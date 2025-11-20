//
//  TestWindowView.swift
//  DriveIndex
//
//  Test window view to debug toolbar transparency
//

import SwiftUI

struct TestWindowView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

    @State private var selectedItem: NavigationItem? = .drives
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var appSearchState = AppSearchState()
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            NavigationSidebar(selection: $selectedItem)
                .navigationSplitViewColumnWidth(
                    min: DesignSystem.Sidebar.minWidth,
                    ideal: DesignSystem.Sidebar.width,
                    max: DesignSystem.Sidebar.maxWidth
                )
        } detail: {
            // Detail view - simplified without ZStack
            Group {
                if let selectedItem = selectedItem {
                    detailView(for: selectedItem)
                        .environment(appSearchState)
                } else {
                    Text("Select an item from the sidebar")
                        .secondaryText()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                // Centered search bar
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search files", text: $appSearchState.searchText)
                            .textFieldStyle(.plain)
                            .frame(maxWidth: 400)
                            .focused($isSearchFieldFocused)
                            .onSubmit {
                                if !appSearchState.searchText.isEmpty {
                                    selectedItem = .search
                                }
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .frame(width: 450)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: appSearchState.searchText) { oldValue, newValue in
            // Automatically switch to Search view when user types in search
            if !newValue.isEmpty && selectedItem != .search {
                selectedItem = .search
            }
        }
        .onChange(of: selectedItem) { oldValue, newValue in
            // Focus search bar when Search is selected
            if newValue == .search {
                isSearchFieldFocused = true
            }
            // Open Settings window when Settings is selected
            if newValue == .settings {
                NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
                // Revert selection back to previous item
                selectedItem = oldValue ?? .drives
            }
        }
    }

    @ViewBuilder
    private func detailView(for item: NavigationItem) -> some View {
        switch item {
        case .search:
            SearchView()
                .environmentObject(driveMonitor)
        case .drives:
            DrivesView()
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
        case .duplicates:
            DuplicatesView()
        case .indexingTest:
            IndexingView()
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
        case .settings:
            // Settings window is opened via notification, this should never be reached
            EmptyView()
        }
    }
}

#Preview {
    TestWindowView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 900, height: 600)
}
