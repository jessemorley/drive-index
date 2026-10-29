//
//  IndexingView.swift
//  DriveIndex
//
//  Indexing configuration view
//

import SwiftUI

struct IndexingView: View {
    @EnvironmentObject var indexManager: IndexManager
    @EnvironmentObject var driveMonitor: DriveMonitor

    @State private var excludedDirectories: [String] = []
    @State private var excludedExtensions: [String] = []
    @State private var excludedDrives: [DriveMetadata] = []
    @State private var localFolders: [String] = []
    @State private var fsEventsEnabled: Bool = true
    @State private var fsEventsBufferDelay: Double = 10.0
    @State private var minDuplicateFileSize: Double = 5.0  // Default 5 MB
    @State private var isLoading: Bool = true
    @State private var hasUnsavedChanges: Bool = false
    @State private var bufferDelayDebounceTask: Task<Void, Never>?
    @State private var minDuplicateSizeDebounceTask: Task<Void, Never>?

    // Default values from FileIndexer
    private let defaultExcludedDirectories = [
        ".git",
        "node_modules",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        "Library",
        "$RECYCLE.BIN",
        "System Volume Information"
    ]

    private let defaultExcludedExtensions = [
        ".tmp",
        ".cache",
        ".DS_Store",
        ".localized",
        ".cof",
        ".cos",
        ".cot",
        ".cop",
        ".comask"
    ]

