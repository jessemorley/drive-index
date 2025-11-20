//
//  MediaInspectorView.swift
//  DriveIndex
//
//  Inspector panel that displays file metadata and thumbnails
//

import SwiftUI

struct MediaInspectorView: View {
    let file: FileDisplayItem

    @State private var thumbnail: NSImage?
    @State private var isLoadingThumbnail = false
    @State private var thumbnailError: Error?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                // Thumbnail placeholder
                thumbnailSection

                // File information
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    sectionHeader("File Information")

                    InfoRow(label: "Name", value: file.name)
                    InfoRow(label: "Type", value: file.kind)
                    InfoRow(label: "Size", value: file.formattedSize)
                }

                // Location information
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    sectionHeader("Location")

                    InfoRow(label: "Drive", value: driveStatus)
                    InfoRow(label: "Path", value: file.relativePath)
                }

                // Date information
                if file.createdAt != nil || file.modifiedAt != nil {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        sectionHeader("Dates")

                        if let createdAt = file.createdAt {
                            InfoRow(label: "Created", value: formatDate(createdAt))
                        }

                        if let modifiedAt = file.modifiedAt {
                            InfoRow(label: "Modified", value: formatDate(modifiedAt))
                        }
                    }
                }

                Spacer()
            }
            .padding(DesignSystem.Spacing.cardPadding)
        }
        .frame(width: 280)
        .background(DesignSystem.Colors.windowBackground)
        .task(id: file.id) {
            await loadThumbnail()
        }
    }

    // MARK: - Thumbnail Section

    private var thumbnailSection: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.cardBackgroundDefault)
                .frame(height: 200)
                .overlay(
                    Group {
                        if isLoadingThumbnail {
                            ProgressView()
                                .controlSize(.large)
                        } else if let thumbnail = thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                        } else {
                            Image(systemName: fileIconName)
                                .font(.system(size: 64))
                                .foregroundColor(fileIconColor.opacity(0.3))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(DesignSystem.Typography.caption)
            .foregroundColor(DesignSystem.Colors.tertiaryText)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var driveStatus: String {
        let status = file.isConnected ? "●" : "○"
        return "\(status) \(file.driveName)"
    }

    // MARK: - File Icon

    private var fileIconName: String {
        if file.isDirectory {
            return "folder.fill"
        }

        let ext = (file.name as NSString).pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg", "png", "gif", "svg", "heic", "heif", "tiff", "tif", "bmp", "webp",
             "nef", "cr2", "cr3", "arw", "dng", "raf", "orf", "rw2", "pef", "srw", "raw":
            return "photo.fill"
        case "mp4", "mov":
            return "video.fill"
        case "mp3", "m4a", "wav":
            return "music.note"
        case "pdf":
            return "doc.fill"
        default:
            return "doc.fill"
        }
    }

    private var fileIconColor: Color {
        if file.isDirectory {
            return .blue
        }

        let ext = (file.name as NSString).pathExtension.lowercased()

        switch ext {
        case "jpg", "jpeg", "png", "gif", "svg", "heic", "heif", "tiff", "tif", "bmp", "webp",
             "nef", "cr2", "cr3", "arw", "dng", "raf", "orf", "rw2", "pef", "srw", "raw":
            return .purple
        case "mp4", "mov":
            return .pink
        case "mp3", "m4a", "wav":
            return .orange
        case "pdf":
            return .red
        default:
            return .blue
        }
    }

    // MARK: - Date Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnail() async {
        // Only load thumbnails for media files
        guard isMediaFile() else { return }

        // Only load if file is connected
        guard file.isConnected else { return }

        isLoadingThumbnail = true
        thumbnailError = nil

        do {
            // Construct file URL
            let volumePath = "/Volumes/\(file.driveName)"
            let fullPath = volumePath + "/" + file.relativePath
            let fileURL = URL(fileURLWithPath: fullPath)

            // Check if file exists before trying to generate thumbnail
            guard FileManager.default.fileExists(atPath: fullPath) else {
                isLoadingThumbnail = false
                return
            }

            // Get or generate thumbnail
            let loadedThumbnail = try await ThumbnailCache.shared.getThumbnail(
                for: file.id,
                fileURL: fileURL
            )

            thumbnail = loadedThumbnail
        } catch {
            thumbnailError = error
            print("Failed to load thumbnail for \(file.name): \(error.localizedDescription)")
        }

        isLoadingThumbnail = false
    }

    private func isMediaFile() -> Bool {
        let ext = (file.name as NSString).pathExtension.lowercased()
        let mediaExtensions: Set<String> = [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp",
            "nef", "cr2", "cr3", "arw", "dng", "raf", "orf", "rw2", "pef", "srw", "raw",
            "mp4", "mov", "m4v", "avi",
            "pdf"
        ]
        return mediaExtensions.contains(ext)
    }
}

// MARK: - Info Row Component

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)

            Text(value)
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.primaryText)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview {
    MediaInspectorView(
        file: FileDisplayItem(
            id: 1,
            name: "example-photo.jpg",
            relativePath: "Photos/2024/January/example-photo.jpg",
            size: 2_458_624,
            driveUUID: "12345",
            driveName: "My Drive",
            modifiedAt: Date(),
            createdAt: Date(),
            isConnected: true,
            isDirectory: false
        )
    )
}
