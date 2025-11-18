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
    @State private var driveListHeight: CGFloat = 300  // Cached height

    private let searchManager = SearchManager()
    private let searchResultsHeight: CGFloat = 474  // Fixed height for search results

    var body: some View {
        mainContent
            .frame(width: 550)
            .background(.thinMaterial)
            .onAppear(perform: handleOnAppear)
            .onReceive(NotificationCenter.default.publisher(for: .driveIndexingComplete)) { _ in
                Task {
                    await driveMonitor.loadDrives()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchWindowDidShow)) { _ in
                handleSearchWindowShow()
            }
            .onChange(of: searchText) { oldValue, newValue in
                Task {
                    await performSearch(newValue)
                }
            }
            .onChange(of: connectedDrives.count) { oldValue, newValue in
                driveListHeight = calculateContentHeight()
            }
            .onChange(of: driveMonitor.drives) { oldValue, newValue in
                driveListHeight = calculateContentHeight()
            }
    }
    
    private var mainContent: some View {
        VStack(spacing: 0) {
            searchBarSection
            Divider()
            statusBarSection
            contentSection
        }
    }
    
    private var searchBarSection: some View {
        SearchBar(
            searchText: $searchText,
            driveCount: driveMonitor.drives.count,
            isSearchFocused: _isSearchFocused,
            onSettingsClick: openSettingsWindow
        )
    }
    
    private var statusBarSection: some View {
        StatusBarContainer(
            pendingChanges: indexManager.pendingChanges,
            isIndexing: indexManager.isIndexing,
            currentProgress: indexManager.currentProgress,
            indexingDriveName: indexManager.indexingDriveName,
            indexManager: indexManager
        )
    }
    
    @ViewBuilder
    private var contentSection: some View {
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
                .frame(height: driveListHeight)
        }
    }
    
    private func handleOnAppear() {
        isSearchFocused = true
        driveListHeight = calculateContentHeight()
        Task {
            await driveMonitor.loadDrives()
        }
    }
    
    private func handleSearchWindowShow() {
        searchText = ""
        isSearchFocused = true
        Task {
            await driveMonitor.loadDrives()
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

struct PendingChangesView: View {
    let driveName: String
    let changeCount: Int

    var body: some View {
        HStack(spacing: Spacing.medium) {
            HStack(spacing: Spacing.xSmall) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)

                Text("CHANGES DETECTED")
                    .font(AppTypography.statusText)
                    .foregroundColor(.blue)
            }

            Text("\(changeCount) file change\(changeCount == 1 ? "" : "s") on \(driveName)")
                .font(.subheadline)
                .lineLimit(1)

            Spacer()
        }
        .padding(Spacing.medium)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

struct CompletionView: View {
    let summary: String

    var body: some View {
        HStack(spacing: Spacing.medium) {
            HStack(spacing: Spacing.xSmall) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text("SCAN COMPLETE")
                    .font(AppTypography.statusText)
                    .foregroundColor(.green)
            }

            Text(summary)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)

            Spacer()
        }
        .padding(Spacing.medium)
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ActiveIndexingView: View {
    @EnvironmentObject var indexManager: IndexManager
    @State private var isAnimating = false

    var body: some View {
        // Show single-line "Scanning" view when filesProcessed is 0 or no progress yet
        if indexManager.currentProgress == nil || indexManager.currentProgress?.filesProcessed == 0 {
            HStack(spacing: Spacing.medium) {
                HStack(spacing: Spacing.xSmall) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .opacity(isAnimating ? 1.0 : 0.5)
                        .animation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)
                        .onAppear { isAnimating = true }

                    Text("SCANNING")
                        .font(AppTypography.statusText)
                        .foregroundColor(.orange)
                }

                Text("Looking for changes on \(indexManager.indexingDriveName)")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)

                Spacer()
            }
            .padding(Spacing.medium)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
        } else {
            // Show single-line indexing progress view
            HStack(spacing: Spacing.medium) {
                HStack(spacing: Spacing.xSmall) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)

                    Text("INDEXING")
                        .font(AppTypography.statusText)
                        .foregroundColor(.orange)
                }

                if let progress = indexManager.currentProgress {
                    Text("\(formatFileCount(progress.filesProcessed)) files indexed")
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                        .frame(minWidth: 120, alignment: .leading)

                    if !progress.currentFile.isEmpty {
                        Text(progress.currentFile)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(indexManager.indexingDriveName)
                        .font(.subheadline)
                        .lineLimit(1)
                }

                Spacer()
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
}

// MARK: - Status Bar Container with Animation Control

private func formatFileCount(_ count: Int) -> String {
    let absCount = abs(count)
    if absCount >= 1_000_000 {
        let millions = Double(absCount) / 1_000_000.0
        return String(format: "%.1fM", millions)
    } else if absCount >= 1_000 {
        let thousands = Double(absCount) / 1_000.0
        return String(format: "%.1fk", thousands)
    } else {
        return "\(count)"
    }
}

struct StatusBarContainer: View {
    let pendingChanges: PendingChanges?
    let isIndexing: Bool
    let currentProgress: IndexProgress?
    let indexingDriveName: String
    let indexManager: IndexManager
    
    @State private var lastTransitionWasFromPending = false
    
    enum StatusState: Equatable {
        case none
        case pending
        case indexing
        case complete
    }
    
    private var currentState: StatusState {
        if pendingChanges != nil {
            return .pending
        } else if let progress = currentProgress, progress.summary != nil {
            return .complete
        } else if isIndexing {
            return .indexing
        } else {
            return .none
        }
    }
    
    private var transitionEffect: AnyTransition {
        if lastTransitionWasFromPending {
            return .identity
        } else {
            return .move(edge: .top).combined(with: .opacity)
        }
    }
    
    @ViewBuilder
    private var statusContent: some View {
        if let pending = pendingChanges {
            pendingChangesContent(pending)
        } else if let progress = currentProgress, let summary = progress.summary {
            completionContent(summary)
        } else if isIndexing {
            indexingContent()
        }
    }
    
    private func pendingChangesContent(_ pending: PendingChanges) -> some View {
        VStack(spacing: 0) {
            PendingChangesView(driveName: pending.driveName, changeCount: pending.changeCount)
                .padding(.horizontal, Spacing.Container.horizontalPadding)
                .padding(.vertical, Spacing.Container.verticalPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
            Divider()
        }
    }
    
    private func completionContent(_ summary: String) -> some View {
        VStack(spacing: 0) {
            CompletionView(summary: summary)
                .padding(.horizontal, Spacing.Container.horizontalPadding)
                .padding(.vertical, Spacing.Container.verticalPadding)
                .transition(.move(edge: .top).combined(with: .opacity))
            Divider()
        }
    }
    
    private func indexingContent() -> some View {
        VStack(spacing: 0) {
            ActiveIndexingView()
                .environmentObject(indexManager)
                .padding(.horizontal, Spacing.Container.horizontalPadding)
                .padding(.vertical, Spacing.Container.verticalPadding)
                .transition(transitionEffect)
            Divider()
        }
    }
    
    var body: some View {
        statusContent
            .animation(
                lastTransitionWasFromPending ? nil : .easeInOut(duration: 0.3),
                value: currentState
            )
            .onChange(of: currentState) { oldState, newState in
                // Track if we're transitioning from pending to indexing
                lastTransitionWasFromPending = (oldState == .pending && newState == .indexing)
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
}
