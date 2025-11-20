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
    case duplicates

    // Settings section (bottom)
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: return "Search"
        case .drives: return "Drives"
        case .duplicates: return "Duplicates"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .drives: return "externaldrive"
        case .duplicates: return "doc.on.doc"
        case .settings: return "gearshape"
        }
    }

    var section: NavigationSection {
        switch self {
        case .search:
            return .search
        case .drives, .duplicates:
            return .index
        case .settings:
            return .preferences
        }
    }
}

// MARK: - Navigation Section

enum NavigationSection: CaseIterable, Identifiable {
    case search
    case index
    case preferences

    var id: String {
        switch self {
        case .search: return "search"
        case .index: return "index"
        case .preferences: return "preferences"
        }
    }

    var title: String {
        switch self {
        case .search: return "" // No header for search
        case .index: return "Index"
        case .preferences: return "" // No header for settings
        }
    }

    var items: [NavigationItem] {
        NavigationItem.allCases.filter { $0.section == self }
    }
}
