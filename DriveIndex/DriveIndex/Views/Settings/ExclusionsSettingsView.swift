//
//  ExclusionsSettingsView.swift
//  DriveIndex
//
//  Exclusions settings tab
//

import SwiftUI

struct ExclusionsSettingsView: View {
    @Binding var excludedDirectories: String
    @Binding var excludedExtensions: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxLarge) {
                // Excluded Directories
                SettingsSection(
                    title: "Excluded Directories",
                    description: "Directory names to skip during indexing",
                    symbol: "folder.badge.minus"
                ) {
                    TextEditor(text: $excludedDirectories)
                        .font(AppTypography.technicalData)
                        .frame(height: 120)
                        .padding(Spacing.small)
                        .scrollContentBackground(.hidden)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
                    TextEditor(text: $excludedExtensions)
                        .font(AppTypography.technicalData)
                        .frame(height: 120)
                        .padding(Spacing.small)
                        .scrollContentBackground(.hidden)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
    ExclusionsSettingsView(
        excludedDirectories: .constant(".git, node_modules"),
        excludedExtensions: .constant(".tmp, .cache")
    )
    .frame(width: 600, height: 400)
}
