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
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("Theme")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        HStack {
                            Text("Appearance")
                                .font(DesignSystem.Typography.callout)

                            Spacer()

                            Picker("Theme", selection: $appTheme) {
                                ForEach(AppTheme.allCases) { theme in
                                    Label(theme.rawValue, systemImage: theme.icon)
                                        .tag(theme)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .onChange(of: appTheme) { _, newValue in
                                applyTheme(newValue)
                            }
                        }

                        Text("Auto mode follows your system appearance settings")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                    .padding(DesignSystem.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Dock Icon
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("Dock Icon")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        HStack {
                            Text("Show Dock icon")
                                .font(DesignSystem.Typography.callout)

                            Spacer()

                            Toggle(isOn: $showDockIcon) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .onChange(of: showDockIcon) { _, newValue in
                                updateDockIconVisibility(newValue)
                            }
                        }

                        Text("Hide the Dock icon to run DriveIndex as a menu bar-only app. Requires app restart to take full effect.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                    .padding(DesignSystem.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .padding(DesignSystem.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
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
