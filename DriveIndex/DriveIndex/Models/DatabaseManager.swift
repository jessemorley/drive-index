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
    let isExcluded: Bool
}

struct DuplicateGroup: Identifiable {
    let name: String
    let size: Int64
    let count: Int
    let files: [DuplicateFile]

    var id: String {
        "\(name)-\(size)"
    }
}

struct DuplicateFile {
    let id: Int64
    let driveUUID: String
    let driveName: String
    let relativePath: String
    let modifiedAt: Date?
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
            sqlite3_close_v2(db)
        }
    }

    // MARK: - Database Recovery

    /// Recover from database corruption or I/O errors
    func recoverDatabase() async throws {
        print("🔄 Attempting database recovery...")

        // Close existing connection if any
        if db != nil {
            sqlite3_close_v2(db)
            db = nil
        }

        // Check if database file exists
        if !FileManager.default.fileExists(atPath: dbPath) {
            print("📁 Database file missing, will recreate on next open")
        }

        // Reopen and recreate schema
        try openDatabase()
        try createSchema()

        print("✅ Database recovered successfully")
    }

    /// Check if database is healthy
    private func ensureDatabaseHealth() throws -> Bool {
        guard db != nil else { return false }

        // Simple health check query
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let healthCheck = "SELECT 1"
        let result = sqlite3_prepare_v2(db, healthCheck, -1, &stmt, nil)

        // Check for I/O or corruption errors
        if result == SQLITE_IOERR || result == SQLITE_CORRUPT || result == SQLITE_NOTADB {
            return false
        }

        return result == SQLITE_OK
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

    /// Migrate existing drives table to add is_excluded column
    private func migrateAddIsExcludedColumn() throws {
        // Check if column already exists
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let pragmaSQL = "PRAGMA table_info(drives)"
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        var hasIsExcluded = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            let columnName = String(cString: sqlite3_column_text(stmt, 1))
            if columnName == "is_excluded" {
                hasIsExcluded = true
                break
            }
        }

        // Add column if it doesn't exist
        if !hasIsExcluded {
            print("📊 Migrating drives table to add is_excluded column")
            try execute("ALTER TABLE drives ADD COLUMN is_excluded BOOLEAN DEFAULT 0")
            print("✅ Migration complete")
        }
    }

    /// Migrate existing files table to add hash columns
    private func migrateAddHashColumns() throws {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let pragmaSQL = "PRAGMA table_info(files)"
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        var hasHash = false
        var hasHashComputedAt = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            let columnName = String(cString: sqlite3_column_text(stmt, 1))
            if columnName == "hash" {
                hasHash = true
            } else if columnName == "hash_computed_at" {
                hasHashComputedAt = true
            }
        }

        // Add columns if they don't exist
        if !hasHash {
            print("📊 Migrating files table to add hash column")
            try execute("ALTER TABLE files ADD COLUMN hash TEXT")
            print("✅ Hash column added")
        }

        if !hasHashComputedAt {
            print("📊 Migrating files table to add hash_computed_at column")
            try execute("ALTER TABLE files ADD COLUMN hash_computed_at INTEGER")
            print("✅ Hash computed_at column added")
        }

        // Add indexes if columns were just added or don't exist
        if !hasHash {
            print("📊 Creating hash indexes")
            try execute("CREATE INDEX IF NOT EXISTS idx_files_hash ON files(hash) WHERE hash IS NOT NULL")
            try execute("CREATE INDEX IF NOT EXISTS idx_files_unhashed ON files(size, is_directory) WHERE hash IS NULL AND is_directory = 0")
            print("✅ Hash indexes created")
        }
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
                file_count INTEGER,
                is_excluded BOOLEAN DEFAULT 0
            )
        """)

        // Migrate existing drives table to add is_excluded column if it doesn't exist
        try migrateAddIsExcludedColumn()

        // Migrate files table to add hash columns if they don't exist
        try migrateAddHashColumns()

        // Thumbnails table for media file previews
        try execute("""
            CREATE TABLE IF NOT EXISTS thumbnails (
                file_id INTEGER PRIMARY KEY,
                thumbnail_path TEXT NOT NULL,
                generated_at INTEGER NOT NULL,
                file_size INTEGER,
                FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
            )
        """)

        // Index for tracking cache size
        try execute("CREATE INDEX IF NOT EXISTS idx_thumbnails_size ON thumbnails(file_size)")
        try execute("CREATE INDEX IF NOT EXISTS idx_thumbnails_generated ON thumbnails(generated_at)")

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
        // Optimized bulk deletion: disable triggers and manually clean FTS5
        // This is much faster than letting triggers fire for each row

        print("🗑️ Clearing drive files (optimized bulk delete)...")

        // Begin transaction
        try execute("BEGIN IMMEDIATE")

        do {
            // Step 1: Delete from FTS5 index first (bulk operation)
            var stmt1: OpaquePointer?
            defer {
                if stmt1 != nil {
                    sqlite3_finalize(stmt1)
                }
            }

            let deleteFTSSQL = """
                DELETE FROM files_fts WHERE rowid IN (
                    SELECT id FROM files WHERE drive_uuid = ?
                )
            """

            guard sqlite3_prepare_v2(db, deleteFTSSQL, -1, &stmt1, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            sqlite3_bind_text(stmt1, 1, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(stmt1) == SQLITE_DONE else {
                throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
            }

            print("✅ FTS5 entries deleted")

            // Step 2: Disable the delete trigger temporarily
            try execute("DROP TRIGGER IF EXISTS files_ad")

            // Step 3: Delete from files table (no trigger overhead)
            var stmt2: OpaquePointer?
            defer {
                if stmt2 != nil {
                    sqlite3_finalize(stmt2)
                }
            }

            let deleteFilesSQL = "DELETE FROM files WHERE drive_uuid = ?"

            guard sqlite3_prepare_v2(db, deleteFilesSQL, -1, &stmt2, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            sqlite3_bind_text(stmt2, 1, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(stmt2) == SQLITE_DONE else {
                throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
            }

            print("✅ File records deleted")

            // Step 4: Recreate the delete trigger
            try execute("""
                CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
                    INSERT INTO files_fts(files_fts, rowid, name, relative_path)
                    VALUES('delete', old.id, old.name, old.relative_path);
                END
            """)

            // Commit transaction
            try execute("COMMIT")

            print("✅ Bulk delete completed successfully")

        } catch {
            // Rollback on error
            try? execute("ROLLBACK")

            // Recreate trigger even on error to ensure consistency
            try? execute("""
                CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
                    INSERT INTO files_fts(files_fts, rowid, name, relative_path)
                    VALUES('delete', old.id, old.name, old.relative_path);
                END
            """)

            throw error
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

    /// Get existing files for a drive to support delta indexing
    /// Returns a dictionary mapping relative_path to (id, modified_at)
    func getExistingFiles(driveUUID: String) throws -> [String: (id: Int64, modifiedAt: Date?)] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = "SELECT id, relative_path, modified_at FROM files WHERE drive_uuid = ?"

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)

        var results: [String: (id: Int64, modifiedAt: Date?)] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let relativePath = String(cString: sqlite3_column_text(stmt, 1))

            var modifiedAt: Date?
            if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2)))
            }

            results[relativePath] = (id: id, modifiedAt: modifiedAt)
        }

        return results
    }

    /// Get existing directories for a drive to support directory caching optimization
    /// Returns a dictionary mapping relative_path to modified_at timestamp
    func getExistingDirectories(driveUUID: String) throws -> [String: Date?] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT relative_path, modified_at
            FROM files
            WHERE drive_uuid = ? AND is_directory = 1
        """

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)

        var results: [String: Date?] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let relativePath = String(cString: sqlite3_column_text(stmt, 0))

            var modifiedAt: Date?
            if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1)))
            }

            results[relativePath] = modifiedAt
        }

        return results
    }

    /// Update a batch of files (for delta indexing when files have changed)
    func updateFilesBatch(_ entries: [FileEntry]) throws {
        guard !entries.isEmpty else { return }

        try execute("BEGIN TRANSACTION")

        do {
            let updateSQL = """
                UPDATE files
                SET name = ?, size = ?, created_at = ?, modified_at = ?, is_directory = ?
                WHERE id = ?
            """

            var stmt: OpaquePointer?
            defer {
                if stmt != nil {
                    sqlite3_finalize(stmt)
                }
            }

            guard sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK else {
                try? execute("ROLLBACK")
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            for entry in entries {
                guard let id = entry.id else {
                    print("⚠️ Warning: Skipping update for entry without ID: \(entry.relativePath)")
                    continue
                }

                sqlite3_bind_text(stmt, 1, (entry.name as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, entry.size)

                if let createdAt = entry.createdAt {
                    sqlite3_bind_int64(stmt, 3, Int64(createdAt.timeIntervalSince1970))
                } else {
                    sqlite3_bind_null(stmt, 3)
                }

                if let modifiedAt = entry.modifiedAt {
                    sqlite3_bind_int64(stmt, 4, Int64(modifiedAt.timeIntervalSince1970))
                } else {
                    sqlite3_bind_null(stmt, 4)
                }

                sqlite3_bind_int(stmt, 5, entry.isDirectory ? 1 : 0)
                sqlite3_bind_int64(stmt, 6, id)

                let result = sqlite3_step(stmt)
                guard result == SQLITE_DONE else {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    print("❌ SQLite error during update: \(errorMsg)")
                    try? execute("ROLLBACK")
                    throw DatabaseError.executeFailed(errorMsg)
                }

                sqlite3_reset(stmt)
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Delete files by relative paths (for delta indexing when files are removed)
    func deleteFiles(driveUUID: String, relativePaths: [String]) throws {
        guard !relativePaths.isEmpty else { return }

        try execute("BEGIN TRANSACTION")

        do {
            let deleteSQL = "DELETE FROM files WHERE drive_uuid = ? AND relative_path = ?"

            var stmt: OpaquePointer?
            defer {
                if stmt != nil {
                    sqlite3_finalize(stmt)
                }
            }

            guard sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK else {
                try? execute("ROLLBACK")
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            for relativePath in relativePaths {
                sqlite3_bind_text(stmt, 1, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, (relativePath as NSString).utf8String, -1, SQLITE_TRANSIENT)

                let result = sqlite3_step(stmt)
                guard result == SQLITE_DONE else {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    print("❌ SQLite error during delete: \(errorMsg)")
                    try? execute("ROLLBACK")
                    throw DatabaseError.executeFailed(errorMsg)
                }

                sqlite3_reset(stmt)
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Get recently added files across all drives
    /// Returns files ordered by ID (most recent first) up to specified limit
    func getRecentFiles(limit: Int = 1000, offset: Int = 0) throws -> [FileEntry] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT id, drive_uuid, name, relative_path, size, created_at, modified_at, is_directory
            FROM files
            WHERE is_directory = 0
            ORDER BY id DESC
            LIMIT ? OFFSET ?
        """

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))

        var results: [FileEntry] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let driveUUID = String(cString: sqlite3_column_text(stmt, 1))
            let name = String(cString: sqlite3_column_text(stmt, 2))
            let relativePath = String(cString: sqlite3_column_text(stmt, 3))
            let size = sqlite3_column_int64(stmt, 4)

            var createdAt: Date?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 5)))
            }

            var modifiedAt: Date?
            if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 6)))
            }

            let isDirectory = sqlite3_column_int(stmt, 7) != 0

            results.append(FileEntry(
                id: id,
                driveUUID: driveUUID,
                name: name,
                relativePath: relativePath,
                size: size,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                isDirectory: isDirectory
            ))
        }

        return results
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
            (uuid, name, last_seen, total_capacity, used_capacity, last_scan_date, file_count, is_excluded)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
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
        sqlite3_bind_int(stmt, 8, metadata.isExcluded ? 1 : 0)

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
            SELECT uuid, name, last_seen, total_capacity, used_capacity, last_scan_date, file_count, is_excluded
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
        let isExcluded = sqlite3_column_int(stmt, 7) != 0

        return DriveMetadata(
            uuid: uuidStr,
            name: name,
            lastSeen: lastSeen,
            totalCapacity: totalCapacity,
            usedCapacity: usedCapacity,
            lastScanDate: lastScanDate,
            fileCount: fileCount,
            isExcluded: isExcluded
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
            SELECT uuid, name, last_seen, total_capacity, used_capacity, last_scan_date, file_count, is_excluded
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
            let isExcluded = sqlite3_column_int(stmt, 7) != 0

            results.append(DriveMetadata(
                uuid: uuid,
                name: name,
                lastSeen: lastSeen,
                totalCapacity: totalCapacity,
                usedCapacity: usedCapacity,
                lastScanDate: lastScanDate,
                fileCount: fileCount,
                isExcluded: isExcluded
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

    func deleteDrive(_ driveUUID: String) throws {
        print("🗑️ deleteDrive called for UUID: \(driveUUID)")

        // Delete all files for this drive first (FTS5 triggers will auto-clean the search index)
        try clearDrive(driveUUID)

        // Delete the drive metadata
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let deleteSQL = "DELETE FROM drives WHERE uuid = ?"

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            print("❌ prepare failed: \(error)")
            throw DatabaseError.prepareFailed(error)
        }

        sqlite3_bind_text(stmt, 1, (driveUUID as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let error = String(cString: sqlite3_errmsg(db))
            print("❌ execute failed: \(error)")
            throw DatabaseError.executeFailed(error)
        }

        print("✅ Drive deleted successfully")
    }

    // MARK: - Drive Exclusion Operations

    /// Set whether a drive is excluded from automatic indexing
    func setDriveExcluded(uuid: String, excluded: Bool) throws {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let updateSQL = "UPDATE drives SET is_excluded = ? WHERE uuid = ?"

        guard sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, excluded ? 1 : 0)
        sqlite3_bind_text(stmt, 2, (uuid as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }

        print("✅ Drive exclusion updated: \(uuid) -> \(excluded)")
    }

    /// Check if a drive is excluded
    func isDriveExcluded(uuid: String) throws -> Bool {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = "SELECT is_excluded FROM drives WHERE uuid = ?"

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (uuid as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            // Drive not found - default to not excluded
            return false
        }

        return sqlite3_column_int(stmt, 0) != 0
    }

    /// Get all excluded drives
    func getExcludedDrives() throws -> [DriveMetadata] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT uuid, name, last_seen, total_capacity, used_capacity, last_scan_date, file_count, is_excluded
            FROM drives
            WHERE is_excluded = 1
            ORDER BY name ASC
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
            let isExcluded = sqlite3_column_int(stmt, 7) != 0

            results.append(DriveMetadata(
                uuid: uuid,
                name: name,
                lastSeen: lastSeen,
                totalCapacity: totalCapacity,
                usedCapacity: usedCapacity,
                lastScanDate: lastScanDate,
                fileCount: fileCount,
                isExcluded: isExcluded
            ))
        }

        return results
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

        let result = sqlite3_exec(db, sql, nil, nil, &error)

        // Check for I/O errors specifically
        if result == SQLITE_IOERR {
            let extendedCode = sqlite3_extended_errcode(db)
            let message = error != nil ? String(cString: error!) : "Disk I/O error"
            throw DatabaseError.ioError(extendedCode, message)
        }

        // Check for corruption
        if result == SQLITE_CORRUPT || result == SQLITE_NOTADB {
            let message = error != nil ? String(cString: error!) : "Database is corrupt or not a database"
            throw DatabaseError.corruptDatabase(message)
        }

        guard result == SQLITE_OK else {
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

    // MARK: - Duplicate Detection

    /// Get unhashed files for background processing
    func getUnhashedFiles(minSize: Int64, limit: Int) throws -> [(id: Int64, driveUUID: String, relativePath: String, size: Int64)] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT id, drive_uuid, relative_path, size
            FROM files
            WHERE hash IS NULL AND is_directory = 0 AND size >= ?
            ORDER BY size DESC
            LIMIT ?
        """

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, minSize)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [(Int64, String, String, Int64)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let driveUUID = String(cString: sqlite3_column_text(stmt, 1))
            let relativePath = String(cString: sqlite3_column_text(stmt, 2))
            let size = sqlite3_column_int64(stmt, 3)
            results.append((id, driveUUID, relativePath, size))
        }

        return results
    }

    /// Get count of unhashed files
    func getUnhashedCount(minSize: Int64) throws -> Int {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let countSQL = """
            SELECT COUNT(*)
            FROM files
            WHERE hash IS NULL AND is_directory = 0 AND size >= ?
        """

        guard sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, minSize)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Batch update file hashes
    func updateHashesBatch(_ updates: [(fileID: Int64, hash: String)]) throws {
        guard !updates.isEmpty else { return }

        try execute("BEGIN TRANSACTION")

        do {
            let updateSQL = "UPDATE files SET hash = ?, hash_computed_at = ? WHERE id = ?"

            var stmt: OpaquePointer?
            defer {
                if stmt != nil {
                    sqlite3_finalize(stmt)
                }
            }

            guard sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK else {
                try? execute("ROLLBACK")
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            let timestamp = Int64(Date().timeIntervalSince1970)

            for update in updates {
                sqlite3_bind_text(stmt, 1, (update.hash as NSString).utf8String, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, timestamp)
                sqlite3_bind_int64(stmt, 3, update.fileID)

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    let errorMsg = String(cString: sqlite3_errmsg(db))
                    try? execute("ROLLBACK")
                    throw DatabaseError.executeFailed(errorMsg)
                }

                sqlite3_reset(stmt)
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Get the count of duplicates for a specific file (by name and size)
    func getDuplicateCount(name: String, size: Int64) throws -> Int {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let countSQL = """
            SELECT COUNT(*) FROM files
            WHERE name = ? AND size = ? AND is_directory = 0
        """

        guard sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, size)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Get all duplicate file groups (files with same hash appearing multiple times)
    func getDuplicateGroups() throws -> [DuplicateGroup] {
        // Get minimum file size from settings (default 5MB)
        let minSizeStr = try getSetting("min_duplicate_file_size") ?? "5242880"
        let minSize = Int64(minSizeStr) ?? 5_242_880  // 5MB default

        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        // Get all duplicate groups (hash values that appear more than once)
        // Only include files with computed hashes
        let groupSQL = """
            SELECT hash, name, size, COUNT(*) as count
            FROM files
            WHERE is_directory = 0 AND size >= ? AND hash IS NOT NULL
            GROUP BY hash
            HAVING COUNT(*) > 1
            ORDER BY count DESC, size DESC
        """

        guard sqlite3_prepare_v2(db, groupSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, minSize)

        var groups: [DuplicateGroup] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let hash = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let size = sqlite3_column_int64(stmt, 2)
            let count = Int(sqlite3_column_int(stmt, 3))

            // Get all files for this duplicate group
            let files = try getDuplicateFilesByHash(hash: hash)

            groups.append(DuplicateGroup(
                name: name,
                size: size,
                count: count,
                files: files
            ))
        }

        return groups
    }

    /// Get all files matching a specific hash
    private func getDuplicateFilesByHash(hash: String) throws -> [DuplicateFile] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let filesSQL = """
            SELECT f.id, f.drive_uuid, d.name as drive_name, f.relative_path, f.modified_at
            FROM files f
            JOIN drives d ON d.uuid = f.drive_uuid
            WHERE f.hash = ? AND f.is_directory = 0
            ORDER BY d.name, f.relative_path
        """

        guard sqlite3_prepare_v2(db, filesSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_text(stmt, 1, (hash as NSString).utf8String, -1, SQLITE_TRANSIENT)

        var files: [DuplicateFile] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let driveUUID = String(cString: sqlite3_column_text(stmt, 1))
            let driveName = String(cString: sqlite3_column_text(stmt, 2))
            let relativePath = String(cString: sqlite3_column_text(stmt, 3))

            var modifiedAt: Date?
            if sqlite3_column_type(stmt, 4) != SQLITE_NULL {
                modifiedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4)))
            }

            files.append(DuplicateFile(
                id: id,
                driveUUID: driveUUID,
                driveName: driveName,
                relativePath: relativePath,
                modifiedAt: modifiedAt
            ))
        }

        return files
    }

    // MARK: - Thumbnail Operations

    /// Save thumbnail metadata to database
    func saveThumbnail(fileID: Int64, thumbnailPath: String, fileSize: Int64) throws {
        let insertSQL = """
            INSERT OR REPLACE INTO thumbnails (file_id, thumbnail_path, generated_at, file_size)
            VALUES (?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, fileID)
        sqlite3_bind_text(stmt, 2, (thumbnailPath as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 4, fileSize)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Get thumbnail path for a file
    func getThumbnailPath(for fileID: Int64) throws -> String? {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = "SELECT thumbnail_path FROM thumbnails WHERE file_id = ?"

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, fileID)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }

        return nil
    }

    /// Get total cache size
    func getThumbnailCacheSize() throws -> Int64 {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = "SELECT COALESCE(SUM(file_size), 0) FROM thumbnails"

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return sqlite3_column_int64(stmt, 0)
    }

    /// Get oldest thumbnails for LRU eviction
    func getOldestThumbnails(limit: Int) throws -> [(fileID: Int64, path: String, size: Int64)] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT file_id, thumbnail_path, file_size
            FROM thumbnails
            ORDER BY generated_at ASC
            LIMIT ?
        """

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var thumbnails: [(Int64, String, Int64)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let fileID = sqlite3_column_int64(stmt, 0)
            let path = String(cString: sqlite3_column_text(stmt, 1))
            let size = sqlite3_column_int64(stmt, 2)
            thumbnails.append((fileID, path, size))
        }

        return thumbnails
    }

    /// Delete thumbnail record from database
    func deleteThumbnail(fileID: Int64) throws {
        let deleteSQL = "DELETE FROM thumbnails WHERE file_id = ?"

        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        guard sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int64(stmt, 1, fileID)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Get media files without thumbnails
    func getMediaFilesWithoutThumbnails(limit: Int) throws -> [(id: Int64, driveUUID: String, relativePath: String, name: String)] {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT f.id, f.drive_uuid, f.relative_path, f.name
            FROM files f
            LEFT JOIN thumbnails t ON f.id = t.file_id
            WHERE t.file_id IS NULL
            AND f.is_directory = 0
            AND (
                LOWER(f.name) LIKE '%.jpg' OR LOWER(f.name) LIKE '%.jpeg' OR LOWER(f.name) LIKE '%.png' OR
                LOWER(f.name) LIKE '%.gif' OR LOWER(f.name) LIKE '%.heic' OR LOWER(f.name) LIKE '%.heif' OR
                LOWER(f.name) LIKE '%.tiff' OR LOWER(f.name) LIKE '%.tif' OR LOWER(f.name) LIKE '%.bmp' OR
                LOWER(f.name) LIKE '%.webp' OR LOWER(f.name) LIKE '%.nef' OR LOWER(f.name) LIKE '%.cr2' OR
                LOWER(f.name) LIKE '%.cr3' OR LOWER(f.name) LIKE '%.arw' OR LOWER(f.name) LIKE '%.dng' OR
                LOWER(f.name) LIKE '%.raf' OR LOWER(f.name) LIKE '%.orf' OR LOWER(f.name) LIKE '%.rw2' OR
                LOWER(f.name) LIKE '%.pef' OR LOWER(f.name) LIKE '%.srw' OR LOWER(f.name) LIKE '%.raw' OR
                LOWER(f.name) LIKE '%.mp4' OR LOWER(f.name) LIKE '%.mov' OR LOWER(f.name) LIKE '%.m4v' OR
                LOWER(f.name) LIKE '%.avi' OR LOWER(f.name) LIKE '%.pdf'
            )
            LIMIT ?
        """

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var files: [(Int64, String, String, String)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let driveUUID = String(cString: sqlite3_column_text(stmt, 1))
            let relativePath = String(cString: sqlite3_column_text(stmt, 2))
            let name = String(cString: sqlite3_column_text(stmt, 3))
            files.append((id, driveUUID, relativePath, name))
        }

        return files
    }

    /// Get count of media files without thumbnails
    func getMediaFilesWithoutThumbnailsCount() throws -> Int {
        var stmt: OpaquePointer?
        defer {
            if stmt != nil {
                sqlite3_finalize(stmt)
            }
        }

        let selectSQL = """
            SELECT COUNT(*)
            FROM files f
            LEFT JOIN thumbnails t ON f.id = t.file_id
            WHERE t.file_id IS NULL
            AND f.is_directory = 0
            AND (
                LOWER(f.name) LIKE '%.jpg' OR LOWER(f.name) LIKE '%.jpeg' OR LOWER(f.name) LIKE '%.png' OR
                LOWER(f.name) LIKE '%.gif' OR LOWER(f.name) LIKE '%.heic' OR LOWER(f.name) LIKE '%.heif' OR
                LOWER(f.name) LIKE '%.tiff' OR LOWER(f.name) LIKE '%.tif' OR LOWER(f.name) LIKE '%.bmp' OR
                LOWER(f.name) LIKE '%.webp' OR LOWER(f.name) LIKE '%.nef' OR LOWER(f.name) LIKE '%.cr2' OR
                LOWER(f.name) LIKE '%.cr3' OR LOWER(f.name) LIKE '%.arw' OR LOWER(f.name) LIKE '%.dng' OR
                LOWER(f.name) LIKE '%.raf' OR LOWER(f.name) LIKE '%.orf' OR LOWER(f.name) LIKE '%.rw2' OR
                LOWER(f.name) LIKE '%.pef' OR LOWER(f.name) LIKE '%.srw' OR LOWER(f.name) LIKE '%.raw' OR
                LOWER(f.name) LIKE '%.mp4' OR LOWER(f.name) LIKE '%.mov' OR LOWER(f.name) LIKE '%.m4v' OR
                LOWER(f.name) LIKE '%.avi' OR LOWER(f.name) LIKE '%.pdf'
            )
        """

        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(stmt, 0))
    }

    // MARK: - Database Optimization

    /// Run PRAGMA optimize to update query statistics and merge FTS5 segments
    func optimize() async throws {
        print("🔧 Running PRAGMA optimize...")
        let startTime = Date()

        try execute("PRAGMA optimize")

        let duration = Date().timeIntervalSince(startTime)
        print("✅ PRAGMA optimize completed in \(String(format: "%.2f", duration * 1000))ms")
    }
}

// MARK: - Error Types

enum DatabaseError: Error, LocalizedError {
    case cannotOpen(String)
    case prepareFailed(String)
    case executeFailed(String)
    case ioError(Int32, String)
    case corruptDatabase(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let message):
            return "Cannot open database: \(message)"
        case .prepareFailed(let message):
            return "Failed to prepare statement: \(message)"
        case .executeFailed(let message):
            return "Failed to execute statement: \(message)"
        case .ioError(let code, let message):
            return "Database I/O error (code \(code)): \(message)"
        case .corruptDatabase(let message):
            return "Database is corrupt: \(message)"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .ioError, .corruptDatabase:
            return true
        default:
            return false
        }
    }
}
