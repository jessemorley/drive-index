//
//  NavigationItem.swift
//  DriveIndex
//
//  Navigation items for main app window (content-focused)
//

import SwiftUI

// MARK: - Navigation Item

enum NavigationItem: String, Identifiable, CaseIterable {
    // Index section
    case drives
    case files
    case duplicates

    // Other section
    case raycast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drives: return "Drives"
        case .files: return "Files"
        case .duplicates: return "Duplicates"
        case .raycast: return "Raycast"
        }
    }

    var icon: String {
        switch self {
        case .drives: return "externaldrive"
        case .files: return "clock"
        case .duplicates: return "doc.on.doc"
        case .raycast: return "sparkles"
        }
    }

    var section: NavigationSection {
        switch self {
        case .drives, .files, .duplicates:
            return .index
        case .raycast:
            return .other
        }
    }
}

// MARK: - Navigation Section

enum NavigationSection: String, CaseIterable, Identifiable {
    case index = "Index"
    case other = "Other"

    var id: String { rawValue }

    var items: [NavigationItem] {
        NavigationItem.allCases.filter { $0.section == self }
    }
}
