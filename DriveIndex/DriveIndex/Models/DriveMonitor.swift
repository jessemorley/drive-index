//
//  DriveMonitor.swift
//  DriveIndex
//
//  Monitors external drive connections using NSWorkspace notifications
//

import Foundation
import AppKit

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
}

@MainActor
class DriveMonitor: ObservableObject {
    @Published var drives: [DriveInfo] = []
    private let database = DatabaseManager.shared

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

            // Update database
            let usedCapacity = Int64(totalCapacity) - Int64(values.volumeAvailableCapacity!)
            let metadata = DriveMetadata(
                uuid: uuid,
                name: volumeName,
                lastSeen: Date(),
                totalCapacity: Int64(totalCapacity),
                usedCapacity: usedCapacity,
                lastScanDate: nil,
                fileCount: 0
            )

            try await database.upsertDriveMetadata(metadata)

            // Reload drives to update UI
            await loadDrives()

            // Trigger indexing
            NotificationCenter.default.post(
                name: .shouldIndexDrive,
                object: nil,
                userInfo: ["driveURL": volumeURL, "driveUUID": uuid]
            )

        } catch {
            print("Error handling mounted drive: \(error)")
        }
    }

    private func handleDriveUnmounted(devicePath: String) async {
        print("Drive unmounted: \(devicePath)")
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
                            fileCount: 0
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
                        fileCount: metadata?.fileCount ?? 0
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
                        fileCount: dbDrive.fileCount
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
}

// MARK: - Notification Names

extension Notification.Name {
    static let shouldIndexDrive = Notification.Name("shouldIndexDrive")
}
