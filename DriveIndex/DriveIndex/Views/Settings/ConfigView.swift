//
//  ConfigView.swift
//  DriveIndex
//
//  Config settings tab
//

import SwiftUI

struct ConfigView: View {
    @Binding var excludedDirectories: [String]
    @Binding var excludedExtensions: [String]
    @Binding var keyboardShortcut: KeyboardShortcut?
    @EnvironmentObject var driveMonitor: DriveMonitor

    @State private var excludedDrives: [DriveMetadata] = []

    var onRestoreDirectoriesDefaults: () -> Void
    var onRestoreExtensionsDefaults: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxLarge) {
                // Keyboard Shortcut
                SettingsSection(
                    title: "Global Shortcut",
                    description: "Keyboard shortcut to open the search window",
                    symbol: "keyboard"
                ) {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        ShortcutRecorder(shortcut: $keyboardShortcut)

                        Text("Press a key combination with at least one modifier (⌘, ⌃, ⌥, or ⇧)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                // Excluded Directories
                SettingsSection(
                    title: "Excluded Directories",
                    description: "Directory names to skip during indexing",
                    symbol: "folder.badge.minus"
                ) {
                    TagInputView(
                        tags: $excludedDirectories,
                        placeholder: "Type directory name and press comma or return..."
                    )

                    Button(action: onRestoreDirectoriesDefaults) {
                        Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }

                // Excluded Extensions
                SettingsSection(
                    title: "Excluded Extensions",
                    description: "File extensions and names to skip",
                    symbol: "doc.badge.gearshape"
                ) {
                    TagInputView(
                        tags: $excludedExtensions,
                        placeholder: "Type extension and press comma or return..."
                    )

                    Button(action: onRestoreExtensionsDefaults) {
                        Label("Restore Defaults", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }

                // Excluded Drives
                SettingsSection(
                    title: "Excluded Drives",
                    description: "Drives that won't be automatically indexed",
                    symbol: "externaldrive.badge.minus"
                ) {
                    if excludedDrives.isEmpty {
                        Text("No excluded drives")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.vertical, Spacing.small)
                    } else {
                        VStack(spacing: Spacing.small) {
                            ForEach(excludedDrives, id: \.uuid) { drive in
                                HStack {
                                    Image(systemName: "externaldrive")
                                        .foregroundColor(.secondary)
                                        .font(.caption)

                                    Text(drive.name)
                                        .font(.caption)

                                    Spacer()

                                    Button("Include") {
                                        Task {
                                            await driveMonitor.unexcludeDrive(drive.uuid)
                                            await loadExcludedDrives()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .font(.caption)
                                }
                                .padding(.vertical, Spacing.xSmall)
                            }
                        }
                    }
                }

                // Info callout
                HStack(alignment: .top, spacing: Spacing.medium) {
                    VStack(spacing: 0) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    }
                    .frame(width: 24)

                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text("Changes take effect on next scan")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text("Existing indexed files won't be removed, only new scans will respect these settings.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(Spacing.medium)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(Spacing.Container.horizontalPadding)
            .padding(.vertical, Spacing.large)
        }
        .onAppear {
            Task {
                await loadExcludedDrives()
            }
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
}

#Preview {
    ConfigView(
        excludedDirectories: .constant([".git", "node_modules", "Library"]),
        excludedExtensions: .constant([".tmp", ".cache", ".DS_Store"]),
        keyboardShortcut: .constant(.default),
        onRestoreDirectoriesDefaults: {},
        onRestoreExtensionsDefaults: {}
    )
    .frame(width: 600, height: 400)
}
