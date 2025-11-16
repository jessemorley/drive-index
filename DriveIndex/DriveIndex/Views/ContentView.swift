//
//  ContentView.swift
//  DriveIndex
//
//  Main popover content view
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var previousSearchResults: [SearchResult] = []
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool

    private let searchManager = SearchManager()
    private let searchResultsHeight: CGFloat = 474  // Fixed height for search results

    var body: some View {
        VStack(spacing: 0) {
            // Search bar at top of window
            SearchBar(
                searchText: $searchText,
                driveCount: driveMonitor.drives.count,
                isSearchFocused: _isSearchFocused,
                onSettingsClick: openSettingsWindow
            )

            Divider()

            // Indexing progress indicator
            if indexManager.isIndexing {
                IndexingProgressView()
                    .padding(.horizontal, Spacing.Container.horizontalPadding)
                    .padding(.vertical, Spacing.Container.verticalPadding)
                Divider()
            }

            // Conditional content: search results or drive list
            if !searchText.isEmpty {
                SearchResultsView(
                    results: searchResults,
                    previousResults: previousSearchResults,
                    isLoading: isSearching,
                    contentHeight: searchResultsHeight
                )
                .frame(height: searchResultsHeight)
            } else if connectedDrives.isEmpty {
                EmptyStateView()
                    .frame(height: 300)
            } else {
                DriveListView()
                    .frame(height: calculateContentHeight())
            }
        }
        .frame(width: 550)
        .background(.thinMaterial)
        .onAppear {
            // Auto-focus search field when window appears
            isSearchFocused = true

            Task {
                await driveMonitor.loadDrives()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveIndexingComplete)) { _ in
            Task {
                await driveMonitor.loadDrives()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchWindowDidShow)) { _ in
            // Clear search text to show drive list
            searchText = ""

            // Refresh drives and focus search when window is shown via hotkey
            isSearchFocused = true
            Task {
                await driveMonitor.loadDrives()
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            Task {
                await performSearch(newValue)
            }
        }
    }

    private func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            previousSearchResults = []
            isSearching = false
            return
        }

        // Preserve previous results before starting new search
        if !searchResults.isEmpty {
            previousSearchResults = searchResults
        }

        isSearching = true

        do {
            let results = try await searchManager.search(query)
            searchResults = results
        } catch {
            print("Search error: \(error)")
            searchResults = []
        }

        isSearching = false
    }

    private var connectedDrives: [DriveInfo] {
        driveMonitor.drives.filter { $0.isConnected }
    }

    private func calculateContentHeight() -> CGFloat {
        let driveCount = connectedDrives.count

        // All drives shown in menu bar are connected, so use connected card height
        let connectedCardHeight: CGFloat = 158  // With capacity bar

        // Calculate actual height based on drive count
        let visibleDrives = min(driveCount, 3)
        let totalCardHeight = CGFloat(visibleDrives) * connectedCardHeight

        let cardSpacing: CGFloat = 12
        let spacingHeight = CGFloat(max(0, visibleDrives - 1)) * cardSpacing
        let containerPadding: CGFloat = 32 // top and bottom padding from DriveListView

        return totalCardHeight + spacingHeight + containerPadding
    }

    private func openSettingsWindow() {
        // Post notification to AppDelegate to open the main window
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Spacing.large) {
            VStack(spacing: Spacing.medium) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                    .opacity(0.5)

                VStack(spacing: Spacing.small) {
                    Text("No Drives Connected")
                        .font(AppTypography.sectionHeader)

                    Text("Connect an external drive to begin indexing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.large)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Helpful tip
            HStack(spacing: Spacing.medium) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                    .font(.caption)

                Text("Tip: DriveIndex automatically scans drives when connected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.medium)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.large)
    }
}

struct IndexingProgressView: View {
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header with status
            HStack(spacing: Spacing.medium) {
                HStack(spacing: Spacing.xSmall) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)

                    Text("INDEXING")
                        .font(AppTypography.statusText)
                        .foregroundColor(.orange)
                }

                Text(indexManager.indexingDriveName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Button("Cancel") {
                    indexManager.cancelIndexing()
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .font(.caption)
            }

            // Progress info
            if let progress = indexManager.currentProgress {
                HStack(spacing: Spacing.large) {
                    HStack(spacing: Spacing.small) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)

                        // Show summary message if available, otherwise status/progress
                        if let summary = progress.summary {
                            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                                Text(summary)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(.secondary)
                            }
                        } else if progress.filesProcessed == 0 && !progress.currentFile.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                                Text(progress.currentFile)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // Show file count when actually processing
                            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                                Text("Files Processed")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Text("\(progress.filesProcessed)")
                                    .font(AppTypography.technicalData)
                                    .fontWeight(.semibold)
                            }

                            if !progress.currentFile.isEmpty {
                                Divider()
                                    .frame(height: 24)

                                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                                    Text("Current File")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text(progress.currentFile)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(Spacing.medium)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
}
