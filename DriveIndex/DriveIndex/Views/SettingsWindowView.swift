//
//  SettingsWindowView.swift
//  DriveIndex
//
//  Settings window view with sidebar navigation and search functionality
//

import SwiftUI

struct SettingsWindowView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

    @State private var selectedItem: SettingsNavigationItem? = .appearance
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var navigationHistory: [SettingsNavigationItem] = [.appearance]
    @State private var historyIndex: Int = 0

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            SettingsNavigationSidebar(selection: $selectedItem)
                .navigationSplitViewColumnWidth(
                    min: DesignSystem.Sidebar.minWidth,
                    ideal: DesignSystem.Sidebar.width,
                    max: DesignSystem.Sidebar.maxWidth
                )
        } detail: {
            // Detail view
            Group {
                if let selectedItem = selectedItem {
                    detailView(for: selectedItem)
                } else {
                    Text("Select a settings section from the sidebar")
                        .secondaryText()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                // Back/Forward navigation buttons
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoBack)
                    .help("Go Back")

                    Button(action: goForward) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)
                    .help("Go Forward")
                }

                // Search bar on the right
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search settings", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 200)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedItem) { oldValue, newValue in
            if let newValue = newValue, oldValue != newValue {
                // Add to navigation history when selection changes
                addToHistory(newValue)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            filterSettings(newValue)
        }
    }

    @ViewBuilder
    private func detailView(for item: SettingsNavigationItem) -> some View {
        switch item {
        case .appearance:
            AppearanceView()
        case .shortcuts:
            ShortcutView()
        case .indexing:
            IndexingView()
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
        case .thumbnails:
            ThumbnailsView()
        case .duplicates:
            DuplicatesSettingsView()
        case .advanced:
            AdvancedView()
                .environmentObject(driveMonitor)
        case .raycast:
            RaycastView()
        }
    }

    // MARK: - Navigation History

    private var canGoBack: Bool {
        historyIndex > 0
    }

    private var canGoForward: Bool {
        historyIndex < navigationHistory.count - 1
    }

    private func addToHistory(_ item: SettingsNavigationItem) {
        // Remove any forward history when navigating to a new item
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory.removeSubrange((historyIndex + 1)...)
        }

        // Add new item to history
        navigationHistory.append(item)
        historyIndex = navigationHistory.count - 1
    }

    private func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        selectedItem = navigationHistory[historyIndex]
    }

    private func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        selectedItem = navigationHistory[historyIndex]
    }

    // MARK: - Search

    private func filterSettings(_ query: String) {
        // Simple keyword-based navigation
        guard !query.isEmpty else { return }

        let lowercasedQuery = query.lowercased()

        // Navigate to relevant section based on keywords
        if lowercasedQuery.contains("theme") || lowercasedQuery.contains("appearance") || lowercasedQuery.contains("dark") || lowercasedQuery.contains("light") {
            selectedItem = .appearance
        } else if lowercasedQuery.contains("shortcut") || lowercasedQuery.contains("hotkey") || lowercasedQuery.contains("keyboard") {
            selectedItem = .shortcuts
        } else if lowercasedQuery.contains("index") || lowercasedQuery.contains("scan") || lowercasedQuery.contains("exclude") {
            selectedItem = .indexing
        } else if lowercasedQuery.contains("thumbnail") || lowercasedQuery.contains("preview") || lowercasedQuery.contains("image") {
            selectedItem = .thumbnails
        } else if lowercasedQuery.contains("duplicate") || lowercasedQuery.contains("hash") {
            selectedItem = .duplicates
        } else if lowercasedQuery.contains("advanced") || lowercasedQuery.contains("database") || lowercasedQuery.contains("cache") {
            selectedItem = .advanced
        } else if lowercasedQuery.contains("raycast") || lowercasedQuery.contains("extension") {
            selectedItem = .raycast
        }
    }
}

#Preview {
    SettingsWindowView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
}
