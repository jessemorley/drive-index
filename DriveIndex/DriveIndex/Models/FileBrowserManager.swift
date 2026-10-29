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
        guard !isDirectory else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modifiedAt else { return "--" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
