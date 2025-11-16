//
//  StorageAnalysis.swift
//  DriveIndex
//
//  Storage categorization and analysis for visualization
//

import Foundation
import SwiftUI
import SQLite3

// MARK: - Storage Category

enum StorageCategory: String, CaseIterable {
    case apps
    case media
    case documents
    case system
    case other

    var displayName: String {
        switch self {
        case .apps: return "Apps"
        case .media: return "Media"
        case .documents: return "Documents"
        case .system: return "System"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .apps: return .blue
        case .media: return .pink
        case .documents: return .purple
        case .system: return .gray
        case .other: return .orange
        }
    }

    /// Determine category based on file extension and path
    static func categorize(relativePath: String) -> StorageCategory {
        let lowercasedPath = relativePath.lowercased()

        // Check for system files first (highest priority)
        if lowercasedPath.hasPrefix(".") ||
           lowercasedPath.contains("/system/") ||
           lowercasedPath.contains("/library/") ||
           lowercasedPath.hasPrefix("system/") ||
           lowercasedPath.hasPrefix("library/") {
            return .system
        }

        // Extract file extension
        let pathComponents = relativePath.split(separator: "/")
        guard let fileName = pathComponents.last else { return .other }

        let components = fileName.split(separator: ".")
        guard components.count > 1, let ext = components.last else { return .other }
        let fileExtension = ext.lowercased()

        // Categorize by extension
        if appExtensions.contains(fileExtension) {
            return .apps
        } else if mediaExtensions.contains(fileExtension) {
            return .media
        } else if documentExtensions.contains(fileExtension) {
            return .documents
        } else {
            return .other
        }
    }

    // MARK: - Extension Mappings

    private static let appExtensions: Set<String> = [
        "app", "dmg", "pkg", "exe", "dll", "so", "dylib",
        "bundle", "framework", "prefpane", "plugin", "kext"
    ]

    private static let mediaExtensions: Set<String> = [
        // Images
        "jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif",
        "bmp", "svg", "webp", "raw", "cr2", "nef", "arw", "dng",
        // Videos
        "mp4", "mov", "avi", "mkv", "m4v", "mpg", "mpeg", "wmv",
        "flv", "webm", "3gp", "mts", "m2ts",
        // Audio
        "mp3", "m4a", "aac", "wav", "flac", "aiff", "alac", "ogg",
        "wma", "opus", "ape"
    ]

    private static let documentExtensions: Set<String> = [
        // Text & Documents
        "pdf", "doc", "docx", "txt", "rtf", "md", "pages", "odt",
        "tex", "wpd", "wps",
        // Spreadsheets
        "xlsx", "xls", "csv", "numbers", "ods",
        // Presentations
        "pptx", "ppt", "key", "odp",
        // Ebooks
        "epub", "mobi", "azw", "azw3",
        // Other document formats
        "log", "json", "xml", "yaml", "yml", "toml"
    ]
}

// MARK: - Storage Breakdown

struct StorageBreakdown {
    let driveUUID: String
    let totalCapacity: Int64
    let usedCapacity: Int64
    let categories: [CategoryData]

    struct CategoryData: Identifiable {
        let id = UUID()
        let category: StorageCategory
        let size: Int64
        let fileCount: Int
        let percentage: Double
    }

    var availableSpace: Int64 {
        totalCapacity - usedCapacity
    }

    var availablePercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(availableSpace) / Double(totalCapacity)
    }

    /// Analyze storage for a given drive
    static func analyze(
        driveUUID: String,
        totalCapacity: Int64,
        usedCapacity: Int64,
        databaseManager: DatabaseManager
    ) async throws -> StorageBreakdown {
        // Dictionary to accumulate size and count per category
        var categoryStats: [StorageCategory: (size: Int64, count: Int)] = [:]

        // Initialize all categories
        for category in StorageCategory.allCases {
            categoryStats[category] = (size: 0, count: 0)
        }

        // Query all files for this drive
        let files = try await databaseManager.executeQuery(
            "SELECT relative_path, size FROM files WHERE drive_uuid = '\(driveUUID)' AND is_directory = 0"
        ) { stmt in
            var results: [(path: String, size: Int64)] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(stmt, 0))
                let size = sqlite3_column_int64(stmt, 1)
                results.append((path: path, size: size))
            }

            return results
        }

        // Categorize and accumulate
        for file in files {
            let category = StorageCategory.categorize(relativePath: file.path)
            let current = categoryStats[category]!
            categoryStats[category] = (
                size: current.size + file.size,
                count: current.count + 1
            )
        }

        // Convert to CategoryData array, sorted by size (largest first)
        // Only include categories with actual data
        let categoryData = categoryStats
            .filter { $0.value.size > 0 }
            .sorted { $0.value.size > $1.value.size }
            .map { category, stats in
                CategoryData(
                    category: category,
                    size: stats.size,
                    fileCount: stats.count,
                    percentage: totalCapacity > 0 ? Double(stats.size) / Double(totalCapacity) : 0.0
                )
            }

        return StorageBreakdown(
            driveUUID: driveUUID,
            totalCapacity: totalCapacity,
            usedCapacity: usedCapacity,
            categories: categoryData
        )
    }
}
