//
//  StorageCache.swift
//  DriveIndex
//
//  Created to cache storage analysis results for instant display
//

import Foundation

/// Thread-safe in-memory cache for storage analysis results
actor StorageCache {
    static let shared = StorageCache()

    /// Cache entry containing the breakdown and validation metadata
    private struct CacheEntry {
        let breakdown: StorageBreakdown
        let lastScanDate: Date?
        let cachedAt: Date
    }

    /// Cache storage keyed by drive UUID
    private var cache: [String: CacheEntry] = [:]

    private init() {}

    /// Retrieves cached storage breakdown if valid
    /// - Parameters:
    ///   - driveUUID: The UUID of the drive
    ///   - currentScanDate: The current last scan date from the database
    /// - Returns: Cached StorageBreakdown if valid, nil otherwise
    func get(driveUUID: String, currentScanDate: Date?) -> StorageBreakdown? {
        guard let entry = cache[driveUUID] else {
            return nil
        }

        // Validate cache: if scan date has changed, cache is invalid
        if entry.lastScanDate != currentScanDate {
            cache.removeValue(forKey: driveUUID)
            return nil
        }

        return entry.breakdown
    }

    /// Stores a storage breakdown in the cache
    /// - Parameters:
    ///   - driveUUID: The UUID of the drive
    ///   - breakdown: The storage breakdown to cache
    ///   - scanDate: The last scan date for validation
    func set(driveUUID: String, breakdown: StorageBreakdown, scanDate: Date?) {
        let entry = CacheEntry(
            breakdown: breakdown,
            lastScanDate: scanDate,
            cachedAt: Date()
        )
        cache[driveUUID] = entry
    }

    /// Invalidates the cache entry for a specific drive
    /// - Parameter driveUUID: The UUID of the drive to invalidate
    func invalidate(driveUUID: String) {
        cache.removeValue(forKey: driveUUID)
    }

    /// Invalidates all cache entries
    func invalidateAll() {
        cache.removeAll()
    }

    /// Returns the number of cached entries (for debugging)
    var count: Int {
        cache.count
    }
}
