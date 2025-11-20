//
//  DuplicatesView.swift
//  DriveIndex
//
//  Duplicate detection configuration view
//

import SwiftUI

struct DuplicatesView: View {
    @AppStorage("duplicateHashingEnabled") private var duplicateHashingEnabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxLarge) {
                // Title
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    Text("Duplicates")
                        .font(DesignSystem.Typography.largeTitle)
                    Text("Configure duplicate file detection settings")
                        .secondaryText()
                }

                // Duplicate Detection Section
                SettingsSection(
                    title: "Duplicate Detection",
                    description: "Enable or disable file hash computation for duplicate detection. When enabled, file hashes are computed during indexing to identify duplicate files.",
                    symbol: "doc.on.doc"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Toggle("Enable duplicate detection", isOn: $duplicateHashingEnabled)
                            .toggleStyle(.switch)

                        if !duplicateHashingEnabled {
                            HStack(spacing: DesignSystem.Spacing.small) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text("Duplicate detection will be disabled. File hashes will not be computed during indexing.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, DesignSystem.Spacing.small)
                        }
                    }
                }

                // Information Section
                SettingsSection(
                    title: "About Duplicate Detection",
                    description: "",
                    symbol: "info.circle"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        DuplicateInfoRow(
                            icon: "speedometer",
                            title: "Performance Impact",
                            description: "Computing file hashes requires reading file contents, which can slow down indexing for large drives."
                        )

                        Divider()

                        DuplicateInfoRow(
                            icon: "chart.bar",
                            title: "Hash Algorithm",
                            description: "Uses XXHash64 for fast, non-cryptographic hashing optimized for duplicate detection."
                        )

                        Divider()

                        DuplicateInfoRow(
                            icon: "arrow.clockwise",
                            title: "Changes Take Effect",
                            description: "Changes will apply to new indexing operations. Existing hashes in the database are not affected."
                        )
                    }
                }

                Spacer()
            }
            .padding(DesignSystem.Spacing.sectionPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Duplicate Info Row Component

private struct DuplicateInfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xSmall)
    }
}

#Preview {
    DuplicatesView()
        .frame(width: 600, height: 400)
}
