//
//  AppearanceView.swift
//  DriveIndex
//
//  Appearance settings view
//

import SwiftUI
import ServiceManagement

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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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

                // Startup
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("Startup")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        HStack {
                            Text("Launch at Login")
                                .font(DesignSystem.Typography.callout)

                            Spacer()

                            Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        Text("Keep DriveIndex running in the menu bar so drives are indexed as they mount.")
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

                        Text("Theme changes apply immediately. The Dock icon appears only while a DriveIndex window is open.")
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("⚠️ Launch at Login: \(error)")
        }
        // Reflect what the system actually did (it may need approval in System Settings)
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
