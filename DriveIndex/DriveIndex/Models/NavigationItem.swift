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
    case maskBackups

    var id: String {
        switch self {
        case .search: return "search"
        case .drive(let driveInfo): return "drive-\(driveInfo.id)"
        case .drives: return "drives"
        case .duplicates: return "duplicates"
        case .maskBackups: return "maskBackups"
        }
    }

    var title: String {
        switch self {
        case .search: return "Search"
        case .drive(let driveInfo): return driveInfo.name
        case .drives: return "Drives"
        case .duplicates: return "Duplicates"
        case .maskBackups: return "Capture One"
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .drive: return "externaldrive"
        case .drives: return "externaldrive"
        case .duplicates: return "doc.on.doc"
        case .maskBackups: return "camera.aperture"
        }
    }
}
