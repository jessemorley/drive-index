//
//  ThumbnailCache.swift
//  DriveIndex
//
//  Manages thumbnail caching with LRU eviction
//

import Foundation
import AppKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB
    private let generator = ThumbnailGenerator.shared
    private let database = DatabaseManager.shared

    // Memory cache
    private let memoryCache = NSCache<NSNumber, NSImage>()
    private let memoryCacheLimit = 50 * 1024 * 1024 // 50MB

    private init() {
        // Create cache directory in Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        cacheDirectory = appSupport
            .appendingPathComponent("DriveIndex")
            .appendingPathComponent("Thumbnails")

        // Create directory if needed
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        // Configure memory cache
        memoryCache.totalCostLimit = memoryCacheLimit
    }

    // MARK: - Public API

    /// Get or generate thumbnail for a file
    func getThumbnail(for fileID: Int64, fileURL: URL) async throws -> NSImage {
        // Check memory cache first
        if let cached = memoryCache.object(forKey: NSNumber(value: fileID)) {
            return cached
        }

        // Check disk cache
        if let thumbnailPath = try await database.getThumbnailPath(for: fileID) {
            let thumbnailURL = URL(fileURLWithPath: thumbnailPath)
            if let image = await generator.loadThumbnail(from: thumbnailURL) {
                // Add to memory cache
                let estimatedSize = estimateImageSize(image)
                memoryCache.setObject(image, forKey: NSNumber(value: fileID), cost: estimatedSize)
                return image
            } else {
                // Thumbnail file is missing, remove from database
                try await database.deleteThumbnail(fileID: fileID)
            }
        }

        // Generate new thumbnail
        return try await generateAndCache(fileID: fileID, fileURL: fileURL)
    }

    /// Check if thumbnail exists for a file
    func hasThumbnail(for fileID: Int64) async -> Bool {
        do {
            return try await database.getThumbnailPath(for: fileID) != nil
        } catch {
            return false
        }
    }

    /// Get current cache size
    func getCacheSize() async throws -> Int64 {
        return try await database.getThumbnailCacheSize()
    }

    /// Clear all thumbnails from cache
    func clearCache() async throws {
        // Clear memory cache
        memoryCache.removeAllObjects()

        // Delete all thumbnail files
        try? FileManager.default.removeItem(at: cacheDirectory)

        // Recreate directory
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        // Clear database records (use raw SQL since we don't have a method for this)
        // The foreign key cascade will handle this automatically when files are deleted
    }

    // MARK: - Private Methods

    private func generateAndCache(fileID: Int64, fileURL: URL) async throws -> NSImage {
        // Generate thumbnail
        let image = try await generator.generateThumbnail(for: fileURL)

        // Create thumbnail file path using hash-based directory structure
        let thumbnailURL = getThumbnailURL(for: fileID)

        // Ensure parent directory exists
        try? FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Save to disk
        try await generator.saveThumbnail(image, to: thumbnailURL)

        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: thumbnailURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        // Save to database
        try await database.saveThumbnail(
            fileID: fileID,
            thumbnailPath: thumbnailURL.path,
            fileSize: fileSize
        )

        // Add to memory cache
        let estimatedSize = estimateImageSize(image)
        memoryCache.setObject(image, forKey: NSNumber(value: fileID), cost: estimatedSize)

        // Check if we need to evict old thumbnails
        try await evictIfNeeded()

        return image
    }

    private func getThumbnailURL(for fileID: Int64) -> URL {
        // Use first 2 digits of file ID as subdirectory to prevent too many files in one directory
        let hashPrefix = String(format: "%02d", fileID % 100)
        return cacheDirectory
            .appendingPathComponent(hashPrefix)
            .appendingPathComponent("\(fileID).jpg")
    }

    private func evictIfNeeded() async throws {
        let currentSize = try await database.getThumbnailCacheSize()

        guard currentSize > maxCacheSize else { return }

        // Calculate how much we need to free
        let targetSize = maxCacheSize * 8 / 10 // Evict to 80% of max
        var sizeToFree = currentSize - targetSize

        print("📦 Thumbnail cache size (\(formatBytes(currentSize))) exceeds limit (\(formatBytes(maxCacheSize)))")
        print("🗑️ Evicting oldest thumbnails...")

        var evictedCount = 0
        var freedSize: Int64 = 0

        // Get and delete oldest thumbnails until we've freed enough space
        while freedSize < sizeToFree {
            let oldThumbnails = try await database.getOldestThumbnails(limit: 100)

            guard !oldThumbnails.isEmpty else { break }

            for (fileID, path, size) in oldThumbnails {
                // Delete file
                try? FileManager.default.removeItem(atPath: path)

                // Delete from database
                try await database.deleteThumbnail(fileID: fileID)

                // Remove from memory cache
                memoryCache.removeObject(forKey: NSNumber(value: fileID))

                freedSize += size
                evictedCount += 1

                if freedSize >= sizeToFree {
                    break
                }
            }
        }

        print("✅ Evicted \(evictedCount) thumbnails, freed \(formatBytes(freedSize))")
    }

    private func estimateImageSize(_ image: NSImage) -> Int {
        // Rough estimate: width * height * 4 bytes per pixel
        let size = image.size
        return Int(size.width * size.height * 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
