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
    private let database = DatabaseManager()
    private var excludedDirectories: Set<String> = []
    private var excludedExtensions: Set<String> = []

    init() {
        Task {
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

        } catch {
            print("Error loading exclusion settings: \(error)")
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

    func indexDrive(
        driveURL: URL,
        driveUUID: String,
        onProgress: @escaping @Sendable (IndexProgress) -> Void
    ) async throws {
        print("Starting index of drive: \(driveURL.path)")

        // Clear existing entries for this drive
        try await database.clearDrive(driveUUID)

        var filesProcessed = 0
        var batch: [FileEntry] = []
        let batchSize = 1000

        // Get base path for relative paths
        let basePath = driveURL.path

        // Walk directory tree
        let fileStream = walkDirectory(at: driveURL, basePath: basePath)

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

        print("Indexing complete: \(filesProcessed) files processed")
    }

    private func walkDirectory(at url: URL, basePath: String) -> AsyncStream<FileEntry> {
        AsyncStream { continuation in
            Task {
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

                for case let fileURL as URL in enumerator {
                    // Yield control periodically
                    await Task.yield()

                    do {
                        // Check if should skip this file/directory
                        if shouldSkip(fileURL) {
                            if isDirectory(fileURL) {
                                enumerator.skipDescendants()
                            }
                            continue
                        }

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
                            driveUUID: url.lastPathComponent, // Will be replaced with actual UUID
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
        }
    }

    private func shouldSkip(_ url: URL) -> Bool {
        let filename = url.lastPathComponent

        // Check excluded extensions
        let ext = url.pathExtension
        if !ext.isEmpty && excludedExtensions.contains(".\(ext)") {
            return true
        }

        if excludedExtensions.contains(filename) {
            return true
        }

        // Check excluded directories
        if excludedDirectories.contains(filename) {
            return true
        }

        return false
    }

    private func isDirectory(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory ?? false
        } catch {
            return false
        }
    }
}
