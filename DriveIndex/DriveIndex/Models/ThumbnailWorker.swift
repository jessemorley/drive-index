//
//  ThumbnailWorker.swift
//  DriveIndex
//
//  Background thumbnail generation worker
//

import Foundation

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
    static let PARALLEL_TASKS = 4  // Lower parallelism than hash computation

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

            // Process batch with parallel tasks
            await withTaskGroup(of: Bool.self) { group in
                for file in batch {
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

                // Collect results
                for await success in group {
                    filesProcessed += 1

                    // Report progress every 10 files or at the end
                    if filesProcessed % 10 == 0 || filesProcessed == totalFiles {
                        let currentFile = filesProcessed < batch.count ? batch[filesProcessed].relativePath : nil
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
        // Query for media files that don't have thumbnails yet
        // This is a simplified version - in production you'd want to be more selective
        let mediaExtensions = [
            "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp",
            "nef", "cr2", "cr3", "arw", "dng", "raf", "orf", "rw2", "pef", "srw", "raw",
            "mp4", "mov", "m4v", "avi",
            "pdf"
        ]

        // This would ideally be a database query, but for now we'll use a simpler approach
        // In production, add a SQL query to DatabaseManager that does:
        // SELECT f.id, f.drive_uuid, f.relative_path
        // FROM files f
        // LEFT JOIN thumbnails t ON f.id = t.file_id
        // WHERE t.file_id IS NULL
        // AND f.is_directory = 0
        // AND (extension check)
        // LIMIT 10000

        // For now, return empty array - will be populated by actual DB query
        return []
    }

    private func getFileURL(driveUUID: String, relativePath: String) async throws -> URL {
        // Get drive path from cache or database
        if let cachedPath = drivePathCache[driveUUID] {
            return URL(fileURLWithPath: cachedPath).appendingPathComponent(relativePath)
        }

        // Get from database (this assumes there's a method to get drive info)
        // For now, construct path using /Volumes
        let driveName = try await getDriveName(for: driveUUID)
        let drivePath = "/Volumes/\(driveName)"

        drivePathCache[driveUUID] = drivePath
        return URL(fileURLWithPath: drivePath).appendingPathComponent(relativePath)
    }

    private func getDriveName(for uuid: String) async throws -> String {
        // This would query the database for the drive name
        // For now, simplified implementation
        return "Unknown"
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
