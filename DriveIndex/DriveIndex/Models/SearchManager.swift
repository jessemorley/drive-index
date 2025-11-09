//
//  SearchManager.swift
//  DriveIndex
//
//  Manages file searching using FTS5 full-text search
//

import Foundation
import SQLite3

struct SearchResult: Identifiable, Hashable {
    let id: Int64
    let name: String
    let relativePath: String
    let driveUUID: String
    let driveName: String
    var isConnected: Bool
}

actor SearchManager {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    /// Searches indexed files using FTS5 with the same logic as Raycast extension
    func search(_ searchText: String) async throws -> [SearchResult] {
        // Step 1: Trim and validate
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        // Step 2: Escape single quotes for SQL
        let escaped = trimmed.replacingOccurrences(of: "'", with: "''")

        // Step 3: Remove FTS5 special characters
        let cleaned = escaped.replacingOccurrences(
            of: "[\":.]+",
            with: "",
            options: .regularExpression
        )

        guard !cleaned.isEmpty else {
            return []
        }

        // Step 4: Add wildcard for prefix matching
        let fts5Term = cleaned + "*"

        // Step 5: Build FTS5 query matching Raycast logic
        let sql = """
        SELECT
            f.id,
            f.name,
            f.relative_path,
            f.drive_uuid,
            d.name as drive_name
        FROM files_fts
        JOIN files f ON f.id = files_fts.rowid
        JOIN drives d ON d.uuid = f.drive_uuid
        WHERE files_fts MATCH 'name:\(fts5Term)'
        ORDER BY bm25(files_fts)
        LIMIT 100
        """

        return try await databaseManager.executeQuery(sql) { stmt in
            var results: [SearchResult] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let name = String(cString: sqlite3_column_text(stmt, 1))
                let relativePath = String(cString: sqlite3_column_text(stmt, 2))
                let driveUUID = String(cString: sqlite3_column_text(stmt, 3))
                let driveName = String(cString: sqlite3_column_text(stmt, 4))

                let isConnected = isDriveMounted(driveName)

                results.append(SearchResult(
                    id: id,
                    name: name,
                    relativePath: relativePath,
                    driveUUID: driveUUID,
                    driveName: driveName,
                    isConnected: isConnected
                ))
            }

            return results
        }
    }

    /// Checks if a drive is currently mounted by checking /Volumes
    private func isDriveMounted(_ driveName: String) -> Bool {
        let volumePath = "/Volumes/\(driveName)"
        return FileManager.default.fileExists(atPath: volumePath)
    }
}
