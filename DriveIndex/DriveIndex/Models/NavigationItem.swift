//
//  NavigationItem.swift
//  DriveIndex
//
//  Navigation items for main app window (content-focused)
//

import SwiftUI

// MARK: - Navigation Item

enum NavigationItem: Identifiable, Hashable {
    // Search section (top)
    case search

    // Drives section
    case drive(DriveInfo)

    // Index section
    case drives
    case duplicates
    case indexingTest  // Temporary test

    // Settings section (bottom)
    case settings

    var id: String {
        switch self {
        case .search: return "search"
        case .drive(let driveInfo): return "drive-\(driveInfo.id)"
        case .drives: return "drives"
        case .duplicates: return "duplicates"
        case .indexingTest: return "indexingTest"
        case .settings: return "settings"
        }
    }

    var title: String {
        switch self {
        case .search: return "Search"
        case .drive(let driveInfo): return driveInfo.name
        case .drives: return "Drives"
        case .duplicates: return "Duplicates"
        case .indexingTest: return "Indexing Test"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .drive: return "externaldrive"
        case .drives: return "externaldrive"
        case .duplicates: return "doc.on.doc"
        case .indexingTest: return "gearshape.fill"
        case .settings: return "gearshape"
        }
    }

    var section: NavigationSection {
        switch self {
        case .search:
            return .search
        case .drive:
            return .drives
        case .drives, .duplicates, .indexingTest:
            return .index
        case .settings:
            return .preferences
        }
    }

    // Static cases for iteration (excludes dynamic drive items)
    static var staticCases: [NavigationItem] {
        [.search, .drives, .duplicates, .indexingTest, .settings]
    }
}

// MARK: - Navigation Section

enum NavigationSection: CaseIterable, Identifiable {
    case search
    case drives
    case index
    case preferences

    var id: String {
        switch self {
        case .search: return "search"
        case .drives: return "drives"
        case .index: return "index"
        case .preferences: return "preferences"
        }
    }

    var title: String {
        switch self {
        case .search: return "" // No header for search
        case .drives: return "Drives"
        case .index: return "Index"
        case .preferences: return "" // No header for settings
        }
    }

    var staticItems: [NavigationItem] {
        NavigationItem.staticCases.filter { $0.section == self }
    }
}
