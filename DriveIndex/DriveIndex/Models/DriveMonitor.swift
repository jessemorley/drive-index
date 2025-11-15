//
//  DriveMonitor.swift
//  DriveIndex
//
//  Monitors external drive connections using NSWorkspace notifications
//

import Foundation
import AppKit
import SwiftUI

struct DriveInfo: Identifiable {
    let id: String  // UUID
    let name: String
    let path: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let isConnected: Bool
    let lastSeen: Date
    let lastScanDate: Date?
    let fileCount: Int
    let isExcluded: Bool

    var usedCapacity: Int64 {
        totalCapacity - availableCapacity
    }

    var usedPercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity) * 100
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }

    var formattedLastScan: String {
        guard let lastScanDate = lastScanDate else {
            return "Never"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Scanned " + formatter.localizedString(for: lastScanDate, relativeTo: Date())
    }

    var isIndexed: Bool {
        lastScanDate != nil && !isExcluded
    }

    /// Background color based on drive state
    /// - Green with green outline: connected and indexed
    /// - Grey with green outline: connected and unindexed
    /// - Grey: not connected (regardless of indexed state)
    var backgroundColor: Color {
        if !isConnected {
            return Color.secondary.opacity(0.05)
        } else if isIndexed {
            return Color.green.opacity(0.05)
        } else {
            return Color.secondary.opacity(0.05)
        }
    }

    var borderColor: Color? {
        if isConnected {
            return Color.green.opacity(0.2)
        }
        return nil
    }
}

@MainActor
class DriveMonitor: ObservableObject {
    @Published var drives: [DriveInfo] = []
    @Published var pendingDrive: (url: URL, uuid: String, name: String)?
    @Published var showTrackingDialog = false
    private let database = DatabaseManager.shared
    private let fsEventsMonitor = FSEventsMonitor.shared

    init() {
        setupNotifications()
        // Load drives immediately on initialization
        Task {
            await loadDrives()
        }
    }

