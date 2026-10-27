//
//  SettingsNavigationItem.swift
//  DriveIndex
//
//  Navigation items for Settings window sidebar
//

import SwiftUI

// MARK: - Settings Navigation Item

enum SettingsNavigationItem: String, Identifiable, CaseIterable {
    case appearance
    case indexing
    case duplicates
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .indexing: return "Indexing"
        case .duplicates: return "Duplicates"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .indexing: return "doc.text"
        case .duplicates: return "doc.on.doc"
        case .advanced: return "gearshape"
        }
    }
}
