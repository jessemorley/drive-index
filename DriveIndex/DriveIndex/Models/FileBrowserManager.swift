//
//  FileBrowserManager.swift
//  DriveIndex
//
//  Manages hierarchical file browsing for indexed drives
//

import Foundation

struct FileBrowserItem: Identifiable, Hashable {
    let id: Int64
    let name: String
    let relativePath: String
    let size: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let isDirectory: Bool

    var formattedSize: String {
        guard !isDirectory else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modifiedAt else { return "--" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var fileIcon: String {
        if isDirectory {
            return "folder.fill"
        }

        // Determine icon based on file extension
        let ext = (relativePath as NSString).pathExtension.lowercased()

        switch ext {
        case "pdf":
            return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic", "svg", "webp":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv", "m4v":
            return "film.fill"
        case "mp3", "m4a", "wav", "flac", "aac":
            return "music.note"
        case "zip", "tar", "gz", "rar", "7z":
            return "doc.zipper"
        case "txt", "md", "rtf":
            return "doc.text.fill"
        case "doc", "docx", "pages":
            return "doc.richtext.fill"
        case "xls", "xlsx", "numbers":
            return "tablecells.fill"
        case "ppt", "pptx", "key":
            return "rectangle.on.rectangle.angled"
        case "swift", "js", "py", "java", "cpp", "c", "h", "m", "go", "rs":
            return "chevron.left.forwardslash.chevron.right"
        case "app":
            return "app.fill"
        case "dmg":
            return "opticaldiscdrive.fill"
        default:
            return "doc.fill"
        }
    }
}

actor FileBrowserManager {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// Get children of a directory (or root if parentPath is empty)
    func getChildren(driveUUID: String, parentPath: String) async throws -> [FileBrowserItem] {
        let entries = try await databaseManager.getDirectoryChildren(driveUUID: driveUUID, parentPath: parentPath)

        return entries.map { entry in
            FileBrowserItem(
                id: entry.id ?? 0,
                name: entry.name,
                relativePath: entry.relativePath,
                size: entry.size,
                createdAt: entry.createdAt,
                modifiedAt: entry.modifiedAt,
                isDirectory: entry.isDirectory
            )
        }
    }
}
