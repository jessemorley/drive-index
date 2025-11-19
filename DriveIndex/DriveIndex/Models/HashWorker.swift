//
//  HashWorker.swift
//  DriveIndex
//
//  Background hash computation worker with parallel processing
//

import Foundation
import CryptoKit

struct HashProgress {
    let filesHashed: Int
    let totalFiles: Int
    let isComplete: Bool
    let currentFile: String?

    var percentage: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(filesHashed) / Double(totalFiles) * 100
    }
}

actor HashWorker {
    private let database = DatabaseManager.shared
    private var isRunning = false
    private var shouldCancel = false

    // Statistics
    private var totalSuccesses = 0
    private var totalFailures = 0
    private var totalSkipped = 0

    // Cache for drive paths to avoid repeated lookups
    private var drivePathCache: [String: String] = [:]

    // Configuration
    static let CHUNK_SIZE = 32_768  // 32 KB chunks for partial hashing
    static let PARALLEL_TASKS = 8   // Process 8 files concurrently
    static let BATCH_SIZE = 1000    // DB batch update size

    /// Start hashing all unhashed files in the background
    func hashAllFiles(
        minSize: Int64,
        onProgress: @escaping @Sendable (HashProgress) -> Void
    ) async throws {
        guard !isRunning else {
            print("⚠️ Hash worker already running")
            return
        }

        isRunning = true
        shouldCancel = false
        totalSuccesses = 0
        totalFailures = 0
        totalSkipped = 0
        drivePathCache.removeAll()  // Clear cache for fresh session
        defer { isRunning = false }

        // Get total count for progress tracking
        let totalFiles = try await database.getUnhashedCount(minSize: minSize)
        guard totalFiles > 0 else {
            print("✅ No files to hash")
            onProgress(HashProgress(filesHashed: 0, totalFiles: 0, isComplete: true, currentFile: nil))
            return
        }

        print("🔨 Starting hash computation for \(totalFiles) files (min size: \(formatBytes(minSize)))")
        let overallStartTime = Date()

        var filesHashed = 0

        // Process in batches until no more unhashed files
        while !shouldCancel {
            // Get next batch of unhashed files (larger batch for parallel processing)
            let files = try await database.getUnhashedFiles(
                minSize: minSize,
                limit: Self.BATCH_SIZE
            )

            guard !files.isEmpty else {
                break // No more files to hash
            }

            // Process files in parallel groups with error handling
            let batchResults = await withTaskGroup(of: (Int64, String)?.self) { group in
                var results: [(Int64, String)] = []

                for file in files {
                    // Add task to group (will run up to PARALLEL_TASKS concurrently)
                    group.addTask {
                        do {
                            let hash = try await self.computePartialHash(
                                driveUUID: file.driveUUID,
                                relativePath: file.relativePath,
                                fileSize: file.size
                            )
                            return (file.id, hash)
                        } catch {
                            // Log error but don't fail the whole batch
                            await self.logHashError(error: error, relativePath: file.relativePath, driveUUID: file.driveUUID)
                            return nil
                        }
                    }
                }

                // Collect all results
                for await result in group {
                    if let result = result {
                        results.append(result)
                    }
                }

                return results
            }

            let batchSuccesses = batchResults.count
            let batchFailures = files.count - batchSuccesses
            totalSuccesses += batchSuccesses
            totalFailures += batchFailures

            // Batch update database
            if !batchResults.isEmpty {
                try await database.updateHashesBatch(batchResults)
                filesHashed += batchResults.count

                // Report progress
                let lastFile = files.last?.relativePath ?? ""
                onProgress(HashProgress(
                    filesHashed: filesHashed,
                    totalFiles: totalFiles,
                    isComplete: false,
                    currentFile: lastFile
                ))
            }

            // Check if we should continue
            if shouldCancel {
                print("⚠️ Hash computation cancelled")
                break
            }
        }

        // Final progress update
        onProgress(HashProgress(
            filesHashed: filesHashed,
            totalFiles: totalFiles,
            isComplete: true,
            currentFile: nil
        ))

        let totalDuration = Date().timeIntervalSince(overallStartTime)

        if totalFailures > 0 {
            print("✅ Hash computation complete: \(totalSuccesses) hashed, \(totalFailures) failed (\(String(format: "%.1f", totalDuration))s)")
        } else {
            print("✅ Hash computation complete: \(totalSuccesses) files (\(String(format: "%.1f", totalDuration))s)")
        }
    }

    private func logHashError(error: Error, relativePath: String, driveUUID: String) {
        totalSkipped += 1

        // Only log first 10 errors to avoid spam, then summarize
        if totalSkipped <= 10 {
            if let hashError = error as? HashError {
                switch hashError {
                case .driveNotFound:
                    print("   ⚠️ Drive not found for: \(relativePath)")
                case .fileNotFound:
                    print("   ⚠️ File not found: \(relativePath)")
                case .invalidFileHandle:
                    print("   ⚠️ Invalid file handle: \(relativePath)")
                }
            } else {
                print("   ⚠️ Hash error for \(relativePath): \(error.localizedDescription)")
            }
        } else if totalSkipped == 11 {
            print("   ⚠️ Further errors will be summarized...")
        }
    }

    /// Compute partial hash for a file (first 32KB + last 32KB + file size)
    private func computePartialHash(
        driveUUID: String,
        relativePath: String,
        fileSize: Int64
    ) async throws -> String {
        // Get or cache drive base path
        let basePath: String
        if let cached = drivePathCache[driveUUID] {
            basePath = cached
        } else {
            // Construct full file path by finding the drive
            let driveMetadata = try await database.getDriveMetadata(driveUUID)
            guard let metadata = driveMetadata else {
                throw HashError.driveNotFound
            }

            // Try to find the mounted drive
            // In macOS, external drives are typically mounted under /Volumes/
            let driveName = metadata.name
            let possibleBasePaths = [
                "/Volumes/\(driveName)",
                driveName  // In case it's already an absolute path
            ]

            var foundPath: String?
            for path in possibleBasePaths {
                if FileManager.default.fileExists(atPath: path) {
                    foundPath = path
                    break
                }
            }

            guard let path = foundPath else {
                print("   ⚠️ Drive not mounted or path not found: \(driveName) (UUID: \(driveUUID))")
                throw HashError.driveNotFound
            }

            // Cache the base path for future use
            drivePathCache[driveUUID] = path
            basePath = path
        }

        // Construct full file path
        let fullPath = (basePath as NSString).appendingPathComponent(relativePath)
        let fileURL = URL(fileURLWithPath: fullPath)

        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw HashError.fileNotFound
        }

        return try await computeHash(for: fileURL, fileSize: fileSize)
    }

    /// Compute hash for a file URL
    private func computeHash(for fileURL: URL, fileSize: Int64) async throws -> String {
        // Always use positioned reads since we're only reading 64KB total (32KB × 2)
        // Memory-mapped I/O is slower on external drives even for medium files
        return try computeHashPositioned(fileURL: fileURL, fileSize: fileSize)
    }

    /// Compute hash using memory-mapped I/O (fast for small files)
    private func computeHashMemoryMapped(fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let firstChunk = data.prefix(Self.CHUNK_SIZE)
        let lastChunk = data.suffix(Self.CHUNK_SIZE)

        var hasher = SHA256()
        hasher.update(data: firstChunk)
        hasher.update(data: Data(String(data.count).utf8))  // Include size
        hasher.update(data: lastChunk)

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute hash using positioned reads (efficient for large files)
    private func computeHashPositioned(fileURL: URL, fileSize: Int64) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        // Read first chunk
        let firstChunk = try handle.read(upToCount: Self.CHUNK_SIZE) ?? Data()

        // For files where chunks would overlap, just use first chunk twice
        let lastChunkOffset = max(0, fileSize - Int64(Self.CHUNK_SIZE))
        let lastChunk: Data

        if lastChunkOffset <= Int64(firstChunk.count) {
            // Chunks overlap - reuse first chunk data
            lastChunk = firstChunk.suffix(Self.CHUNK_SIZE)
        } else {
            // Seek to last chunk position
            try handle.seek(toOffset: UInt64(lastChunkOffset))
            lastChunk = try handle.read(upToCount: Self.CHUNK_SIZE) ?? Data()
        }

        // Compute hash: SHA256(first_chunk + file_size + last_chunk)
        var hasher = SHA256()
        hasher.update(data: firstChunk)
        hasher.update(data: Data(String(fileSize).utf8))
        hasher.update(data: lastChunk)

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Cancel the current hashing operation
    func cancel() {
        shouldCancel = true
    }

    /// Check if worker is currently running
    func getIsRunning() -> Bool {
        return isRunning
    }

    // Helper to format bytes for display
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

enum HashError: Error {
    case driveNotFound
    case fileNotFound
    case invalidFileHandle
}
