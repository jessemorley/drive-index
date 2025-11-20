//
//  SettingsWindowView.swift
//  DriveIndex
//
//  Settings window view with native macOS tabs and search functionality
//

import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case shortcuts = "Shortcuts"
    case indexing = "Indexing"
    case advanced = "Advanced"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .shortcuts: return "command.square.fill"
        case .indexing: return "folder.fill.badge.gearshape"
        case .advanced: return "gearshape.fill"
        }
    }
}

struct SettingsWindowView: View {
    @State private var selectedTab: SettingsTab = .appearance
    @State private var searchText = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            // Appearance tab
            AppearanceView()
                .tabItem {
                    Label(SettingsTab.appearance.rawValue, systemImage: SettingsTab.appearance.icon)
                }
                .tag(SettingsTab.appearance)

            // Shortcuts tab
            ShortcutView()
                .tabItem {
                    Label(SettingsTab.shortcuts.rawValue, systemImage: SettingsTab.shortcuts.icon)
                }
                .tag(SettingsTab.shortcuts)

            // Indexing tab
            IndexingView()
                .tabItem {
                    Label(SettingsTab.indexing.rawValue, systemImage: SettingsTab.indexing.icon)
                }
                .tag(SettingsTab.indexing)

            // Advanced tab
            AdvancedView()
                .tabItem {
                    Label(SettingsTab.advanced.rawValue, systemImage: SettingsTab.advanced.icon)
                }
                .tag(SettingsTab.advanced)
        }
        .frame(minWidth: 700, minHeight: 500)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search settings")
        .onChange(of: searchText) { oldValue, newValue in
            // Filter settings based on search text
            // This can be expanded to implement actual filtering logic
            filterSettings(newValue)
        }
    }

    private func filterSettings(_ query: String) {
        // TODO: Implement settings search/filtering
        // For now, this is a placeholder for future search functionality
        // Could highlight matching sections or switch to relevant tabs
        if query.isEmpty {
            return
        }

        let lowercasedQuery = query.lowercased()

        // Simple tab switching based on keywords
        if lowercasedQuery.contains("theme") || lowercasedQuery.contains("appearance") || lowercasedQuery.contains("dark") || lowercasedQuery.contains("light") {
            selectedTab = .appearance
        } else if lowercasedQuery.contains("shortcut") || lowercasedQuery.contains("hotkey") || lowercasedQuery.contains("keyboard") {
            selectedTab = .shortcuts
        } else if lowercasedQuery.contains("index") || lowercasedQuery.contains("scan") || lowercasedQuery.contains("exclude") {
            selectedTab = .indexing
        } else if lowercasedQuery.contains("advanced") || lowercasedQuery.contains("database") || lowercasedQuery.contains("cache") {
            selectedTab = .advanced
        }
    }
}

#Preview {
    SettingsWindowView()
}