    private func setupNotifications() {
        let workspace = NSWorkspace.shared

        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(driveDidMount(_:)),
            name: NSWorkspace.didMountNotification,
            object: nil
        )

        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(driveDidUnmount(_:)),
            name: NSWorkspace.didUnmountNotification,
            object: nil
        )

        // Listen for indexing completion to refresh drive list
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(indexingDidComplete(_:)),
            name: .driveIndexingComplete,
            object: nil
        )
    }

    @objc private func indexingDidComplete(_ notification: NSNotification) {
        Task {
            await loadDrives()
        }
    }

    @objc private func driveDidMount(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let volumeURL = userInfo["NSDevicePath"] as? String,
              let url = URL(string: "file://\(volumeURL)") else {
            return
        }

        Task {
            await handleDriveMounted(volumeURL: url)
        }
    }

    @objc private func driveDidUnmount(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let devicePath = userInfo["NSDevicePath"] as? String else {
            return
        }

        Task {
            await handleDriveUnmounted(devicePath: devicePath)
        }
    }

    private func handleDriveMounted(volumeURL: URL) async {
        do {
            let values = try volumeURL.resourceValues(forKeys: [
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeIsInternalKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeUUIDStringKey
            ])

            // Only process external drives (non-internal)
            guard values.volumeIsInternal == false else {
                return
            }

            guard let volumeName = values.volumeName,
                  let uuid = values.volumeUUIDString,
                  let totalCapacity = values.volumeTotalCapacity,
                  values.volumeAvailableCapacity != nil else {
                return
            }

            print("Drive mounted: \(volumeName) (UUID: \(uuid))")

            // Check if drive exists in database and if it's excluded
            let existingMetadata = try await database.getDriveMetadata(uuid)
            let isNewDrive = existingMetadata?.lastScanDate == nil
            let isExcluded = try await database.isDriveExcluded(uuid: uuid)

            // Update database with current capacity info
            let usedCapacity = Int64(totalCapacity) - Int64(values.volumeAvailableCapacity!)
            let metadata = DriveMetadata(
                uuid: uuid,
                name: volumeName,
                lastSeen: Date(),
                totalCapacity: Int64(totalCapacity),
                usedCapacity: usedCapacity,
                lastScanDate: existingMetadata?.lastScanDate,
                fileCount: existingMetadata?.fileCount ?? 0,
                isExcluded: existingMetadata?.isExcluded ?? false
            )

            try await database.upsertDriveMetadata(metadata)

            // Reload drives to update UI
            await loadDrives()

            // Handle new/un-indexed drives or excluded drives
            if isNewDrive && !isExcluded {
                // Show standalone alert asking user if they want to track this drive
                pendingDrive = (url: volumeURL, uuid: uuid, name: volumeName)
                showTrackingAlert()
            } else if !isExcluded {
                // Automatically index existing non-excluded drives
                NotificationCenter.default.post(
                    name: .shouldIndexDrive,
                    object: nil,
                    userInfo: ["driveURL": volumeURL, "driveUUID": uuid]
                )
            }
            // If excluded, do nothing (no indexing)

            // Start FSEvents monitoring for non-excluded drives
            if !isExcluded {
                Task {
                    do {
                        try await fsEventsMonitor.startMonitoring(driveURL: volumeURL, driveUUID: uuid)
                    } catch {
                        print("⚠️ Failed to start FSEvents monitoring: \(error)")
                        // Non-fatal: continue without live monitoring
                    }
                }
            }

        } catch {
            print("Error handling mounted drive: \(error)")
        }
    }

    private func handleDriveUnmounted(devicePath: String) async {
        print("Drive unmounted: \(devicePath)")

        // Try to find UUID from current drives list before reloading
        let unmountedDrive = drives.first { $0.path == devicePath }
        if let uuid = unmountedDrive?.id {
            Task {
                await fsEventsMonitor.stopMonitoring(driveUUID: uuid)
            }
        }

        await loadDrives()
    }

    func loadDrives() async {
        do {
            // Get all drives from database
            let dbDrives = try await database.getAllDriveMetadata()

            // Get currently mounted volumes
            let fileManager = FileManager.default
            guard let mountedURLs = fileManager.mountedVolumeURLs(
                includingResourceValuesForKeys: [
                    .volumeNameKey,
                    .volumeIsRemovableKey,
                    .volumeIsEjectableKey,
                    .volumeIsInternalKey,
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey,
                    .volumeUUIDStringKey
                ],
                options: .skipHiddenVolumes
            ) else {
                return
            }

            var mountedDriveUUIDs: Set<String> = []
            var updatedDrives: [DriveInfo] = []

            // Process currently mounted drives
            for url in mountedURLs {
                do {
                    let values = try url.resourceValues(forKeys: [
                        .volumeNameKey,
                        .volumeIsRemovableKey,
                        .volumeIsEjectableKey,
                        .volumeIsInternalKey,
                        .volumeTotalCapacityKey,
                        .volumeAvailableCapacityKey,
                        .volumeUUIDStringKey
                    ])

                    // Only show external drives (non-internal)
                    guard values.volumeIsInternal == false else {
                        continue
                    }

                    guard let volumeName = values.volumeName,
                          let uuid = values.volumeUUIDString,
                          let totalCapacity = values.volumeTotalCapacity,
                          let availableCapacity = values.volumeAvailableCapacity else {
                        continue
                    }

                    mountedDriveUUIDs.insert(uuid)

                    // Find metadata from database
                    let metadata = dbDrives.first { $0.uuid == uuid }

                    // If drive not in database, create entry
                    if metadata == nil {
                        let usedCapacity = Int64(totalCapacity) - Int64(availableCapacity)
                        let newMetadata = DriveMetadata(
                            uuid: uuid,
                            name: volumeName,
                            lastSeen: Date(),
                            totalCapacity: Int64(totalCapacity),
                            usedCapacity: usedCapacity,
                            lastScanDate: nil,
                            fileCount: 0,
                            isExcluded: false
                        )
                        try? await database.upsertDriveMetadata(newMetadata)
                    }

                    let driveInfo = DriveInfo(
                        id: uuid,
                        name: volumeName,
                        path: url.path,
                        totalCapacity: Int64(totalCapacity),
                        availableCapacity: Int64(availableCapacity),
                        isConnected: true,
                        lastSeen: Date(),
                        lastScanDate: metadata?.lastScanDate,
                        fileCount: metadata?.fileCount ?? 0,
                        isExcluded: metadata?.isExcluded ?? false
                    )

                    updatedDrives.append(driveInfo)

                } catch {
                    print("Error reading drive info: \(error)")
                }
            }

            // Add offline drives from database
            for dbDrive in dbDrives {
                if !mountedDriveUUIDs.contains(dbDrive.uuid) {
                    // For offline drives, calculate available capacity from stored used capacity
                    let availableCapacity = dbDrive.totalCapacity - dbDrive.usedCapacity
                    let driveInfo = DriveInfo(
                        id: dbDrive.uuid,
                        name: dbDrive.name,
                        path: "",
                        totalCapacity: dbDrive.totalCapacity,
                        availableCapacity: availableCapacity,
                        isConnected: false,
                        lastSeen: dbDrive.lastSeen,
                        lastScanDate: dbDrive.lastScanDate,
                        fileCount: dbDrive.fileCount,
                        isExcluded: dbDrive.isExcluded
                    )

                    updatedDrives.append(driveInfo)
                }
            }

            // Sort by connection status (connected first) then by name
            updatedDrives.sort { drive1, drive2 in
                if drive1.isConnected != drive2.isConnected {
                    return drive1.isConnected
                }
                return drive1.name < drive2.name
            }

            // Explicitly update on main actor to ensure UI refresh
            await MainActor.run {
                self.drives = updatedDrives
            }

        } catch {
            print("Error loading drives: \(error)")
        }
    }

    func getDriveURL(for driveInfo: DriveInfo) -> URL? {
        guard driveInfo.isConnected else { return nil }

        let fileManager = FileManager.default
        guard let mountedURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey],
            options: .skipHiddenVolumes
        ) else {
            return nil
        }

        for url in mountedURLs {
            do {
                let values = try url.resourceValues(forKeys: [.volumeUUIDStringKey])
                if values.volumeUUIDString == driveInfo.id {
                    return url
                }
            } catch {
                continue
            }
        }

        return nil
    }

    func deleteDrive(_ driveUUID: String) async throws {
        print("🗑️ DriveMonitor: deleting drive with UUID: \(driveUUID)")
        try await database.deleteDrive(driveUUID)
        await loadDrives()
    }

    // MARK: - Drive Tracking Actions

    /// Track a new drive (start indexing it)
    func trackDrive() {
        guard let pending = pendingDrive else { return }

        showTrackingDialog = false

        // Trigger indexing for this drive
        NotificationCenter.default.post(
            name: .shouldIndexDrive,
            object: nil,
            userInfo: ["driveURL": pending.url, "driveUUID": pending.uuid]
        )

        pendingDrive = nil
    }

    /// Show tracking dialog as a standalone alert
    func showTrackingAlert() {
        guard let pending = pendingDrive else { return }

        let alert = NSAlert()
        alert.messageText = "Track Drive?"
        alert.informativeText = "Would you like to track \"\(pending.name)\"? Tracking will index all files on the drive for search."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Track")
        alert.addButton(withTitle: "Don't Track")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn: // Track
            trackDrive()
        case .alertSecondButtonReturn: // Don't Track
            Task {
                await excludeDrive()
            }
        default: // Cancel
            cancelTrackingDialog()
        }
    }

    /// Exclude a drive from automatic tracking
    func excludeDrive() async {
        guard let pending = pendingDrive else { return }

        showTrackingDialog = false

        do {
            try await database.setDriveExcluded(uuid: pending.uuid, excluded: true)
            print("✅ Drive excluded: \(pending.name)")

            // Stop FSEvents monitoring for excluded drive
            await fsEventsMonitor.stopMonitoring(driveUUID: pending.uuid)

            await loadDrives()
        } catch {
            print("❌ Error excluding drive: \(error)")
        }

        pendingDrive = nil
    }

    /// Un-exclude a drive (allow it to be tracked again)
    func unexcludeDrive(_ driveUUID: String) async {
        do {
            try await database.setDriveExcluded(uuid: driveUUID, excluded: false)
            print("✅ Drive un-excluded: \(driveUUID)")

            // Start FSEvents monitoring if drive is currently connected
            if let driveInfo = drives.first(where: { $0.id == driveUUID }),
               let driveURL = getDriveURL(for: driveInfo) {
                Task {
                    do {
                        try await fsEventsMonitor.startMonitoring(driveURL: driveURL, driveUUID: driveUUID)
                    } catch {
                        print("⚠️ Failed to start FSEvents monitoring: \(error)")
                    }
                }
            }

            await loadDrives()
        } catch {
            print("❌ Error un-excluding drive: \(error)")
        }
    }

    /// Cancel the tracking dialog without taking action
    func cancelTrackingDialog() {
        showTrackingDialog = false
        pendingDrive = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let shouldIndexDrive = Notification.Name("shouldIndexDrive")
}
