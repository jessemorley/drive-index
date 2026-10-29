//
//  AppStyle.swift
//  DriveIndex
//
//  The few app-specific style values with no system equivalent. See docs/STYLE.md.
//

import SwiftUI
import UniformTypeIdentifiers

/// Connection status dot: sidebar, drives list, drive header, search results. Sized by the surrounding font.
struct ConnectionDot: View {
    let isConnected: Bool

    var body: some View {
        Image(systemName: "circle.fill")
            .imageScale(.small)
            .foregroundStyle(isConnected ? .green : .secondary)
    }
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

extension NSWorkspace {
    /// Finder's icon for a file, by type rather than path so it works for offline drives.
    /// ponytail: looked up per row render; cache by extension if long tables stutter
    func listIcon(name: String, isDirectory: Bool) -> NSImage {
        let type = isDirectory ? UTType.folder : UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        let image = icon(for: type)
        image.size = NSSize(width: 16, height: 16)  // Finder list-view icon size
        return image
    }
}
