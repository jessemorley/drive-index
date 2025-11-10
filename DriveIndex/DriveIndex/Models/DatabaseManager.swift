//
//  DatabaseManager.swift
//  DriveIndex
//
//  Handles all SQLite database operations including FTS5 search
//

import Foundation
import SQLite3

struct FileEntry {
    let id: Int64?
    let driveUUID: String
    let name: String
    let relativePath: String
    let size: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let isDirectory: Bool
}

struct DriveMetadata {
    let uuid: String
    let name: String
    let lastSeen: Date
    let totalCapacity: Int64
    let usedCapacity: Int64
    let lastScanDate: Date?
    let fileCount: Int
}

actor DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let dbPath: String
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        // Store database in Application Support directory
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let driveIndexDir = appSupport.appendingPathComponent("DriveIndex")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(
            at: driveIndexDir,
            withIntermediateDirectories: true
        )

        dbPath = driveIndexDir.appendingPathComponent("index.db").path

        Task {
            try await openDatabase()
            try await createSchema()
        }
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() throws {
        let result = sqlite3_open(dbPath, &db)
        guard result == SQLITE_OK else {
            throw DatabaseError.cannotOpen(String(cString: sqlite3_errmsg(db)))
        }

        // Enable foreign keys
        try execute("PRAGMA foreign_keys = ON")

        // Performance optimizations
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA cache_size = 10000")
        try execute("PRAGMA temp_store = MEMORY")
    }

    private func createSchema() throws {
        // Main files table
        try execute("""
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                drive_uuid TEXT NOT NULL,
                name TEXT NOT NULL,
                relative_path TEXT NOT NULL,
                size INTEGER,
                created_at INTEGER,
                modified_at INTEGER,
                is_directory BOOLEAN,
                UNIQUE(drive_uuid, relative_path)
            )
        """)

        // FTS5 virtual table for fast search
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
                name,
                relative_path,
                content='files',
                content_rowid='id',
                tokenize='porter unicode61'
            )
        """)

        // Triggers to keep FTS index in sync
        try execute("""
            CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
                INSERT INTO files_fts(rowid, name, relative_path)
                VALUES (new.id, new.name, new.relative_path);
            END
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
                INSERT INTO files_fts(files_fts, rowid, name, relative_path)
                VALUES('delete', old.id, old.name, old.relative_path);
            END
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
                INSERT INTO files_fts(files_fts, rowid, name, relative_path)
                VALUES('delete', old.id, old.name, old.relative_path);
                INSERT INTO files_fts(rowid, name, relative_path)
                VALUES(new.id, new.name, new.relative_path);
            END
        """)

        // Indexes for performance
        try execute("CREATE INDEX IF NOT EXISTS idx_files_drive ON files(drive_uuid)")
        try execute("CREATE INDEX IF NOT EXISTS idx_files_modified ON files(modified_at)")
        try execute("CREATE INDEX IF NOT EXISTS idx_files_name ON files(name)")

        // Drive metadata table
        try execute("""
            CREATE TABLE IF NOT EXISTS drives (
                uuid TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                last_seen INTEGER,
                total_capacity INTEGER,
                used_capacity INTEGER,
                last_scan_date INTEGER,
                file_count INTEGER
            )
        """)

        // Migration: Add used_capacity column if it doesn't exist
        // Check if column exists by trying to add it (will fail silently if exists)
        try? execute("ALTER TABLE drives ADD COLUMN used_capacity INTEGER DEFAULT 0")

        // Settings table
        try execute("""
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        """)
    }

    // MARK: - File Operations

    func insertBatch(_ entries: [FileEntry]) throws {
        guard !entries.isEmpty else { return }

        try execute("BEGIN TRANSACTION")

        do {
            let insertSQL = """
                INSERT OR REPLACE INTO files
                (drive_uuid, name, relative_path, size, created_at, modified_at, is_directory)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """

            var stmt: OpaquePointer?
            defer {
                if stmt != nil {
                    sqlite3_finalize(stmt)
                }
            }

            guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
                try? execute("ROLLBACK")
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            for entry in entries {
                sqlite3_bind_text(stmt, 1, (entry.driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, (entry.name as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, (entry.relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 4, entry.size)

                if let createdAt = entry.createdAt {
                    sqlite3_bind_int64(stmt, 5, Int64(createdAt.timeIntervalSince1970))
                } else {
                    sqlite3_bind_null(stmt, 5)
                }

                if let modifiedAt = entry.modifiedAt {
                    sqlite3_bind_int64(stmt, 6, Int64(modifiedAt.timeIntervalSince1970))
                } else {
                    sqlite3_bind_null(stmt, 6)
                }

                sqlite3_bind_int(stmt, 7, entry.isDirectory ? 1 : 0)

                let result = sqlite3_step(stmt)
                guard result == SQLITE_DONE else {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    let errorCode = sqlite3_errcode(db)
                    let extendedErrorCode = sqlite3_extended_errcode(db)
                    print("❌ SQLite error during insert:")
                    print("   Error code: \(errorCode), Extended: \(extendedErrorCode)")
                    print("   Message: \(errorMsg)")
                    print("   Entry: \(entry.name) in \(entry.relativePath)")
                    try? execute("ROLLBACK")
                    throw DatabaseError.executeFailed("\(errorMsg) (code: \(errorCode)/\(extendedErrorCode))")
                }

                sqlite3_reset(stmt)
            }

            // Only commit if all inserts succeeded
            try execute("COMMIT")
        } catch {
            // Ensure rollback on any error
            try? execute("ROLLBACK")
            throw error
        }
    }

    func clearDrive(_ driveUUID: String) throws {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let deleteSQL = "DELETE FROM files WHERE drive_uuid = ?"

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func getFileCount(for driveUUID: String) throws -> Int {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let countSQL = "SELECT COUNT(*) FROM files WHERE drive_uuid = ?"

        guard sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - Drive Metadata Operations

    func upsertDriveMetadata(_ metadata: DriveMetadata) throws {
        print("📝 upsertDriveMetadata called for: \(metadata.name) (UUID: \(metadata.uuid))")

        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let upsertSQL = """
            INSERT OR REPLACE INTO drives
            (uuid, name, last_seen, total_capacity, used_capacity, last_scan_date, file_count)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """

        guard sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            print("❌ prepare failed: \(error)")
            throw DatabaseError.prepareFailed(error)
        }

        sqlite3_bind_text(stmt, 1, (metadata.uuid as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, (metadata.name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, Int64(metadata.lastSeen.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 4, metadata.totalCapacity)
        sqlite3_bind_int64(stmt, 5, metadata.usedCapacity)

        if let lastScanDate = metadata.lastScanDate {
            sqlite3_bind_int64(stmt, 6, Int64(lastScanDate.timeIntervalSince1970))
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        sqlite3_bind_int(stmt, 7, Int32(metadata.fileCount))

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE else {
            let error = String(cString: sqlite3_errmsg(db))
            print("❌ execute failed: \(error) (code: \(result))")
            throw DatabaseError.executeFailed(error)
        }

        print("✅ Drive metadata upserted successfully")
    }

    func getDriveMetadata(_ uuid: String) throws -> DriveMetadata? {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT uuid, name, last_seen, total_capacity, used_capacity, last_scan_date, file_count
            FROM drives WHERE uuid = ?
        """

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (uuid as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        let uuidStr = String(cString: sqlite3_column_text(stmt, 0))
        let name = String(cString: sqlite3_column_text(stmt, 1))
        let lastSeen = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))
        let totalCapacity = sqlite3_column_int64(stmt, 3)
        let usedCapacity = sqlite3_column_int64(stmt, 4)

        var lastScanDate: Date?
        if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
            lastScanDate = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5)))
        }

        let fileCount = Int(sqlite3_column_int(stmt, 6))

        return DriveMetadata(
            uuid: uuidStr,
            name: name,
            lastSeen: lastSeen,
            totalCapacity: totalCapacity,
            usedCapacity: usedCapacity,
            lastScanDate: lastScanDate,
            fileCount: fileCount
        )
    }

    func getAllDriveMetadata() throws -> [DriveMetadata] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT uuid, name, last_seen, total_capacity, used_capacity, last_scan_date, file_count
            FROM drives
            ORDER BY last_seen DESC
        """

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        var results: [DriveMetadata] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let uuid = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let lastSeen = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))
            let totalCapacity = sqlite3_column_int64(stmt, 3)
            let usedCapacity = sqlite3_column_int64(stmt, 4)

            var lastScanDate: Date?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                lastScanDate = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5)))
            }

            let fileCount = Int(sqlite3_column_int(stmt, 6))

            results.append(DriveMetadata(
                uuid: uuid,
                name: name,
                lastSeen: lastSeen,
                totalCapacity: totalCapacity,
                usedCapacity: usedCapacity,
                lastScanDate: lastScanDate,
                fileCount: fileCount
            ))
        }

        return results
    }

    func updateLastScanDate(for driveUUID: String, date: Date) throws {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let updateSQL = "UPDATE drives SET last_scan_date = ? WHERE uuid = ?"

        guard sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, Int64(date.timeIntervalSince1970))
        sqlite3_bind_text(stmt, 2, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Settings Operations

    func getSetting(_ key: String) throws -> String? {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = "SELECT value FROM settings WHERE key = ?"

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return String(cString: sqlite3_column_text(stmt, 0))
    }

    func setSetting(_ key: String, value: String) throws {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let upsertSQL = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)"

        guard sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Helper Methods

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        defer {
            if error != nil {
                sqlite3_free(error)
            }
        }

        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error != nil ? String(cString: error!) : "Unknown error"
            throw DatabaseError.executeFailed(message)
        }
    }

    /// Execute a query and process results with a closure
    func executeQuery<T>(_ sql: String, process: (OpaquePointer) throws -> T) throws -> T {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        guard let statement = stmt else {
            throw DatabaseError.prepareFailed("Statement is nil")
        }

        return try process(statement)
    }
}

// MARK: - Error Types

enum DatabaseError: Error, LocalizedError {
    case cannotOpen(String)
    case prepareFailed(String)
    case executeFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let message):
            return "Cannot open database: \(message)"
        case .prepareFailed(let message):
            return "Failed to prepare statement: \(message)"
        case .executeFailed(let message):
            return "Failed to execute statement: \(message)"
        }
    }
}
