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
        Form {
            Section("Theme") {
                Picker(selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.rawValue, systemImage: theme.icon)
                            .tag(theme)
                    }
                } label: {
                    Text("Appearance")
                    Text("Auto mode follows your system appearance settings")
                }
                .pickerStyle(.segmented)
                .onChange(of: appTheme) { _, newValue in
                    applyTheme(newValue)
                }
            }

            Section {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                    Text("Launch at Login")
                    Text("Keep DriveIndex running in the menu bar so drives are indexed as they mount.")
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Theme changes apply immediately. The Dock icon appears only while a DriveIndex window is open.")
            }
        }
        .formStyle(.grouped)
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
