//
//  MainWindowView.swift
//  DriveIndex
//
//  Main application window view
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

    @State private var selectedItem: NavigationItem? = .drives
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            NavigationSidebar(selection: $selectedItem, driveMonitor: driveMonitor)
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
                    Text("Select an item from the sidebar")
                        .secondaryText()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Indexing progress strip; safeAreaInset (not ZStack) so it pushes content up instead of covering the last rows
                if indexManager.pendingChanges != nil || indexManager.isIndexing || indexManager.isHashing {
                    IndexingStatusBar()
                        .environmentObject(indexManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: indexManager.isIndexing)
            .animation(.default, value: indexManager.isHashing)
            .animation(.default, value: indexManager.pendingChanges != nil)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: searchText) { oldValue, newValue in
            // Automatically switch to Search view when user types in search
            if !newValue.isEmpty && selectedItem != .search {
                selectedItem = .search
            }
        }
    }

    @ViewBuilder
    private func detailView(for item: NavigationItem) -> some View {
        switch item {
        case .search:
            SearchView(searchText: $searchText)
                .environmentObject(driveMonitor)
        case .drive(let driveInfo):
            DriveDetailView(drive: driveInfo)
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
        case .drives:
            DrivesView(selectedItem: $selectedItem)
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
        case .duplicates:
            DuplicatesView()
        }
    }
}

// MARK: - Indexing Progress Overlay

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

/// Thin strip at the bottom of the main window while changes are pending, a scan or hash runs, or a scan just finished.
struct IndexingStatusBar: View {
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .controlSize(.small)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
        .animation(nil, value: indexManager.currentProgress?.filesProcessed)
    }

    @ViewBuilder
    private var content: some View {
        if let pending = indexManager.pendingChanges {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
            Text("\(pending.changeCount) file change\(pending.changeCount == 1 ? "" : "s") detected on \(pending.driveName)")
        } else if let progress = indexManager.currentProgress, let summary = progress.summary {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Scan complete")
            Text(summary)
                .foregroundStyle(.secondary)
        } else if indexManager.isIndexing {
            ProgressView()
            if let progress = indexManager.currentProgress, progress.filesProcessed > 0 {
                Text("Indexing \(formatFileCount(progress.filesProcessed)) files")
                    .monospacedDigit()
                    .fixedSize()
                if !progress.currentFile.isEmpty {
                    Text(progress.currentFile)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                }
            } else {
                Text("Looking for changes on \(indexManager.indexingDriveName)")
            }
        } else if indexManager.isHashing {
            if let progress = indexManager.hashProgress {
                ProgressView(value: progress.percentage, total: 100)
                    .progressViewStyle(.circular)
                Text("Computing file hashes")
                Text(String(format: "%.0f%%", progress.percentage))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Computing file hashes for duplicate detection")
            }
            Spacer()
            Button("Cancel", systemImage: "xmark.circle.fill") {
                indexManager.cancelHashing()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Cancel hash computation")
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 900, height: 600)
}

#Preview("Status bar") {
    let indexing = IndexManager()
    indexing.isIndexing = true
    indexing.currentProgress = IndexProgress(filesProcessed: 12_345, currentFile: "Photos/2024/Trip/IMG_0042.HEIC", isComplete: false)
    let hashing = IndexManager()
    hashing.isHashing = true
    hashing.hashProgress = HashProgress(filesHashed: 42, totalFiles: 100, isComplete: false, currentFile: nil)
    let pending = IndexManager()
    pending.pendingChanges = PendingChanges(driveName: "Jesse T72", changeCount: 3)
    let done = IndexManager()
    done.currentProgress = IndexProgress(filesProcessed: 10, currentFile: "", isComplete: true, summary: "3 added, 1 removed")

    return VStack(spacing: 20) {
        ForEach([pending, indexing, hashing, done].indices, id: \.self) { i in
            IndexingStatusBar().environmentObject([pending, indexing, hashing, done][i])
        }
    }
    .frame(width: 480)
    .padding(.vertical)
}
