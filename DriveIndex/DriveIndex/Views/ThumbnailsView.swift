//
//  ThumbnailsView.swift
//  DriveIndex
//
//  Thumbnail generation configuration view
//

import SwiftUI

struct ThumbnailsView: View {
    @AppStorage("thumbnailGenerationEnabled") private var thumbnailGenerationEnabled: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxLarge) {
                // Title
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                    Text("Thumbnails")
                        .font(DesignSystem.Typography.largeTitle)
                    Text("Configure thumbnail generation settings")
                        .secondaryText()
                }

                // Thumbnail Generation Section
                SettingsSection(
                    title: "Thumbnail Generation",
                    description: "Enable or disable thumbnail generation for media files. When enabled, thumbnails are generated during or after indexing to provide previews in the inspector panel.",
                    symbol: "photo"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Toggle("Enable thumbnail generation", isOn: $thumbnailGenerationEnabled)
                            .toggleStyle(.switch)

                        if !thumbnailGenerationEnabled {
                            HStack(spacing: DesignSystem.Spacing.small) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text("Thumbnail generation will be disabled. The inspector panel will show file icons instead of previews.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, DesignSystem.Spacing.small)
                        }
                    }
                }

                // Information Section
                SettingsSection(
                    title: "About Thumbnails",
                    description: "",
                    symbol: "info.circle"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        ThumbnailInfoRow(
                            icon: "photo.on.rectangle",
                            title: "Supported Formats",
                            description: "Thumbnails are generated for images (JPEG, PNG, HEIC) and RAW files (NEF, CR2, ARW, DNG). Video and CR3 files are currently skipped."
                        )

                        Divider()

                        ThumbnailInfoRow(
                            icon: "externaldrive",
                            title: "Cache Size",
                            description: "Thumbnails are cached on disk with a 500MB limit. Oldest thumbnails are automatically evicted when the limit is reached."
                        )

                        Divider()

                        ThumbnailInfoRow(
                            icon: "speedometer",
                            title: "Performance",
                            description: "Thumbnail generation runs in the background with conservative resource usage to avoid memory pressure."
                        )

                        Divider()

                        ThumbnailInfoRow(
                            icon: "arrow.clockwise",
                            title: "Changes Take Effect",
                            description: "Changes will apply to new thumbnail generation operations. Existing thumbnails in the cache are not affected."
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

// MARK: - Thumbnail Info Row Component

private struct ThumbnailInfoRow: View {
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
    ThumbnailsView()
        .frame(width: 600, height: 400)
}
