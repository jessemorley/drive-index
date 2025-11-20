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
    @State private var navigationHistory: [SettingsNavigationItem] = [.appearance]
    @State private var historyIndex: Int = 0

    var body: some View {
        NavigationSplitView {
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
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .onChange(of: selectedItem) { oldValue, newValue in
            if let newValue = newValue, oldValue != newValue {
                // Add to navigation history when selection changes
                addToHistory(newValue)
            }
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
        case .duplicates:
            DuplicateSettingsView()
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
}

#Preview {
    SettingsWindowView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
}
