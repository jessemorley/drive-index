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
    let summary: String?  // Brief summary shown after completion
    let changesCount: Int?  // nil = full scan, Int = delta scan change count

    init(filesProcessed: Int, currentFile: String, isComplete: Bool, summary: String? = nil, changesCount: Int? = nil) {
        self.filesProcessed = filesProcessed
        self.currentFile = currentFile
        self.isComplete = isComplete
        self.summary = summary
        self.changesCount = changesCount
    }
}

actor FileIndexer {
    private let database = DatabaseManager.shared
    // Sets for O(1) lookup performance during file system traversal
    private var excludedDirectories: Set<String> = []
    private var excludedExtensions: Set<String> = []
    // Arrays to preserve user-defined order for UI display
    private var excludedDirectoriesOrdered: [String] = []
    private var excludedExtensionsOrdered: [String] = []

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
                let dirs = dirSettings.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                excludedDirectoriesOrdered = dirs
                excludedDirectories = Set(dirs)
            } else {
                // Default exclusions
                let defaultDirs = [
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
                excludedDirectoriesOrdered = defaultDirs
                excludedDirectories = Set(defaultDirs)
                try await database.setSetting("excluded_directories", value: defaultDirs.joined(separator: ","))
            }

            // Load excluded extensions
            if let extSettings = try await database.getSetting("excluded_extensions") {
                let exts = extSettings.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                excludedExtensionsOrdered = exts
                excludedExtensions = Set(exts)
            } else {
                // Default exclusions
                let defaultExts = [
                    ".tmp",
                    ".cache",
                    ".DS_Store",
                    ".localized",
                    ".cof",
                    ".cos",
                    ".cot",
                    ".cop",
                    ".comask"
                ]
                excludedExtensionsOrdered = defaultExts
                excludedExtensions = Set(defaultExts)
                try await database.setSetting("excluded_extensions", value: defaultExts.joined(separator: ","))
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
                let defaultDirs = [
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
                excludedDirectoriesOrdered = defaultDirs
                excludedDirectories = Set(defaultDirs)
            }
            if excludedExtensions.isEmpty {
                let defaultExts = [
                    ".tmp",
                    ".cache",
                    ".DS_Store",
                    ".localized",
                    ".cof",
                    ".cos",
                    ".cot",
                    ".cop",
                    ".comask"
                ]
                excludedExtensionsOrdered = defaultExts
                excludedExtensions = Set(defaultExts)
            }
        } catch {
            print("Error loading exclusion settings: \(error)")
            // Use defaults if loading fails
            if excludedDirectories.isEmpty {
                let defaultDirs = [
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
                excludedDirectoriesOrdered = defaultDirs
                excludedDirectories = Set(defaultDirs)
            }
            if excludedExtensions.isEmpty {
                let defaultExts = [
                    ".tmp",
                    ".cache",
                    ".DS_Store",
                    ".localized",
                    ".cof",
                    ".cos",
                    ".cot",
                    ".cop",
                    ".comask"
                ]
                excludedExtensionsOrdered = defaultExts
                excludedExtensions = Set(defaultExts)
            }
        }
    }

    func updateExcludedDirectories(_ directories: [String]) async throws {
        excludedDirectoriesOrdered = directories
        excludedDirectories = Set(directories)
        try await database.setSetting("excluded_directories", value: directories.joined(separator: ","))
    }

    func updateExcludedExtensions(_ extensions: [String]) async throws {
        excludedExtensionsOrdered = extensions
        excludedExtensions = Set(extensions)
        try await database.setSetting("excluded_extensions", value: extensions.joined(separator: ","))
    }

    func getExcludedDirectories() -> [String] {
        excludedDirectoriesOrdered
    }

    func getExcludedExtensions() -> [String] {
        excludedExtensionsOrdered
    }

    // MARK: - Indexing

    /// Main entry point for drive indexing - intelligently chooses delta vs full scan
    func indexDrive(
        driveURL: URL,
        driveUUID: String,
        changedPaths: [String]? = nil,
        onProgress: @escaping @Sendable (IndexProgress) -> Void
    ) async throws {
        // Determine scan type based on whether this drive has been indexed before
        let driveMetadata = try await database.getDriveMetadata(driveUUID)
        let shouldUseDelta = driveMetadata?.lastScanDate != nil

        if shouldUseDelta {
            print("Starting delta index of drive: \(driveURL.path)")
            try await indexDriveDelta(
                driveURL: driveURL,
                driveUUID: driveUUID,
                changedPaths: changedPaths,
                onProgress: onProgress
            )
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
                fileCount: fileCount,
                isExcluded: metadata.isExcluded
            )
            try await database.upsertDriveMetadata(updatedMetadata)
        }

        let fileWord = filesProcessed == 1 ? "file" : "files"
        let summary = "Index complete. \(filesProcessed) \(fileWord) indexed."

        onProgress(IndexProgress(
            filesProcessed: filesProcessed,
            currentFile: "",
            isComplete: true,
            summary: summary,
            changesCount: nil  // Full scan - always optimize
        ))

        print("Full index complete: \(filesProcessed) files processed")
    }

    /// Delta indexing - only updates changed files, inserts new files, deletes removed files
    private func indexDriveDelta(
        driveURL: URL,
        driveUUID: String,
        changedPaths: [String]? = nil,
        onProgress: @escaping @Sendable (IndexProgress) -> Void
    ) async throws {
        // Fetch existing files from database
        let existingFiles = try await database.getExistingFiles(driveUUID: driveUUID)
        print("📊 Delta scan: \(existingFiles.count) existing files in database")

        // Fetch existing directories for incremental scan optimization
        let existingDirectories = try await database.getExistingDirectories(driveUUID: driveUUID)
        print("📁 Directory cache: \(existingDirectories.count) directories")

        // Build directories to scan from FSEvents paths if available
        let directoriesFromFSEvents: Set<String>?
        if let paths = changedPaths {
            let basePath = driveURL.path
            var dirs = Set<String>()

            for path in paths {
                // Convert absolute path to relative path
                guard path.hasPrefix(basePath) else { continue }

                let relativePath = String(path.dropFirst(basePath.count + 1))

                // Extract parent directory path
                if let lastSlash = relativePath.lastIndex(of: "/") {
                    let parentPath = String(relativePath[..<lastSlash])
                    dirs.insert(parentPath)

                    // Add all ancestor paths
                    var components = parentPath.split(separator: "/")
                    while !components.isEmpty {
                        components.removeLast()
                        if !components.isEmpty {
                            dirs.insert(components.joined(separator: "/"))
                        }
                    }
                } else {
                    // File in root directory - need to scan root
                    dirs.insert("")  // Empty string = root directory
                }
            }

            directoriesFromFSEvents = dirs
            print("🎯 FSEvents: \(paths.count) changed files → scanning \(dirs.count) directories")
        } else {
            directoriesFromFSEvents = nil
            // Show initial progress message during directory change detection
            onProgress(IndexProgress(
                filesProcessed: 0,
                currentFile: "Scanning drive for file changes...",
                isComplete: false
            ))
        }

        var filesProcessed = 0
        var insertBatch: [FileEntry] = []
        var updateBatch: [FileEntry] = []
        var visitedPaths = Set<String>()
        let batchSize = 1000

        var newCount = 0
        var modifiedCount = 0
        var unchangedCount = 0
        var skippedDirectories = 0

        // Get base path for relative paths
        let basePath = driveURL.path

        // Walk directory tree (with directory caching or FSEvents optimization)
        let fileStream = walkDirectory(
            at: driveURL,
            basePath: basePath,
            driveUUID: driveUUID,
            cachedDirectories: existingDirectories,
            existingFiles: existingFiles,
            directoriesFromFSEvents: directoriesFromFSEvents,
            onDirectorySkipped: { skippedDirectories += 1 },
            onFilesMarkedVisited: { paths in
                visitedPaths.formUnion(paths)
            }
        )

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

        // Update drive metadata only if changes occurred
        if newCount > 0 || modifiedCount > 0 || deletedCount > 0 {
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
                    fileCount: fileCount,
                    isExcluded: metadata.isExcluded
                )
                try await database.upsertDriveMetadata(updatedMetadata)
            }
        }

        // Build completion summary
        let totalChanges = newCount + modifiedCount + deletedCount
        let summary: String
        if totalChanges == 0 {
            summary = "Scan complete. No changes detected."
        } else {
            var parts: [String] = []
            if newCount > 0 {
                let fileWord = newCount == 1 ? "file" : "files"
                parts.append("\(newCount) new \(fileWord) added")
            }
            if modifiedCount > 0 {
                let fileWord = modifiedCount == 1 ? "file" : "files"
                parts.append("\(modifiedCount) \(fileWord) modified")
            }
            if deletedCount > 0 {
                let fileWord = deletedCount == 1 ? "file" : "files"
                parts.append("\(deletedCount) \(fileWord) deleted")
            }
            summary = "Scan complete. " + parts.joined(separator: ", " + ".")
        }

        onProgress(IndexProgress(
            filesProcessed: filesProcessed,
            currentFile: "",
            isComplete: true,
            summary: summary,
            changesCount: newCount + modifiedCount + deletedCount
        ))

        print("✅ Delta index complete: \(newCount) new, \(modifiedCount) modified, \(unchangedCount) unchanged, \(deletedCount) deleted, \(skippedDirectories) directories skipped")
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

    private func walkDirectory(
        at url: URL,
        basePath: String,
        driveUUID: String,
        cachedDirectories: [String: Date?]? = nil,
        existingFiles: [String: (id: Int64, modifiedAt: Date?)]? = nil,
        directoriesFromFSEvents: Set<String>? = nil,
        onDirectorySkipped: (() -> Void)? = nil,
        onFilesMarkedVisited: (([String]) -> Void)? = nil
    ) -> AsyncStream<FileEntry> {
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
                    cachedDirectories: cachedDirectories,
                    existingFiles: existingFiles,
                    directoriesFromFSEvents: directoriesFromFSEvents,
                    onDirectorySkipped: onDirectorySkipped,
                    onFilesMarkedVisited: onFilesMarkedVisited,
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
        cachedDirectories: [String: Date?]?,
        existingFiles: [String: (id: Int64, modifiedAt: Date?)]?,
        directoriesFromFSEvents: Set<String>?,
        onDirectorySkipped: (() -> Void)?,
        onFilesMarkedVisited: (([String]) -> Void)?,
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

        // Incremental scan optimization: Build set of directories that need scanning
        // Use FSEvents paths if available, otherwise detect changed directories
        var dirsToScan: Set<String>?
        if let fsEventsDirs = directoriesFromFSEvents {
            // FSEvents provided specific directories - use them directly
            dirsToScan = fsEventsDirs
        } else if let cachedDirs = cachedDirectories {
            var changedDirs = Set<String>()

            // Quick scan: Check which directories have changed mod times
            if let quickEnumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                for case let itemURL as URL in quickEnumerator {
                    // Skip if excluded
                    if shouldSkip(itemURL, excludedDirs: excludedDirs, excludedExts: excludedExts) {
                        if isDirectory(itemURL) {
                            quickEnumerator.skipDescendants()
                        }
                        continue
                    }

                    // Only check directories
                    guard isDirectory(itemURL) else { continue }

                    // Calculate relative path
                    let fullPath = itemURL.path
                    let relativePath: String
                    if fullPath.hasPrefix(basePath) {
                        relativePath = String(fullPath.dropFirst(basePath.count + 1))
                    } else {
                        relativePath = fullPath
                    }

                    // Check if this directory's mod time changed
                    if let cachedModTime = cachedDirs[relativePath] {
                        if let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey]),
                           let currentModTime = values.contentModificationDate {
                            // Compare timestamps with 1-second tolerance
                            let isUnchanged: Bool
                            if let cached = cachedModTime {
                                isUnchanged = abs(currentModTime.timeIntervalSince(cached)) <= 1.0
                            } else {
                                // Cached has no mod time, current does - changed
                                isUnchanged = false
                            }

                            if !isUnchanged {
                                changedDirs.insert(relativePath)
                            }
                        }
                    } else {
                        // Directory not in cache - it's new, mark as changed
                        changedDirs.insert(relativePath)
                    }
                }
            }

            // Build full set of directories to scan (changed dirs + their ancestors)
            var toScan = Set<String>()
            for changedPath in changedDirs {
                toScan.insert(changedPath)

                // Add all ancestor paths
                var pathComponents = changedPath.split(separator: "/")
                while !pathComponents.isEmpty {
                    pathComponents.removeLast()
                    if !pathComponents.isEmpty {
                        let ancestorPath = pathComponents.joined(separator: "/")
                        toScan.insert(ancestorPath)
                    }
                }
            }

            // Only use optimization if we actually have changes detected
            if changedDirs.isEmpty {
                // No directory changes - skip enumeration entirely and mark all as visited
                print("🎯 No directory changes detected, skipping enumeration")

                // Mark all existing files as visited (nothing changed, nothing to delete)
                if let existing = existingFiles {
                    onFilesMarkedVisited?(Array(existing.keys))
                }

                // Skip enumeration entirely
                continuation.finish()
                return
            } else {
                dirsToScan = toScan
                print("🎯 Directory changes detected: \(changedDirs.count) changed, \(toScan.count) total to scan")
            }
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

            // Incremental scan: Skip directories that don't need scanning
            if let dirsToScan = dirsToScan, isDirectory(fileURL) {
                // Calculate relative path
                let fullPath = fileURL.path
                let relativePath: String
                if fullPath.hasPrefix(basePath) {
                    relativePath = String(fullPath.dropFirst(basePath.count + 1))
                } else {
                    relativePath = fullPath
                }

                if !dirsToScan.contains(relativePath) {
                    // This directory and all its ancestors are unchanged - skip it
                    enumerator.skipDescendants()
                    onDirectorySkipped?()

                    // Mark all files in this directory as visited
                    if let existing = existingFiles {
                        var pathsToMark: [String] = []
                        let dirPrefix = relativePath + "/"
                        for (filePath, _) in existing {
                            if filePath == relativePath || filePath.hasPrefix(dirPrefix) {
                                pathsToMark.append(filePath)
                            }
                        }
                        if !pathsToMark.isEmpty {
                            onFilesMarkedVisited?(pathsToMark)
                        }
                    }

                    continue
                }
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
