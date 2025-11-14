//
//  FileIndexer.swift
//  DriveIndex
//
//  Async file system indexer with exclusion support
//

import Foundation

struct IndexProgress {
    let filesProcessed: Int
    let currentFile: String
    let isComplete: Bool
}

actor FileIndexer {
    private let database = DatabaseManager.shared
    private var excludedDirectories: Set<String> = []
    private var excludedExtensions: Set<String> = []

    init() {
        Task {
            // Wait a moment for database to initialize
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await loadExclusionSettings()
        }
    }

    private func loadExclusionSettings() async {
        do {
            // Load excluded directories
            if let dirSettings = try await database.getSetting("excluded_directories") {
                excludedDirectories = Set(dirSettings.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            } else {
                // Default exclusions
                excludedDirectories = [
                    ".git",
                    "node_modules",
                    ".Spotlight-V100",
                    ".Trashes",
                    ".fseventsd",
                    ".TemporaryItems",
                    "Library",
                    "$RECYCLE.BIN",
                    "System Volume Information"
                ]
                try await database.setSetting("excluded_directories", value: excludedDirectories.joined(separator: ","))
            }

            // Load excluded extensions
            if let extSettings = try await database.getSetting("excluded_extensions") {
                excludedExtensions = Set(extSettings.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            } else {
                // Default exclusions
                excludedExtensions = [
                    ".tmp",
                    ".cache",
                    ".DS_Store",
                    ".localized"
                ]
                try await database.setSetting("excluded_extensions", value: excludedExtensions.joined(separator: ","))
            }

        } catch let error as DatabaseError {
            // Attempt recovery for recoverable database errors
            if error.isRecoverable {
                print("⚠️ Database error detected, attempting recovery...")
                do {
                    try await database.recoverDatabase()
                    // Retry loading settings once after recovery
                    await loadExclusionSettings()
                    return
                } catch {
                    print("❌ Recovery failed: \(error)")
                }
            }

            print("Error loading exclusion settings: \(error)")
            // Use defaults if loading fails
            if excludedDirectories.isEmpty {
                excludedDirectories = [
                    ".git",
                    "node_modules",
                    ".Spotlight-V100",
                    ".Trashes",
                    ".fseventsd",
                    ".TemporaryItems",
                    "Library",
                    "$RECYCLE.BIN",
                    "System Volume Information"
                ]
            }
            if excludedExtensions.isEmpty {
                excludedExtensions = [
                    ".tmp",
                    ".cache",
                    ".DS_Store",
                    ".localized"
                ]
            }
        } catch {
            print("Error loading exclusion settings: \(error)")
            // Use defaults if loading fails
            if excludedDirectories.isEmpty {
                excludedDirectories = [
                    ".git",
                    "node_modules",
                    ".Spotlight-V100",
                    ".Trashes",
                    ".fseventsd",
                    ".TemporaryItems",
                    "Library",
                    "$RECYCLE.BIN",
                    "System Volume Information"
                ]
            }
            if excludedExtensions.isEmpty {
                excludedExtensions = [
                    ".tmp",
                    ".cache",
                    ".DS_Store",
                    ".localized"
                ]
            }
        }
    }

    func updateExcludedDirectories(_ directories: [String]) async throws {
        excludedDirectories = Set(directories)
        try await database.setSetting("excluded_directories", value: directories.joined(separator: ","))
    }

    func updateExcludedExtensions(_ extensions: [String]) async throws {
        excludedExtensions = Set(extensions)
        try await database.setSetting("excluded_extensions", value: extensions.joined(separator: ","))
    }

    func getExcludedDirectories() -> [String] {
        Array(excludedDirectories).sorted()
    }

    func getExcludedExtensions() -> [String] {
        Array(excludedExtensions).sorted()
    }

    // MARK: - Indexing

    /// Main entry point for drive indexing - intelligently chooses delta vs full scan
    func indexDrive(
        driveURL: URL,
        driveUUID: String,
        onProgress: @escaping @Sendable (IndexProgress) -> Void
    ) async throws {
        // Determine scan type based on whether this drive has been indexed before
        let driveMetadata = try await database.getDriveMetadata(driveUUID)
        let shouldUseDelta = driveMetadata?.lastScanDate != nil

        if shouldUseDelta {
            print("Starting delta index of drive: \(driveURL.path)")
            try await indexDriveDelta(driveURL: driveURL, driveUUID: driveUUID, onProgress: onProgress)
        } else {
            print("Starting full index of drive: \(driveURL.path) (first time)")
            try await indexDriveFull(driveURL: driveURL, driveUUID: driveUUID, onProgress: onProgress)
        }
    }

    /// Full reindex - clears all existing data and rebuilds from scratch
    private func indexDriveFull(
        driveURL: URL,
        driveUUID: String,
        onProgress: @escaping @Sendable (IndexProgress) -> Void
    ) async throws {
        // Clear existing entries for this drive
        try await database.clearDrive(driveUUID)

        var filesProcessed = 0
        var batch: [FileEntry] = []
        let batchSize = 1000

        // Get base path for relative paths
        let basePath = driveURL.path

        // Walk directory tree
        let fileStream = walkDirectory(at: driveURL, basePath: basePath, driveUUID: driveUUID)

        for await fileEntry in fileStream {
            batch.append(fileEntry)
            filesProcessed += 1

            // Report progress every 100 files
            if filesProcessed % 100 == 0 {
                onProgress(IndexProgress(
                    filesProcessed: filesProcessed,
                    currentFile: fileEntry.name,
                    isComplete: false
                ))
            }

            // Insert in batches
            if batch.count >= batchSize {
                try await database.insertBatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        // Insert remaining entries
        if !batch.isEmpty {
            try await database.insertBatch(batch)
        }

        // Update drive metadata
        let fileCount = try await database.getFileCount(for: driveUUID)
        try await database.updateLastScanDate(for: driveUUID, date: Date())

        // Update file count in drives table
        if let metadata = try await database.getDriveMetadata(driveUUID) {
            let updatedMetadata = DriveMetadata(
                uuid: metadata.uuid,
                name: metadata.name,
                lastSeen: metadata.lastSeen,
                totalCapacity: metadata.totalCapacity,
                usedCapacity: metadata.usedCapacity,
                lastScanDate: Date(),
                fileCount: fileCount
            )
            try await database.upsertDriveMetadata(updatedMetadata)
        }

        onProgress(IndexProgress(
            filesProcessed: filesProcessed,
            currentFile: "",
            isComplete: true
        ))

        print("Full index complete: \(filesProcessed) files processed")
    }

    /// Delta indexing - only updates changed files, inserts new files, deletes removed files
    private func indexDriveDelta(
        driveURL: URL,
        driveUUID: String,
        onProgress: @escaping @Sendable (IndexProgress) -> Void
    ) async throws {
        // Fetch existing files from database
        let existingFiles = try await database.getExistingFiles(driveUUID: driveUUID)
        print("📊 Delta scan: \(existingFiles.count) existing files in database")

        var filesProcessed = 0
        var insertBatch: [FileEntry] = []
        var updateBatch: [FileEntry] = []
        var visitedPaths = Set<String>()
        let batchSize = 1000

        var newCount = 0
        var modifiedCount = 0
        var unchangedCount = 0

        // Get base path for relative paths
        let basePath = driveURL.path

        // Walk directory tree
        let fileStream = walkDirectory(at: driveURL, basePath: basePath, driveUUID: driveUUID)

        for await fileEntry in fileStream {
            filesProcessed += 1
            visitedPaths.insert(fileEntry.relativePath)

            // Report progress every 100 files
            if filesProcessed % 100 == 0 {
                onProgress(IndexProgress(
                    filesProcessed: filesProcessed,
                    currentFile: fileEntry.name,
                    isComplete: false
                ))
            }

            // Check if file exists in database
            if let existing = existingFiles[fileEntry.relativePath] {
                // File exists - check if modified
                if isFileModified(current: fileEntry.modifiedAt, existing: existing.modifiedAt) {
                    // File has been modified - add to update batch
                    var updatedEntry = fileEntry
                    updatedEntry = FileEntry(
                        id: existing.id,
                        driveUUID: fileEntry.driveUUID,
                        name: fileEntry.name,
                        relativePath: fileEntry.relativePath,
                        size: fileEntry.size,
                        createdAt: fileEntry.createdAt,
                        modifiedAt: fileEntry.modifiedAt,
                        isDirectory: fileEntry.isDirectory
                    )
                    updateBatch.append(updatedEntry)
                    modifiedCount += 1

                    if updateBatch.count >= batchSize {
                        try await database.updateFilesBatch(updateBatch)
                        updateBatch.removeAll(keepingCapacity: true)
                    }
                } else {
                    // File unchanged - no database operation needed
                    unchangedCount += 1
                }
            } else {
                // New file - add to insert batch
                insertBatch.append(fileEntry)
                newCount += 1

                if insertBatch.count >= batchSize {
                    try await database.insertBatch(insertBatch)
                    insertBatch.removeAll(keepingCapacity: true)
                }
            }
        }

        // Flush remaining batches
        if !insertBatch.isEmpty {
            try await database.insertBatch(insertBatch)
        }
        if !updateBatch.isEmpty {
            try await database.updateFilesBatch(updateBatch)
        }

        // Mark-and-sweep: find deleted files
        let deletedPaths = Set(existingFiles.keys).subtracting(visitedPaths)
        let deletedCount = deletedPaths.count

        if deletedCount > 0 {
            print("🗑️ Deleting \(deletedCount) removed files")
            // Delete in batches to avoid huge SQL statements
            let deleteBatchSize = 1000
            let deletedPathsArray = Array(deletedPaths)
            for i in stride(from: 0, to: deletedPathsArray.count, by: deleteBatchSize) {
                let end = min(i + deleteBatchSize, deletedPathsArray.count)
                let batch = Array(deletedPathsArray[i..<end])
                try await database.deleteFiles(driveUUID: driveUUID, relativePaths: batch)
            }
        }

        // Update drive metadata
        let fileCount = try await database.getFileCount(for: driveUUID)
        try await database.updateLastScanDate(for: driveUUID, date: Date())

        if let metadata = try await database.getDriveMetadata(driveUUID) {
            let updatedMetadata = DriveMetadata(
                uuid: metadata.uuid,
                name: metadata.name,
                lastSeen: metadata.lastSeen,
                totalCapacity: metadata.totalCapacity,
                usedCapacity: metadata.usedCapacity,
                lastScanDate: Date(),
                fileCount: fileCount
            )
            try await database.upsertDriveMetadata(updatedMetadata)
        }

        onProgress(IndexProgress(
            filesProcessed: filesProcessed,
            currentFile: "",
            isComplete: true
        ))

        print("✅ Delta index complete: \(newCount) new, \(modifiedCount) modified, \(unchangedCount) unchanged, \(deletedCount) deleted")
    }

    /// Compare file modification times with 1-second tolerance for filesystem quirks
    private func isFileModified(current: Date?, existing: Date?) -> Bool {
        // Both nil - unchanged
        if current == nil && existing == nil {
            return false
        }

        // One nil, one not - changed
        guard let currentDate = current, let existingDate = existing else {
            return true
        }

        // Compare with 1-second tolerance
        return abs(currentDate.timeIntervalSince(existingDate)) > 1.0
    }

    private func walkDirectory(at url: URL, basePath: String, driveUUID: String) -> AsyncStream<FileEntry> {
        AsyncStream { continuation in
            // Capture needed state for the synchronous enumeration
            let excludedDirs = excludedDirectories
            let excludedExts = excludedExtensions
            
            // Perform file enumeration on a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                Self.enumerateFiles(
                    at: url,
                    basePath: basePath,
                    driveUUID: driveUUID,
                    excludedDirs: excludedDirs,
                    excludedExts: excludedExts,
                    continuation: continuation
                )
            }
        }
    }
    
    private static func enumerateFiles(
        at url: URL,
        basePath: String,
        driveUUID: String,
        excludedDirs: Set<String>,
        excludedExts: Set<String>,
        continuation: AsyncStream<FileEntry>.Continuation
    ) {
        let fileManager = FileManager.default

        let resourceKeys: Set<URLResourceKey> = [
            .nameKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]

        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options,
            errorHandler: { url, error in
                // Skip permission denied errors silently
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain &&
                   nsError.code == NSFileReadNoPermissionError {
                    return true
                }
                print("Error enumerating \(url.path): \(error)")
                return true
            }
        ) else {
            continuation.finish()
            return
        }

        // Process files synchronously
        for case let fileURL as URL in enumerator {
            // Check if should skip this file/directory
            if shouldSkip(fileURL, excludedDirs: excludedDirs, excludedExts: excludedExts) {
                if isDirectory(fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            do {
                let values = try fileURL.resourceValues(forKeys: resourceKeys)

                guard let name = values.name else {
                    continue
                }

                // Calculate relative path
                let fullPath = fileURL.path
                let relativePath: String
                if fullPath.hasPrefix(basePath) {
                    relativePath = String(fullPath.dropFirst(basePath.count + 1))
                } else {
                    relativePath = fullPath
                }

                let entry = FileEntry(
                    id: nil,
                    driveUUID: driveUUID,
                    name: name,
                    relativePath: relativePath,
                    size: Int64(values.fileSize ?? 0),
                    createdAt: values.creationDate,
                    modifiedAt: values.contentModificationDate,
                    isDirectory: values.isDirectory ?? false
                )

                continuation.yield(entry)

            } catch {
                // Skip files we can't read
                continue
            }
        }

        continuation.finish()
    }

    private static func shouldSkip(_ url: URL, excludedDirs: Set<String>, excludedExts: Set<String>) -> Bool {
        let filename = url.lastPathComponent

        // Check excluded extensions
        let ext = url.pathExtension
        if !ext.isEmpty && excludedExts.contains(".\(ext)") {
            return true
        }

        if excludedExts.contains(filename) {
            return true
        }

        // Check excluded directories
        if excludedDirs.contains(filename) {
            return true
        }

        return false
    }

    private static func isDirectory(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory ?? false
        } catch {
            return false
        }
    }
}
