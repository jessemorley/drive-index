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
    @State private var settingsWindow: NSWindow?
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false

    private let searchManager = SearchManager()

    var body: some View {
        VStack(spacing: 0) {
            // Search bar - replaces header
            SearchBar(
                searchText: $searchText,
                driveCount: driveMonitor.drives.count,
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
            if driveMonitor.drives.isEmpty {
                EmptyStateView()
                    .frame(height: 300)
            } else if !searchText.isEmpty {
                SearchResultsView(results: searchResults, isLoading: isSearching)
            } else {
                DriveListView()
                    .frame(height: calculateContentHeight())
            }
        }
        .frame(width: 400)
        .background(VisualEffectBackground())
        .onAppear {
            Task {
                await driveMonitor.loadDrives()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveIndexingComplete)) { _ in
            Task {
                await driveMonitor.loadDrives()
            }
        }
        .onChange(of: searchText) { newValue in
            Task {
                await performSearch(newValue)
            }
        }
    }

    private func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
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

    private func calculateContentHeight() -> CGFloat {
        let driveCount = driveMonitor.drives.count

        // Height varies based on whether drive is online (has capacity bar) or offline
        let connectedCardHeight: CGFloat = 158  // With capacity bar
        let offlineCardHeight: CGFloat = 128    // Without capacity bar

        // Calculate actual height based on drive states
        var totalCardHeight: CGFloat = 0
        let visibleDrives = min(driveCount, 3)

        for drive in driveMonitor.drives.prefix(visibleDrives) {
            totalCardHeight += drive.isConnected ? connectedCardHeight : offlineCardHeight
        }

        let cardSpacing: CGFloat = 12
        let spacingHeight = CGFloat(max(0, visibleDrives - 1)) * cardSpacing
        let containerPadding: CGFloat = 32 // top and bottom padding from DriveListView

        return totalCardHeight + spacingHeight + containerPadding
    }

    private func openSettingsWindow() {
        // If window already exists, bring it to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window with Liquid Glass styling
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified

        let settingsView = SettingsView()
            .environmentObject(indexManager)
            .environmentObject(driveMonitor)

        window.contentView = NSHostingView(rootView: settingsView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
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
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)

                        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                            Text("Files Processed")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("\(progress.filesProcessed)")
                                .font(AppTypography.technicalData)
                                .fontWeight(.semibold)
                        }
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

                    Spacer()
                }
            } else {
                ProgressView()
                    .scaleEffect(0.8)
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

// MARK: - Visual Effect Background
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // No updates needed
    }
}

#Preview {
    ContentView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
}
