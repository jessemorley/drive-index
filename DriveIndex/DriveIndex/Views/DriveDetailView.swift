//
//  DriveDetailView.swift
//  DriveIndex
//
//  Detail view for a single drive, showing storage visualization and actions
//

import SwiftUI

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
            }

            // This Mac shows the folders it indexes instead of a file tree
            if drive.isLocal {
                LocalFoldersSection()
            } else if drive.fileCount > 0 {
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
                            .disabled(indexManager.isIndexing || !driveMonitor.canScan(drive))
                        Button("Show in Finder", action: revealInFinder)
                        if !drive.isLocal {
                            Button("Eject", action: ejectDrive)
                        }
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
            if drive.isConnected && !drive.isLocal && isPointerInWindow {
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
            Image(nsImage: drive.finderIcon)
                .resizable()
                .frame(width: 64, height: 64)

            Text(drive.name)
                .font(.title)
                .foregroundStyle(.primary)

            HStack {
                Text(drive.formattedTotal)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ConnectionChip(isConnected: drive.isConnected)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom)
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

// MARK: - Local Folders

/// The folders indexed on this Mac. Only folders on the startup disk: one elsewhere would be
/// indexed under this Mac.
struct LocalFoldersSection: View {
    @EnvironmentObject var driveMonitor: DriveMonitor

    var body: some View {
        Section {
            ForEach(driveMonitor.localFolders, id: \.self) { path in
                LabeledContent {
                    Button("Remove") {
                        save(driveMonitor.localFolders.filter { $0 != path })
                    }
                } label: {
                    Label {
                        Text((path as NSString).lastPathComponent)
                        Text(path)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.listIcon(name: path, isDirectory: true))
                    }
                }
            }
            Button("Add Folder…", action: addFolders)
        } header: {
            Text("Local Folders")
        } footer: {
            Text("Folders on this Mac to index for search, duplicates and Capture One. Nothing else on the Mac is scanned. Rescan after changing these.")
        }
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK,
              let startupDisk = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        else { return }
        let folders = driveMonitor.localFolders
        let added = panel.urls.filter { isMounted($0, uuid: startupDisk) }.map(\.path)
        if added.count < panel.urls.count { NSSound.beep() }
        save(folders + added.filter { !folders.contains($0) })
    }

    /// Removing the last folder drops the Mac's index
    private func save(_ folders: [String]) {
        driveMonitor.localFolders = folders
        Task {
            do {
                try await LocalFolders.save(folders)
                if folders.isEmpty, let mac = driveMonitor.drives.first(where: \.isLocal) {
                    try await driveMonitor.deleteDrive(mac.id)
                } else {
                    await driveMonitor.loadDrives()
                }
            } catch {
                print("Error saving local folders: \(error)")
            }
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
