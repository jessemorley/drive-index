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

// MARK: - DuplicatesView leftovers

// ponytail: kept for DuplicatesView until its rewrite
struct DesignSystem {
    struct Spacing {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xxxLarge: CGFloat = 24
        static let cardPadding: CGFloat = 16
        static let sectionPadding: CGFloat = 20
    }

    struct CornerRadius {
        static let card: CGFloat = 12
    }

    struct Colors {
        static let cardBackgroundHover = Color.secondary.opacity(0.08)
        static let border = Color.secondary.opacity(0.15)
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
    }

    struct Typography {
        static let headline = Font.system(.headline, design: .default).weight(.semibold)
        static let body = Font.system(.body, design: .default)
        static let subheadline = Font.system(.subheadline, design: .default)
        static let caption = Font.system(.caption, design: .default)
    }
}

// ponytail: kept for DuplicatesView until its rewrite
enum Spacing {
    static let medium: CGFloat = 12
}

// ponytail: kept for DuplicatesView until its rewrite
enum AppTypography {
    static let capacityInfo = Font.system(.caption2, design: .monospaced)
}
