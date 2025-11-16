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
        case .appearance: return "Appearance"
        case .shortcut: return "Shortcut"
        case .indexing: return "Indexing"
        case .advanced: return "Advanced"
        case .raycast: return "Raycast"
        }
    }

    var icon: String {
        switch self {
        case .drives: return "externaldrive.fill"
        case .files: return "clock.fill"
        case .appearance: return "paintbrush.fill"
        case .shortcut: return "command"
        case .indexing: return "doc.text.fill"
        case .advanced: return "gearshape.fill"
        case .raycast: return "sparkles"
        }
    }

    var section: NavigationSection {
        switch self {
        case .drives, .files:
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
