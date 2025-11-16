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
    @State private var isLoading: Bool = true
    @State private var hasUnsavedChanges: Bool = false

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
                        .onChange(of: fsEventsEnabled) { _, _ in
                            hasUnsavedChanges = true
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
                                    .onChange(of: fsEventsBufferDelay) { _, _ in
                                        hasUnsavedChanges = true
                                    }

                                Text("How long to wait after file changes before triggering a scan")
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                            }
                            .padding(.top, DesignSystem.Spacing.small)
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
                            hasUnsavedChanges = true
                        }

                        Button(action: {
                            excludedDirectories = defaultExcludedDirectories
                            hasUnsavedChanges = true
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
                            hasUnsavedChanges = true
                        }

                        Button(action: {
                            excludedExtensions = defaultExcludedExtensions
                            hasUnsavedChanges = true
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

        await loadExcludedDrives()

        await MainActor.run {
            excludedDirectories = dirs
            excludedExtensions = exts
            fsEventsEnabled = fsEnabled
            fsEventsBufferDelay = fsDelay
            isLoading = false
            hasUnsavedChanges = false
        }
    }

    private func loadExcludedDrives() async {
        do {
            let drives = try await DatabaseManager.shared.getExcludedDrives()
            await MainActor.run {
                withAnimation(DesignSystem.Animation.standard) {
                    excludedDrives = drives
                }
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

                // Update FSEvents settings
                await FSEventsMonitor.shared.setEnabled(fsEventsEnabled)
                await FSEventsMonitor.shared.setBufferDelay(fsEventsBufferDelay)

                await MainActor.run {
                    hasUnsavedChanges = false
                }
            } catch {
                print("Error saving settings: \(error)")
            }
        }
    }
}

#Preview {
    IndexingView()
        .environmentObject(IndexManager())
        .environmentObject(DriveMonitor())
}
