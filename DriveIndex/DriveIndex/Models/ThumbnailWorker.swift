//
//  ThumbnailWorker.swift
//  DriveIndex
//
//  Background thumbnail generation worker
//

import Foundation

enum ThumbnailGenerationError: Error {
    case driveNotFound
    case fileNotFound
}

struct ThumbnailProgress {
    let filesProcessed: Int
    let totalFiles: Int
    let isComplete: Bool
    let currentFile: String?

    var percentage: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(filesProcessed) / Double(totalFiles) * 100
    }
}

actor ThumbnailWorker {
    private let database = DatabaseManager.shared
    private let thumbnailCache = ThumbnailCache.shared
    private var isRunning = false
    private var shouldCancel = false

    // Statistics
    private var totalSuccesses = 0
    private var totalFailures = 0
    private var totalSkipped = 0

    // Cache for drive paths to avoid repeated lookups
    private var drivePathCache: [String: String] = [:]

    // Configuration
    static let BATCH_SIZE = 100    // Process in smaller batches
    static let PARALLEL_TASKS = 2  // Conservative parallelism to avoid IOSurface memory pressure

    /// Start generating thumbnails for media files
    func generateThumbnails(
        onProgress: @escaping @Sendable (ThumbnailProgress) -> Void
    ) async throws {
        guard !isRunning else {
            print("⚠️ Thumbnail worker already running")
            return
        }

        isRunning = true
        shouldCancel = false
        totalSuccesses = 0
        totalFailures = 0
        totalSkipped = 0
        drivePathCache.removeAll()
        defer { isRunning = false }

        // Get media files that don't have thumbnails yet
        let mediaFiles = try await getMediaFilesWithoutThumbnails()
        let totalFiles = mediaFiles.count

        guard totalFiles > 0 else {
            print("✅ No media files need thumbnails")
            onProgress(ThumbnailProgress(filesProcessed: 0, totalFiles: 0, isComplete: true, currentFile: nil))
            return
        }

        print("🖼️ Starting thumbnail generation for \(totalFiles) media files")
        let overallStartTime = Date()

        var filesProcessed = 0

        // Process in batches
        for batchStart in stride(from: 0, to: mediaFiles.count, by: Self.BATCH_SIZE) {
            guard !shouldCancel else {
                print("❌ Thumbnail generation cancelled")
                break
            }

            let batchEnd = min(batchStart + Self.BATCH_SIZE, mediaFiles.count)
            let batch = Array(mediaFiles[batchStart..<batchEnd])

            // Process batch with LIMITED parallel tasks to avoid memory pressure
            // Break batch into chunks of PARALLEL_TASKS size
            for chunkStart in stride(from: 0, to: batch.count, by: Self.PARALLEL_TASKS) {
                guard !shouldCancel else { break }

                let chunkEnd = min(chunkStart + Self.PARALLEL_TASKS, batch.count)
                let chunk = Array(batch[chunkStart..<chunkEnd])

                await withTaskGroup(of: Bool.self) { group in
                    for file in chunk {
                        group.addTask {
                            do {
                                let fileURL = try await self.getFileURL(
                                    driveUUID: file.driveUUID,
                                    relativePath: file.relativePath
                                )

                                // Generate and cache thumbnail
                                _ = try await self.thumbnailCache.getThumbnail(
                                    for: file.id,
                                    fileURL: fileURL
                                )

                                await self.incrementSuccess()
                                return true
                            } catch {
                                await self.logThumbnailError(
                                    error: error,
                                    relativePath: file.relativePath,
                                    driveUUID: file.driveUUID
                                )
                                await self.incrementFailure()
                                return false
                            }
                        }
                    }

                    // Collect results from this chunk
                    for await success in group {
                        filesProcessed += 1

                        // Report progress every 10 files or at the end
                        if filesProcessed % 10 == 0 || filesProcessed == totalFiles {
                            let currentFile = filesProcessed < batch.count ? batch[min(filesProcessed, batch.count - 1)].relativePath : nil
                            onProgress(ThumbnailProgress(
                                filesProcessed: filesProcessed,
                                totalFiles: totalFiles,
                                isComplete: filesProcessed == totalFiles,
                                currentFile: currentFile
                            ))
                        }
                    }
                }
            }

            // Small delay between batches to allow memory cleanup
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        let duration = Date().timeIntervalSince(overallStartTime)
        print("✅ Thumbnail generation complete")
        print("   • Successes: \(totalSuccesses)")
        print("   • Failures: \(totalFailures)")
        print("   • Skipped: \(totalSkipped)")
        print("   • Duration: \(String(format: "%.1f", duration))s")

        onProgress(ThumbnailProgress(
            filesProcessed: filesProcessed,
            totalFiles: totalFiles,
            isComplete: true,
            currentFile: nil
        ))
    }

    /// Cancel thumbnail generation
    func cancel() {
        shouldCancel = true
    }

    // MARK: - Private Methods

    private func getMediaFilesWithoutThumbnails() async throws -> [(id: Int64, driveUUID: String, relativePath: String)] {
        // Get media files that don't have thumbnails
        let files = try await database.getMediaFilesWithoutThumbnails(limit: 10000)
        return files.map { ($0.id, $0.driveUUID, $0.relativePath) }
    }

    private func getFileURL(driveUUID: String, relativePath: String) async throws -> URL {
        // Get drive path from cache or database
        if let cachedPath = drivePathCache[driveUUID] {
            return URL(fileURLWithPath: cachedPath).appendingPathComponent(relativePath)
        }

        // Get from database
        guard let driveMetadata = try await database.getDriveMetadata(driveUUID) else {
            throw ThumbnailGenerationError.driveNotFound
        }

        let drivePath = "/Volumes/\(driveMetadata.name)"
        drivePathCache[driveUUID] = drivePath
        return URL(fileURLWithPath: drivePath).appendingPathComponent(relativePath)
    }

    private func incrementSuccess() {
        totalSuccesses += 1
    }

    private func incrementFailure() {
        totalFailures += 1
    }

    private func incrementSkipped() {
        totalSkipped += 1
    }

    private func logThumbnailError(error: Error, relativePath: String, driveUUID: String) {
        // Simplified error logging
        print("⚠️ Failed to generate thumbnail for \(relativePath): \(error.localizedDescription)")
    }
}
