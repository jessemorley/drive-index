//
//  FileBrowserCache.swift
//  DriveIndex
//
//  Cache for file browser root items to eliminate loading flash when switching drives
//

import Foundation

/// Thread-safe in-memory cache for file browser root items
@MainActor
final class FileBrowserCache {
    static let shared = FileBrowserCache()

    /// Cache entry containing root items and validation metadata
    private struct CacheEntry {
        let rootItems: [FileBrowserItem]
        let lastScanDate: Date?
        let cachedAt: Date
    }

    /// Cache storage keyed by drive UUID
    private var cache: [String: CacheEntry] = [:]

    private init() {}

    /// Retrieves cached root items if valid
    /// - Parameters:
    ///   - driveUUID: The UUID of the drive
    ///   - currentScanDate: The current last scan date from the database
    /// - Returns: Cached root items if valid, nil otherwise
    func get(driveUUID: String, currentScanDate: Date?) -> [FileBrowserItem]? {
        guard let entry = cache[driveUUID] else {
            return nil
        }

        // Validate cache: if scan date has changed, cache is invalid
        if entry.lastScanDate != currentScanDate {
            cache.removeValue(forKey: driveUUID)
            return nil
        }

        return entry.rootItems
    }

    /// Stores root items in the cache
    /// - Parameters:
    ///   - driveUUID: The UUID of the drive
    ///   - rootItems: The root items to cache
    ///   - scanDate: The last scan date for validation
    func set(driveUUID: String, rootItems: [FileBrowserItem], scanDate: Date?) {
        let entry = CacheEntry(
            rootItems: rootItems,
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
