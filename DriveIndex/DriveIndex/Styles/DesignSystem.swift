//
//  DesignSystem.swift
//  DriveIndex
//
//  Centralized design system for consistent styling across the app
//

import SwiftUI

// MARK: - Design System

struct DesignSystem {

    // MARK: - Spacing

    struct Spacing {
        static let xxSmall: CGFloat = 2
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let xLarge: CGFloat = 16
        static let xxLarge: CGFloat = 20
        static let xxxLarge: CGFloat = 24

        // Common padding values
        static let cardPadding: CGFloat = 16
        static let sectionPadding: CGFloat = 20
        static let toolbarPadding: CGFloat = 12
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 10
        static let card: CGFloat = 12
    }

    // MARK: - Colors

    struct Colors {
        // Backgrounds
        static let cardBackground = Color(nsColor: .controlBackgroundColor)
        static let cardBackgroundHover = Color.secondary.opacity(0.08)
        static let cardBackgroundDefault = Color.secondary.opacity(0.05)
        static let windowBackground = Color(nsColor: .windowBackgroundColor)

        // UI Elements
        static let divider = Color(nsColor: .separatorColor)
        static let border = Color.secondary.opacity(0.15)
        static let borderSubtle = Color.secondary.opacity(0.08)

        // Text
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let tertiaryText = Color(nsColor: .tertiaryLabelColor)

        // Accents
        static let accent = Color.accentColor
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
    }

    // MARK: - Typography

    struct Typography {
        // Navigation & Headers
        static let largeTitle = Font.system(.largeTitle, design: .default).weight(.bold)
        static let title = Font.system(.title, design: .default).weight(.semibold)
        static let title2 = Font.system(.title2, design: .default).weight(.semibold)
        static let headline = Font.system(.headline, design: .default).weight(.semibold)

        // Body
        static let body = Font.system(.body, design: .default)
        static let bodyEmphasized = Font.system(.body, design: .default).weight(.semibold)
        static let callout = Font.system(.callout, design: .default)

        // Small text
        static let subheadline = Font.system(.subheadline, design: .default)
        static let footnote = Font.system(.footnote, design: .default)
        static let caption = Font.system(.caption, design: .default)
        static let caption2 = Font.system(.caption2, design: .default)

        // Technical/Monospaced
        static let technicalData = Font.system(.caption, design: .monospaced)
        static let technicalBody = Font.system(.body, design: .monospaced)
    }

    // MARK: - Sidebar

    struct Sidebar {
        static let width: CGFloat = 220
        static let minWidth: CGFloat = 200
        static let maxWidth: CGFloat = 250
        static let itemHeight: CGFloat = 28
        static let sectionSpacing: CGFloat = 16
        static let iconSize: CGFloat = 16
    }

    // MARK: - Toolbar

    struct Toolbar {
        static let height: CGFloat = 52
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 12
        static let buttonSpacing: CGFloat = 8
        static let searchFieldWidth: CGFloat = 200
    }

    // MARK: - Cards

    struct Card {
        static let padding: CGFloat = 16
        static let spacing: CGFloat = 12
        static let minHeight: CGFloat = 200
        static let gridSpacing: CGFloat = 16
    }

    // MARK: - Animation

    struct Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.3)
    }
}

// MARK: - View Modifiers

// MARK: Card Style

struct CardStyle: ViewModifier {
    var isHovered: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Card.padding)
            .background(
                isHovered
                    ? DesignSystem.Colors.cardBackgroundHover
                    : DesignSystem.Colors.cardBackgroundDefault
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.5)
            )
    }
}

// MARK: Section Header Style

struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Typography.headline)
            .foregroundStyle(DesignSystem.Colors.primaryText)
    }
}

// MARK: Secondary Text Style

struct SecondaryTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Typography.caption)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
    }
}

// MARK: Technical Text Style

struct TechnicalTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Typography.technicalData)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
    }
}

// MARK: Toolbar Item Style

struct ToolbarItemStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
    }
}

// MARK: Placeholder View Style

struct PlaceholderViewStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.windowBackground)
    }
}

// MARK: Search Field Style

struct SearchFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(DesignSystem.Typography.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small))
    }
}

// MARK: - View Extensions

extension View {
    /// Apply card styling with optional hover state
    func card(isHovered: Bool = false) -> some View {
        modifier(CardStyle(isHovered: isHovered))
    }

    /// Apply section header styling
    func sectionHeader() -> some View {
        modifier(SectionHeaderStyle())
    }

    /// Apply secondary text styling
    func secondaryText() -> some View {
        modifier(SecondaryTextStyle())
    }

    /// Apply technical/monospaced text styling
    func technicalText() -> some View {
        modifier(TechnicalTextStyle())
    }

    /// Apply toolbar item styling
    func toolbarItem() -> some View {
        modifier(ToolbarItemStyle())
    }

    /// Apply placeholder view styling
    func placeholderView() -> some View {
        modifier(PlaceholderViewStyle())
    }

    /// Apply search field styling
    func searchField() -> some View {
        modifier(SearchFieldStyle())
    }
}

// MARK: - Common Components

extension DesignSystem {

    /// Standard divider
    static func divider() -> some View {
        Divider()
            .background(Colors.divider)
    }

    /// Icon with consistent sizing
    static func icon(_ systemName: String, size: CGFloat = 16) -> some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.hierarchical)
    }
}
