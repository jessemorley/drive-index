//
//  DriveDetailView.swift
//  DriveIndex
//
//  Detail view for a single drive, showing storage visualization and actions
//

import SwiftUI
import UniformTypeIdentifiers

struct DriveDetailView: View {
    let drive: DriveInfo
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @State private var showDeleteConfirmation = false
    @State private var isPointerInWindow = false

    var body: some View {
        Form {
            Section {
                infoRows
                    .textSelection(.enabled)
            } header: {
                hero
            }

            // Storage and files work for offline drives via the database
            if drive.fileCount > 0 {
                Section("Storage") {
                    StorageVisualizationView(drive: drive)
                        .id(drive.id)
                }

                Section("Files") {
                    FileBrowserView(drive: drive)
                        .id(drive.id)  // Force new view instance for each drive
                }
            }

            if drive.isConnected {
                Section {
                    HStack {
                        Spacer()
                        Button(drive.lastScanDate == nil ? "Scan" : "Rescan", action: rescanDrive)
                            .disabled(indexManager.isIndexing)
                        Button("Show in Finder", action: revealInFinder)
                        Button("Eject", action: ejectDrive)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Covers the toolbar too, so the pointer can reach the toolbar Eject button without it vanishing
        .background {
            Color.clear
                .ignoresSafeArea()
                .onHover { isPointerInWindow = $0 }
        }
        .navigationTitle(drive.name)
        .navigationSubtitle(drive.formattedTotal)
        .toolbar {
            if drive.isConnected && isPointerInWindow {
                ToolbarItem(placement: .primaryAction) {
                    Button("Eject", systemImage: "eject", action: ejectDrive)
                        .help("Eject drive")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", systemImage: "trash") {
                    showDeleteConfirmation = true
                }
                .help("Remove drive from database")
            }
        }
        .confirmationDialog(
            "Are you sure you want to remove \"\(drive.name)\" from the database?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await driveMonitor.deleteDrive(drive.id)
                    } catch {
                        print("Error deleting drive: \(error)")
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All indexed files for this drive will be permanently deleted.")
        }
    }

    // MARK: - Header

    private var hero: some View {
        VStack {
            Image(nsImage: driveIcon)
                .resizable()
                .frame(width: 64, height: 64)

            Text(drive.name)
                .font(.title)
                .foregroundStyle(.primary)

            Label {
                Text("\(drive.formattedTotal) · \(drive.isConnected ? "Connected" : "Disconnected")")
            } icon: {
                ConnectionDot(isConnected: drive.isConnected)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom)
    }

    /// The volume's own Finder icon when mounted, Finder's generic external drive icon when offline
    private var driveIcon: NSImage {
        if FileManager.default.fileExists(atPath: drive.path) {
            return NSWorkspace.shared.icon(forFile: drive.path)
        }
        // ponytail: not public API; falls back to the generic volume (folder-looking) icon if Apple moves it
        return NSImage(contentsOfFile: "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/External.icns")
            ?? NSWorkspace.shared.icon(for: .volume)
    }

    @ViewBuilder
    private var infoRows: some View {
        LabeledContent("Files Indexed", value: drive.fileCount > 0 ? "\(drive.fileCount.formatted()) files" : "Not indexed")
        LabeledContent("Last Scanned", value: drive.formattedLastScan)
        LabeledContent("UUID", value: drive.id)
    }

    // MARK: - Actions

    private func rescanDrive() {
        // Un-exclude drive if it was excluded
        Task {
            await driveMonitor.unexcludeDrive(drive.id)
        }

        // Trigger drive rescan
        if let driveURL = driveMonitor.getDriveURL(for: drive) {
            Task {
                await indexManager.indexDrive(url: driveURL, uuid: drive.id)
            }
        }
    }

    private func revealInFinder() {
        if let driveURL = driveMonitor.getDriveURL(for: drive) {
            NSWorkspace.shared.open(driveURL)
        }
    }

    private func ejectDrive() {
        if let driveURL = driveMonitor.getDriveURL(for: drive) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: driveURL)
        }
    }
}

// MARK: - Preview

#Preview {
    let scanDate = Date(timeIntervalSinceNow: -3600)
    let drive = DriveInfo(
        id: "test-uuid",
        name: "My External Drive",
        path: "/Volumes/MyDrive",
        totalCapacity: 2_000_000_000_000,
        availableCapacity: 900_000_000_000,
        isConnected: true,
        lastSeen: Date(),
        lastScanDate: scanDate,
        fileCount: 15432,
        isExcluded: false
    )
    // Prime the caches so the preview shows storage and files without a database
    StorageCache.shared.set(driveUUID: drive.id, breakdown: StorageBreakdown(
        driveUUID: drive.id,
        totalCapacity: drive.totalCapacity,
        usedCapacity: drive.usedCapacity,
        categories: [(StorageCategory.media, 0.32), (.documents, 0.1), (.apps, 0.05), (.system, 0.03), (.other, 0.05)].map {
            .init(category: $0.0, size: Int64(Double(drive.totalCapacity) * $0.1), fileCount: 0, percentage: $0.1)
        }
    ), scanDate: scanDate)
    FileBrowserCache.shared.set(driveUUID: drive.id, rootItems: [
        FileBrowserItem(id: 1, name: "Photos", relativePath: "Photos", size: 0, createdAt: nil, modifiedAt: scanDate, isDirectory: true),
        FileBrowserItem(id: 2, name: "Projects", relativePath: "Projects", size: 0, createdAt: nil, modifiedAt: scanDate, isDirectory: true),
        FileBrowserItem(id: 3, name: "Backup.dmg", relativePath: "Backup.dmg", size: 64_000_000_000, createdAt: nil, modifiedAt: Date(timeIntervalSinceNow: -86400 * 9), isDirectory: false),
        FileBrowserItem(id: 4, name: "Notes.md", relativePath: "Notes.md", size: 12_400, createdAt: nil, modifiedAt: Date(timeIntervalSinceNow: -86400 * 2), isDirectory: false),
    ], scanDate: scanDate)

    return NavigationStack {
        DriveDetailView(drive: drive)
            .environmentObject(DriveMonitor())
            .environmentObject(IndexManager())
    }
    .frame(width: 480, height: 1300)  // detail column at the main window's minimum width
}
