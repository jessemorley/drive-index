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

                    Text("Common patterns: .git, node_modules, Library, .Trashes, Cache")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
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

                    Text("Common patterns: .tmp, .cache, .DS_Store, .localized, Thumbs.db")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
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
    }
}

#Preview {
    ConfigView(
        excludedDirectories: .constant([".git", "node_modules", "Library"]),
        excludedExtensions: .constant([".tmp", ".cache", ".DS_Store"]),
        keyboardShortcut: .constant(.default)
    )
    .frame(width: 600, height: 400)
}
