//
//  NavigationItem.swift
//  DriveIndex
//
//  Created for macOS System Settings-style navigation
//

import SwiftUI

// MARK: - Navigation Item

enum NavigationItem: String, Identifiable, CaseIterable {
    // Index section
    case drives
    case files
    case duplicates

    // Settings section
    case appearance
    case shortcut
    case indexing
    case advanced

    // Other section
    case raycast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drives: return "Drives"
        case .files: return "Files"
        case .duplicates: return "Duplicates"
        case .appearance: return "Appearance"
        case .shortcut: return "Shortcut"
        case .indexing: return "Indexing"
        case .advanced: return "Advanced"
        case .raycast: return "Raycast"
        }
    }

    var icon: String {
        switch self {
        case .drives: return "externaldrive"
        case .files: return "clock"
        case .duplicates: return "doc.on.doc"
        case .appearance: return "paintbrush"
        case .shortcut: return "command"
        case .indexing: return "doc.text"
        case .advanced: return "gearshape"
        case .raycast: return "sparkles"
        }
    }

    var section: NavigationSection {
        switch self {
        case .drives, .files, .duplicates:
            return .index
        case .appearance, .shortcut, .indexing, .advanced:
            return .settings
        case .raycast:
            return .other
        }
    }
}

// MARK: - Navigation Section

enum NavigationSection: String, CaseIterable, Identifiable {
    case index = "Index"
    case settings = "Settings"
    case other = "Other"

    var id: String { rawValue }

    var items: [NavigationItem] {
        NavigationItem.allCases.filter { $0.section == self }
    }
}
