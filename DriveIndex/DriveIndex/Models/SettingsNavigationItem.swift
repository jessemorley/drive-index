//
//  SettingsNavigationItem.swift
//  DriveIndex
//
//  Navigation items for Settings window sidebar
//

import SwiftUI

// MARK: - Settings Navigation Item

enum SettingsNavigationItem: String, Identifiable, CaseIterable {
    // Settings section
    case appearance
    case indexing
    case duplicates
    case advanced

    // Integration section
    case raycast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .indexing: return "Indexing"
        case .duplicates: return "Duplicates"
        case .advanced: return "Advanced"
        case .raycast: return "Raycast"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .indexing: return "doc.text"
        case .duplicates: return "doc.on.doc"
        case .advanced: return "gearshape"
        case .raycast: return "sparkles"
        }
    }

    var section: SettingsNavigationSection {
        switch self {
        case .appearance, .indexing, .duplicates, .advanced:
            return .settings
        case .raycast:
            return .integrations
        }
    }
}

// MARK: - Settings Navigation Section

enum SettingsNavigationSection: String, CaseIterable, Identifiable {
    case settings = "Settings"
    case integrations = "Integrations"

    var id: String { rawValue }

    var items: [SettingsNavigationItem] {
        SettingsNavigationItem.allCases.filter { $0.section == self }
    }
}
