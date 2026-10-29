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
    @AppStorage("searchTableColumns") private var columnCustomization = TableColumnCustomization<FileDisplayItem>()

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
        Table(filteredResults.sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { file in
                Label {
                    Text(file.name)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.listIcon(name: file.name, isDirectory: file.isDirectory))
                }
                .lineLimit(1)
            }
            .width(min: 150, ideal: 300)
            .customizationID("name")
            // Finder pins Name: always first, can't be hidden
            .disabledCustomizationBehavior([.reorder, .visibility])
            TableColumn("Drive", value: \.driveName) { file in
                // Offline drives greyed out, as in the sidebar
                Text(file.driveName)
                    .foregroundStyle(file.isConnected ? .secondary : .tertiary)
            }
            .width(min: 80, ideal: 100)
            .customizationID("drive")
            TableColumn("Location", value: \.relativePath, comparator: .localizedStandard) { file in
                let folder = (file.relativePath as NSString).deletingLastPathComponent
                Text(folder)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(folder)
            }
            .width(min: 100, ideal: 200)
            .customizationID("location")
            TableColumn("Size", value: \.size) { file in
                Text(file.formattedSize)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 70)
            .customizationID("size")
            .alignment(.trailing)
            TableColumn("Kind", value: \.kind) { file in
                Text(file.kind)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)
            .customizationID("kind")
        }
        .tableStyle(.inset)
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
