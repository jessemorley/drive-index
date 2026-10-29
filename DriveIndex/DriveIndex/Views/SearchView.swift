//
//  SearchView.swift
//  DriveIndex
//
//  Dedicated search view with empty state
//

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @Binding var searchText: String

    @State private var searchResults: [FileDisplayItem] = []
    @State private var isSearching = false
    @State private var selectedDriveFilter: String? = nil
    @State private var selection: FileDisplayItem.ID?
    @State private var sortOrder = [KeyPathComparator(\FileDisplayItem.name, comparator: .localizedStandard)]

    private let searchManager = SearchManager()

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
        .searchable(text: $searchText, placement: .automatic, prompt: "Search files")
        .onChange(of: searchText) { oldValue, newValue in
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

    // MARK: - Empty States

    private var emptyStateView: some View {
        ContentUnavailableView(
            "Search Your Drives",
            systemImage: "magnifyingglass",
            description: Text("Use the search bar above to find files across all indexed drives")
        )
    }

    private var loadingView: some View {
        ProgressView("Searching...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        ContentUnavailableView.search(text: searchText)
    }

    // MARK: - Search Results View

    private var searchResultsView: some View {
        Table(filteredResults.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { file in
                HStack {
                    Label {
                        Text(file.name)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.listIcon(name: file.name, isDirectory: file.isDirectory))
                    }
                    Text(file.relativePath)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                }
                .lineLimit(1)
                .help(file.relativePath)
            }
            TableColumn("Size", value: \.size) { file in
                Text(file.formattedSize)
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 80)
            TableColumn("Kind", value: \.kind) { file in
                Text(file.kind)
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 120)
            TableColumn("Drive", value: \.driveName) { file in
                Label {
                    Text(file.driveName)
                } icon: {
                    Image(systemName: "circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(Color.connectionStatus(file.isConnected))
                }
                .foregroundStyle(.secondary)
            }
            .width(ideal: 120)
            TableColumn("Date Modified") { file in
                Text(file.formattedDate)
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 130)
        }
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: FileDisplayItem.ID.self) { ids in
            if let file = file(for: ids) {
                Button("Reveal in Finder") { revealInFinder(file) }
            }
        } primaryAction: { ids in
            if let file = file(for: ids) { revealInFinder(file) }
        }
    }

    private func file(for ids: Set<FileDisplayItem.ID>) -> FileDisplayItem? {
        ids.first.flatMap { id in searchResults.first { $0.id == id } }
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
    SearchView(searchText: .constant(""))
        .environmentObject(DriveMonitor())
}
