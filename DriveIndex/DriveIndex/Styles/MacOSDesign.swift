//
//  MacOSDesign.swift
//  DriveIndex
//
//  macOS 15 Sequoia design system constants
//

import SwiftUI

enum MacOSDesign {
    // MARK: - Corner Radius
    enum CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let card: CGFloat = 12
    }

    // MARK: - Sidebar
    enum Sidebar {
        static let width: CGFloat = 220
        static let minWidth: CGFloat = 200
        static let maxWidth: CGFloat = 250
        static let itemHeight: CGFloat = 28
        static let sectionSpacing: CGFloat = 16
    }

    // MARK: - Toolbar
    enum Toolbar {
        static let height: CGFloat = 52
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 12
        static let buttonSpacing: CGFloat = 8
    }

    // MARK: - Cards
    enum Card {
        static let padding: CGFloat = 16
        static let spacing: CGFloat = 12
        static let minHeight: CGFloat = 200
    }

    // MARK: - Content
    enum Content {
        static let padding: CGFloat = 20
        static let spacing: CGFloat = 16
    }

    // MARK: - Colors
    enum Colors {
        static let cardBackground = Color(nsColor: .controlBackgroundColor)
        static let cardBackgroundHover = Color.secondary.opacity(0.08)
        static let cardBackgroundDefault = Color.secondary.opacity(0.05)

        static let sidebarBackground = Color(nsColor: .controlBackgroundColor)
        static let sidebarSelectedBackground = Color.accentColor

        static let divider = Color(nsColor: .separatorColor)
        static let border = Color.secondary.opacity(0.15)
    }

    // MARK: - Typography (SF Pro)
    enum Typography {
        static let navigationTitle = Font.system(.largeTitle, design: .default).weight(.bold)
        static let sectionHeader = Font.system(.headline, design: .default).weight(.semibold)
        static let body = Font.system(.body, design: .default)
        static let caption = Font.system(.caption, design: .default)
        static let caption2 = Font.system(.caption2, design: .default)
    }

    // MARK: - Animation
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
    }
}

// MARK: - Card Style ViewModifier

struct MacOSCardStyle: ViewModifier {
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(MacOSDesign.Card.padding)
            .background(
                isHovered ? MacOSDesign.Colors.cardBackgroundHover : MacOSDesign.Colors.cardBackgroundDefault
            )
            .cornerRadius(MacOSDesign.CornerRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: MacOSDesign.CornerRadius.card)
                    .strokeBorder(MacOSDesign.Colors.border, lineWidth: 0.5)
            )
    }
}

extension View {
    func macOSCard(isHovered: Bool = false) -> some View {
        modifier(MacOSCardStyle(isHovered: isHovered))
    }
}
