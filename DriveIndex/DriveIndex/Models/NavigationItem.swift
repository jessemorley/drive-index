//
//  NavigationItem.swift
//  DriveIndex
//
//  Navigation items for main app window (content-focused)
//

import SwiftUI

// MARK: - Navigation Item

enum NavigationItem: String, Identifiable, CaseIterable {
    // Search section (top)
    case search

    // Index section
    case drives
    case files
    case duplicates

    // Settings section (bottom)
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: return "Search"
        case .drives: return "Drives"
        case .files: return "Files"
        case .duplicates: return "Duplicates"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .drives: return "externaldrive"
        case .files: return "clock"
        case .duplicates: return "doc.on.doc"
        case .settings: return "gearshape"
        }
    }

    var section: NavigationSection {
        switch self {
        case .search:
            return .search
        case .drives, .files, .duplicates:
            return .index
        case .settings:
            return .preferences
        }
    }
}

// MARK: - Navigation Section

enum NavigationSection: String, CaseIterable, Identifiable {
    case search = "" // No header for search
    case index = "Index"
    case preferences = "" // No header for settings

    var id: String { rawValue }

    var items: [NavigationItem] {
        NavigationItem.allCases.filter { $0.section == self }
    }
}
