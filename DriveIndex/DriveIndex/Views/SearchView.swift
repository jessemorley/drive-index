//
//  SearchView.swift
//  DriveIndex
//
//  Dedicated search view with empty state
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @Environment(AppSearchState.self) private var appSearchState

    @State private var searchResults: [FileDisplayItem] = []
    @State private var isSearching = false
    @State private var selectedDriveFilter: String? = nil
    @State private var hoveredFileID: Int64?

    private let searchManager = SearchManager()

    // Use shared search text from AppSearchState
    private var searchText: String {
        appSearchState.searchText
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content
            if searchText.isEmpty {
                emptyStateView
            } else if isSearching {
                loadingView
            } else if searchResults.isEmpty {
                noResultsView
            } else {
                searchResultsView
            }
        }
        .navigationTitle("Search")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(id: "search-toolbar") {
            ToolbarItem(id: "filter", placement: .automatic) {
                filterMenu
            }
        }
        .onChange(of: appSearchState.searchText) { oldValue, newValue in
            Task {
                await performSearch(newValue)
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredResults: [FileDisplayItem] {
        guard let driveId = selectedDriveFilter else {
            return searchResults
        }
        return searchResults.filter { $0.driveUUID == driveId }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.xxLarge) {
            Spacer()

            VStack(spacing: DesignSystem.Spacing.large) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 72))
                    .foregroundColor(.gray)
                    .opacity(0.5)

                Text("Search Your Drives")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.primaryText)

                Text("Use the search bar above to find files across all indexed drives")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            ProgressView()
                .controlSize(.large)

            Text("Searching...")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Results View

    private var noResultsView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)
                .opacity(0.5)

            VStack(spacing: DesignSystem.Spacing.small) {
                Text("No Results Found")
                    .font(DesignSystem.Typography.headline)

                Text("Try different keywords or check your spelling")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredResults, id: \.id) { file in
                    FileRow(
                        file: file,
                        isHovered: hoveredFileID == file.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        revealInFinder(file)
                    }
                    .onHover { isHovering in
                        hoveredFileID = isHovering ? file.id : nil
                    }

                    if file.id != filteredResults.last?.id {
                        Divider()
                            .padding(.leading, DesignSystem.Spacing.cardPadding)
                    }
                }
            }
        }
    }

    // MARK: - Toolbar Items

    private var filterMenu: some View {
        Menu {
            Button(action: { selectedDriveFilter = nil }) {
                if selectedDriveFilter == nil {
                    Label("All Drives", systemImage: "checkmark")
                } else {
                    Text("All Drives")
                }
            }

            if !driveMonitor.drives.isEmpty {
                Divider()

                ForEach(driveMonitor.drives, id: \.id) { drive in
                    Button(action: { selectedDriveFilter = drive.id }) {
                        if selectedDriveFilter == drive.id {
                            Label(drive.name, systemImage: "checkmark")
                        } else {
                            Text(drive.name)
                        }
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter by drive")
    }

    // MARK: - Search

    private func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        do {
            let results = try await searchManager.search(query)
            // Convert SearchResult to FileDisplayItem
            searchResults = results.map { result in
                FileDisplayItem(
                    id: result.id,
                    name: result.name,
                    relativePath: result.relativePath,
                    size: result.size,
                    driveUUID: result.driveUUID,
                    driveName: result.driveName,
                    modifiedAt: nil, // SearchResult doesn't include dates
                    createdAt: nil,
                    isConnected: result.isConnected,
                    isDirectory: result.isDirectory
                )
            }
        } catch {
            print("Search error: \(error)")
            searchResults = []
        }

        isSearching = false
    }

    // MARK: - Actions

    private func revealInFinder(_ file: FileDisplayItem) {
        let volumePath = "/Volumes/\(file.driveName)"
        let fullPath = volumePath + "/" + file.relativePath
        let url = URL(fileURLWithPath: fullPath)

        if FileManager.default.fileExists(atPath: fullPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSSound.beep()
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(DriveMonitor())
}
