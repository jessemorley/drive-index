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
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxLarge) {
                // Automatic Indexing
                SettingsSection(
                    title: "Automatic Indexing",
                    description: "Monitor drives for file changes and automatically update the index",
                    symbol: "arrow.triangle.2.circlepath"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Toggle(isOn: $fsEventsEnabled) {
                            Text("Enable automatic indexing")
                                .font(DesignSystem.Typography.callout)
                        }
                        .toggleStyle(.switch)
                        .onChange(of: fsEventsEnabled) { _, newValue in
                            autoSaveFSEventsEnabled(newValue)
                        }

                        if fsEventsEnabled {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                                HStack {
                                    Text("Event buffer delay:")
                                        .font(DesignSystem.Typography.callout)
                                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                                    Spacer()

                                    Text("\(Int(fsEventsBufferDelay))s")
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(DesignSystem.Colors.primaryText)
                                        .frame(width: 40, alignment: .trailing)
                                }

                                Slider(value: $fsEventsBufferDelay, in: 5...60, step: 5)
                                    .onChange(of: fsEventsBufferDelay) { _, newValue in
                                        debouncedAutoSaveBufferDelay(newValue)
                                    }

                                Text("How long to wait after file changes before triggering a scan")
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                            }
                            .padding(.top, DesignSystem.Spacing.small)
                        }
                    }
                }

                // Duplicate Detection
                SettingsSection(
                    title: "Duplicate Detection",
                    description: "Configure how duplicate files are detected and analyzed",
                    symbol: "doc.on.doc"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                            HStack {
                                Text("Minimum file size:")
                                    .font(DesignSystem.Typography.callout)
                                    .foregroundStyle(DesignSystem.Colors.secondaryText)

                                Spacer()

                                Text("\(Int(minDuplicateFileSize)) MB")
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.primaryText)
                                    .frame(width: 60, alignment: .trailing)
                            }

                            Slider(value: $minDuplicateFileSize, in: 1...50, step: 1)
                                .onChange(of: minDuplicateFileSize) { _, newValue in
                                    debouncedAutoSaveMinDuplicateSize(newValue)
                                }

                            Text("Only detect duplicates for files larger than this size. Smaller threshold = more thorough but slower. Larger = faster but may miss small duplicates.")
                                .font(DesignSystem.Typography.caption2)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Excluded Directories
                SettingsSection(
                    title: "Excluded Directories",
                    description: "Directory names to skip during indexing",
                    symbol: "folder.badge.minus"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        TagInputView(
                            tags: $excludedDirectories,
                            placeholder: "Type directory name and press comma or return..."
                        )
                        .onChange(of: excludedDirectories) { _, _ in
                            markAsChanged()
                        }

                        Button(action: {
                            excludedDirectories = defaultExcludedDirectories
                            markAsChanged()
                        }) {
                            Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                                .font(DesignSystem.Typography.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }

                // Excluded Extensions
                SettingsSection(
                    title: "Excluded Extensions",
                    description: "File extensions and names to skip",
                    symbol: "doc.badge.gearshape"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        TagInputView(
                            tags: $excludedExtensions,
                            placeholder: "Type extension and press comma or return..."
                        )
                        .onChange(of: excludedExtensions) { _, _ in
                            markAsChanged()
                        }

                        Button(action: {
                            excludedExtensions = defaultExcludedExtensions
                            markAsChanged()
                        }) {
                            Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                                .font(DesignSystem.Typography.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }

                // Excluded Drives
                SettingsSection(
                    title: "Excluded Drives",
                    description: "Drives that won't be automatically indexed",
                    symbol: "externaldrive.badge.minus"
                ) {
                    if excludedDrives.isEmpty {
                        Text("No excluded drives")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                            .italic()
                            .padding(.vertical, DesignSystem.Spacing.small)
                    } else {
                        VStack(spacing: DesignSystem.Spacing.small) {
                            ForEach(excludedDrives, id: \.uuid) { drive in
                                HStack {
                                    Image(systemName: "externaldrive")
                                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                                        .font(DesignSystem.Typography.caption)

                                    Text(drive.name)
                                        .font(DesignSystem.Typography.caption)

                                    Spacer()

                                    Button("Include") {
                                        Task {
                                            await driveMonitor.unexcludeDrive(drive.uuid)
                                            await loadExcludedDrives()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .font(DesignSystem.Typography.caption)
                                }
                                .padding(.vertical, DesignSystem.Spacing.xSmall)
                            }
                        }
                    }
                }

                // Info callout
                HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                    VStack(spacing: 0) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .font(DesignSystem.Typography.title2)
                    }
                    .frame(width: 24)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                        Text("Changes take effect on next scan")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)

                        Text("Existing indexed files won't be removed, only new scans will respect these settings.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignSystem.Spacing.sectionPadding)
            .padding(.vertical, DesignSystem.Spacing.large)
        }
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

        await MainActor.run {
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
