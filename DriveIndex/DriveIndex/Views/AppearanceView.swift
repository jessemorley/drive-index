//
//  AppearanceView.swift
//  DriveIndex
//
//  Appearance settings view
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case auto = "Auto"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .auto: return "circle.lefthalf.filled"
        }
    }
}

struct AppearanceView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .auto
    @AppStorage("showDockIcon") private var showDockIcon: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxLarge) {
                // Theme Selection
                SettingsSection(
                    title: "Theme",
                    description: "Choose your preferred color scheme",
                    symbol: "paintbrush.fill"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Picker("Theme", selection: $appTheme) {
                            ForEach(AppTheme.allCases) { theme in
                                Label(theme.rawValue, systemImage: theme.icon)
                                    .tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: appTheme) { _, newValue in
                            applyTheme(newValue)
                        }

                        Text("Auto mode follows your system appearance settings")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }

                // Dock Icon
                SettingsSection(
                    title: "Dock Icon",
                    description: "Control dock icon visibility",
                    symbol: "square.grid.3x3.fill.square"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Toggle(isOn: $showDockIcon) {
                            Text("Show Dock icon")
                                .font(DesignSystem.Typography.callout)
                        }
                        .toggleStyle(.switch)
                        .onChange(of: showDockIcon) { _, newValue in
                            updateDockIconVisibility(newValue)
                        }

                        Text("Hide the Dock icon to run DriveIndex as a menu bar-only app. Requires app restart to take full effect.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }

                // Info callout
                HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                    VStack(spacing: 0) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .font(DesignSystem.Typography.title2)
                    }
                    .frame(width: 24)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                        Text("Appearance Settings")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)

                        Text("Theme changes apply immediately. Dock icon changes take full effect after restarting the app.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .padding(.horizontal, DesignSystem.Spacing.sectionPadding)
            .padding(.vertical, DesignSystem.Spacing.large)
        }
        .navigationTitle("Appearance")
    }

    private func updateDockIconVisibility(_ show: Bool) {
        if show {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func applyTheme(_ theme: AppTheme) {
        // Apply appearance at app level (affects all windows)
        let appearance: NSAppearance?
        switch theme.colorScheme {
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        case nil:
            appearance = nil  // Auto - follow system
        @unknown default:
            appearance = nil
        }

        NSApp.appearance = appearance
    }
}

#Preview {
    AppearanceView()
}
