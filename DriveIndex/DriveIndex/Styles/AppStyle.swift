//
//  AppStyle.swift
//  DriveIndex
//
//  The few app-specific style values with no system equivalent. See docs/STYLE.md.
//

import SwiftUI
import UniformTypeIdentifiers

/// "Connected" / "Disconnected" chip for the drive header and drives list. Sized by the surrounding font.
/// ponytail: macOS has no status-chip control; capsule tinted with hierarchical system colors
struct ConnectionChip: View {
    let isConnected: Bool

    var body: some View {
        Text(isConnected ? "Connected" : "Disconnected")
            .font(.caption)
            .foregroundStyle(isConnected ? Color.green : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isConnected ? Color.green.quaternary : Color.gray.quaternary, in: .capsule)
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

extension DriveInfo {
    /// The volume's own Finder icon when mounted, Finder's generic external drive icon when offline
    var finderIcon: NSImage {
        if FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        // ponytail: not public API; falls back to the generic volume (folder-looking) icon if Apple moves it
        return NSImage(contentsOfFile: "/System/Library/Extensions/IOStorageFamily.kext/Contents/Resources/External.icns")
            ?? NSWorkspace.shared.icon(for: .volume)
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

/// Sidebar column widths for the main and Settings windows. (Main window minimum size is in MainWindow.swift.)
enum SidebarWidth {
    static let min: CGFloat = 200
    static let ideal: CGFloat = 220
    static let max: CGFloat = 250
}