    var body: some View {
        Form {
            Section("Automatic Indexing") {
                Toggle("Enable automatic indexing", isOn: $fsEventsEnabled)
                    .onChange(of: fsEventsEnabled) { _, newValue in
                        autoSaveFSEventsEnabled(newValue)
                    }

                if fsEventsEnabled {
                    LabeledContent {
                        Slider(value: $fsEventsBufferDelay, in: 5...60, step: 5)
                            .onChange(of: fsEventsBufferDelay) { _, newValue in
                                debouncedAutoSaveBufferDelay(newValue)
                            }
                        Text("\(Int(fsEventsBufferDelay))s")
                            .monospacedDigit()
                            .fixedSize()
                    } label: {
                        Text("Event buffer delay")
                        Text("How long to wait after file changes before triggering a scan")
                    }
                }
            }

            Section {
                ForEach(localFolders, id: \.self) { path in
                    LabeledContent {
                        Button("Remove") {
                            saveLocalFolders(localFolders.filter { $0 != path })
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
                Button("Add Folder…", action: addLocalFolders)
            } header: {
                Text("Local Folders")
            } footer: {
                Text("Folders on this Mac to index for search, duplicates and Capture One. Nothing else on the Mac is scanned. Scan it from Drives after changing these.")
            }

            Section("Duplicate Detection") {
                LabeledContent {
                    Slider(value: $minDuplicateFileSize, in: 1...50, step: 1)
                        .onChange(of: minDuplicateFileSize) { _, newValue in
                            debouncedAutoSaveMinDuplicateSize(newValue)
                        }
                    Text("\(Int(minDuplicateFileSize)) MB")
                        .monospacedDigit()
                        .fixedSize()
                } label: {
                    Text("Minimum file size")
                    Text("Only detect duplicates for files larger than this size. Smaller threshold = more thorough but slower. Larger = faster but may miss small duplicates.")
                }
            }

            Section("Excluded Directories") {
                TagInputView(
                    tags: $excludedDirectories,
                    placeholder: "Type directory name and press comma or return..."
                )
                .onChange(of: excludedDirectories) { _, _ in
                    markAsChanged()
                }

                Button("Restore Defaults") {
                    excludedDirectories = defaultExcludedDirectories
                    markAsChanged()
                }
            }

            Section("Excluded Extensions") {
                TagInputView(
                    tags: $excludedExtensions,
                    placeholder: "Type extension and press comma or return..."
                )
                .onChange(of: excludedExtensions) { _, _ in
                    markAsChanged()
                }

                Button("Restore Defaults") {
                    excludedExtensions = defaultExcludedExtensions
                    markAsChanged()
                }
            }

            Section {
                if excludedDrives.isEmpty {
                    Text("No excluded drives")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(excludedDrives, id: \.uuid) { drive in
                        LabeledContent {
                            Button("Include") {
                                Task {
                                    await driveMonitor.unexcludeDrive(drive.uuid)
                                    await loadExcludedDrives()
                                }
                            }
                        } label: {
                            Label(drive.name, systemImage: "externaldrive")
                        }
                    }
                }
            } header: {
                Text("Excluded Drives")
            } footer: {
                Text("Changes take effect on the next scan. Existing indexed files won't be removed, only new scans will respect these settings.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Indexing")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    saveSettings()
                }
                .disabled(!hasUnsavedChanges)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .task {
            await loadSettings()
        }
    }

    private func loadSettings() async {
        let dirs = await indexManager.getExcludedDirectories()
        let exts = await indexManager.getExcludedExtensions()
        let fsEnabled = await FSEventsMonitor.shared.isEnabled()
        let fsDelay = await FSEventsMonitor.shared.getBufferDelay()

        // Load minimum duplicate file size (default 5MB = 5242880 bytes)
        let minSizeBytes: Int64
        do {
            let minSizeStr = try await DatabaseManager.shared.getSetting("min_duplicate_file_size") ?? "5242880"
            minSizeBytes = Int64(minSizeStr) ?? 5_242_880
        } catch {
            print("Error loading min duplicate file size: \(error)")
            minSizeBytes = 5_242_880
        }

        await loadExcludedDrives()
        let folders = await LocalFolders.load()

        await MainActor.run {
            localFolders = folders
            excludedDirectories = dirs
            excludedExtensions = exts
            fsEventsEnabled = fsEnabled
            fsEventsBufferDelay = fsDelay
            minDuplicateFileSize = Double(minSizeBytes) / 1_048_576.0  // Convert bytes to MB
            isLoading = false
            hasUnsavedChanges = false
        }
    }

    private func loadExcludedDrives() async {
        do {
            let drives = try await DatabaseManager.shared.getExcludedDrives()
            await MainActor.run {
                excludedDrives = drives
            }
        } catch {
            print("Error loading excluded drives: \(error)")
        }
    }

    private func saveSettings() {
        Task {
            do {
                // Filter out empty values
                let dirs = excludedDirectories.filter { !$0.isEmpty }
                let exts = excludedExtensions.filter { !$0.isEmpty }

                try await indexManager.updateExcludedDirectories(dirs)
                try await indexManager.updateExcludedExtensions(exts)

                await MainActor.run {
                    hasUnsavedChanges = false
                }
            } catch {
                print("Error saving settings: \(error)")
            }
        }
    }

    /// Folders on the startup disk only: one elsewhere would be indexed under this Mac
    private func addLocalFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK,
              let startupDisk = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        else { return }
        let added = panel.urls.filter { isMounted($0, uuid: startupDisk) }.map(\.path)
        if added.count < panel.urls.count { NSSound.beep() }
        saveLocalFolders(localFolders + added.filter { !localFolders.contains($0) })
    }

    /// Lists this Mac as a drive while it has folders; removing the last one drops its index
    private func saveLocalFolders(_ folders: [String]) {
        localFolders = folders
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

    private func markAsChanged() {
        hasUnsavedChanges = true
    }

    // Auto-save methods for non-tag settings
    private func autoSaveFSEventsEnabled(_ enabled: Bool) {
        Task {
            await FSEventsMonitor.shared.setEnabled(enabled)
        }
    }

    private func debouncedAutoSaveBufferDelay(_ delay: Double) {
        // Cancel previous task
        bufferDelayDebounceTask?.cancel()

        // Create new debounced task
        bufferDelayDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            guard !Task.isCancelled else { return }

            await FSEventsMonitor.shared.setBufferDelay(delay)
        }
    }

    private func debouncedAutoSaveMinDuplicateSize(_ size: Double) {
        // Cancel previous task
        minDuplicateSizeDebounceTask?.cancel()

        // Create new debounced task
        minDuplicateSizeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            guard !Task.isCancelled else { return }

            do {
                let minSizeBytes = Int64(size * 1_048_576.0)
                try await DatabaseManager.shared.setSetting("min_duplicate_file_size", value: String(minSizeBytes))
            } catch {
                print("Error saving min duplicate file size: \(error)")
            }
        }
    }
}

#Preview {
    IndexingView()
        .environmentObject(IndexManager())
        .environmentObject(DriveMonitor())
}
