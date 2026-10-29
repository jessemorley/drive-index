//
//  FileRow.swift
//  DriveIndex
//
//  File list row and its display model, used by SearchView
//

import SwiftUI

struct FileDisplayItem: Identifiable {
    let id: Int64
    let name: String
    let relativePath: String
    let size: Int64
    let driveUUID: String
    let driveName: String
    let modifiedAt: Date?
    let createdAt: Date?
    let isConnected: Bool
    let isDirectory: Bool

    var kind: String {
        // Folders are always "Folder"
        if isDirectory {
            return "Folder"
        }

        let ext = (name as NSString).pathExtension.lowercased()

        // Common file type mappings
        switch ext {
        case "pdf": return "PDF Document"
        case "doc", "docx": return "Word Document"
        case "xls", "xlsx": return "Excel Spreadsheet"
        case "ppt", "pptx": return "PowerPoint Presentation"
        case "txt": return "Plain Text"
        case "rtf": return "Rich Text Document"
        case "jpg", "jpeg": return "JPEG Image"
        case "png": return "PNG Image"
        case "gif": return "GIF Image"
        case "svg": return "SVG Image"
        case "heic", "heif": return "HEIC Image"
        case "tiff", "tif": return "TIFF Image"
        case "bmp": return "BMP Image"
        case "webp": return "WebP Image"
        // Raw image formats
        case "nef": return "Nikon RAW Image"
        case "cr2", "cr3": return "Canon RAW Image"
        case "arw": return "Sony RAW Image"
        case "dng": return "Digital Negative"
        case "raf": return "Fujifilm RAW Image"
        case "orf": return "Olympus RAW Image"
        case "rw2": return "Panasonic RAW Image"
        case "pef": return "Pentax RAW Image"
        case "srw": return "Samsung RAW Image"
        case "raw": return "RAW Image"
        case "mp4", "mov": return "Video"
        case "mp3", "m4a", "wav": return "Audio"
        case "zip", "tar", "gz": return "Archive"
        case "dmg": return "Disk Image"
        case "app": return "Application"
        case "pkg": return "Installer Package"
        case "swift": return "Swift Source"
        case "py": return "Python Script"
        case "js": return "JavaScript"
        case "html": return "HTML Document"
        case "css": return "CSS Stylesheet"
        case "json": return "JSON File"
        case "md": return "Markdown Document"
        default:
            if ext.isEmpty {
                return "Document"
            }
            return ext.uppercased() + " File"
        }
    }

    var formattedSize: String {
        if isDirectory {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modifiedAt ?? createdAt else {
            return "—" // Em dash for search results without dates
        }

        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return "Today, " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday, " + formatter.string(from: date)
        } else if calendar.dateComponents([.day], from: date, to: Date()).day ?? 0 < 7 {
            formatter.dateFormat = "EEEE, h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

struct FileRow: View {
    let file: FileDisplayItem
    let isHovered: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // File icon and name (flexible)
            HStack(spacing: DesignSystem.Spacing.medium) {
                fileIcon
                    .frame(width: 24)

                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    Text(file.name)
                        .font(DesignSystem.Typography.body)
                        .lineLimit(1)

                    Text("—")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    Text(file.relativePath)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Size (fixed width)
            Text(file.formattedSize)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 80, alignment: .trailing)

            // Kind (fixed width)
            Text(file.kind)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            // Drive (fixed width) with status indicator
            HStack(spacing: DesignSystem.Spacing.xSmall) {
                Circle()
                    .fill(file.isConnected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)

                Text(file.driveName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)

            // Date Added (fixed width)
            Text(file.formattedDate)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? DesignSystem.Colors.cardBackgroundHover : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
    }

    private var fileIcon: some View {
        let iconName: String
        let iconColor: Color

        // Show folder icon for directories
        if file.isDirectory {
            iconName = "folder.fill"
            iconColor = .blue
        } else {
            let ext = (file.name as NSString).pathExtension.lowercased()

            switch ext {
            case "pdf":
                iconName = "doc.fill"
                iconColor = .red
            case "doc", "docx":
                iconName = "doc.text.fill"
                iconColor = .blue
            case "xls", "xlsx":
                iconName = "tablecells.fill"
                iconColor = .green
            case "ppt", "pptx":
                iconName = "square.fill.text.grid.1x2"
                iconColor = .orange
            case "txt", "rtf":
                iconName = "doc.plaintext.fill"
                iconColor = .gray
            case "jpg", "jpeg", "png", "gif", "svg", "heic", "heif", "tiff", "tif", "bmp", "webp",
                 "nef", "cr2", "cr3", "arw", "dng", "raf", "orf", "rw2", "pef", "srw", "raw":
                iconName = "photo.fill"
                iconColor = .purple
            case "mp4", "mov":
                iconName = "video.fill"
                iconColor = .pink
            case "mp3", "m4a", "wav":
                iconName = "music.note"
                iconColor = .orange
            case "zip", "tar", "gz":
                iconName = "doc.zipper"
                iconColor = .gray
            case "dmg":
                iconName = "externaldrive.fill"
                iconColor = .gray
            case "app":
                iconName = "app.fill"
                iconColor = .blue
            case "swift":
                iconName = "chevron.left.forwardslash.chevron.right"
                iconColor = .orange
            case "py", "js", "html", "css":
                iconName = "chevron.left.forwardslash.chevron.right"
                iconColor = .green
            default:
                iconName = "doc.fill"
                iconColor = .blue
            }
        }

        return Image(systemName: iconName)
            .foregroundColor(iconColor)
            .font(.title3)
    }
}
