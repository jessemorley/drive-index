//
//  AppStyle.swift
//  DriveIndex
//
//  The few app-specific style values with no system equivalent. See docs/STYLE.md.
//

import SwiftUI

extension DriveInfo {
    /// Sidebar dot and drive header status.
    var connectionStatusColor: Color { isConnected ? .green : .secondary }
}

extension StorageCategory {
    /// Storage bar and legend. System colors so they adapt to Dark Mode and Increase Contrast.
    var color: Color {
        switch self {
        case .apps: return .blue
        case .media: return .pink
        case .documents: return .purple
        case .system: return .gray
        case .other: return .orange
        }
    }
}
