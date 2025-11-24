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
            NavigationSidebar(selection: $selectedItem)
                .navigationSplitViewColumnWidth(
                    min: DesignSystem.Sidebar.minWidth,
                    ideal: DesignSystem.Sidebar.width,
                    max: DesignSystem.Sidebar.maxWidth
                )
        } detail: {
            // Detail view - no ZStack wrapper to preserve toolbar transparency
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
                // Indexing progress overlay using safeAreaInset instead of ZStack
                if indexManager.pendingChanges != nil || indexManager.isIndexing || indexManager.isHashing {
                    Group {
                        if let pending = indexManager.pendingChanges {
                            PendingChangesOverlay(driveName: pending.driveName, changeCount: pending.changeCount)
                        } else if let progress = indexManager.currentProgress, let summary = progress.summary {
                            CompletionOverlay(summary: summary)
                        } else if indexManager.isIndexing {
                            ActiveIndexingOverlay()
                                .environmentObject(indexManager)
                        } else if indexManager.isHashing {
                            ActiveHashingOverlay()
                                .environmentObject(indexManager)
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: indexManager.isIndexing)
            .animation(.easeInOut(duration: 0.2), value: indexManager.isHashing)
            .animation(.easeInOut(duration: 0.2), value: indexManager.pendingChanges != nil)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search files")
        .onChange(of: searchText) { oldValue, newValue in
            // Automatically switch to Search view when user types in search
            if !newValue.isEmpty && selectedItem != .search {
                selectedItem = .search
            }
        }
        .onChange(of: selectedItem) { oldValue, newValue in
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
            SearchView(searchText: $searchText)
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

struct PendingChangesOverlay: View {
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.Container.horizontalPadding)
        .padding(.bottom, Spacing.medium)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
    }
}

struct CompletionOverlay: View {
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.Container.horizontalPadding)
        .padding(.bottom, Spacing.medium)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
    }
}

struct ActiveIndexingOverlay: View {
    @EnvironmentObject var indexManager: IndexManager
    @State private var isScanningAnimating = false
    @State private var isIndexingAnimating = false

    var body: some View {
        Group {
            // Show single-line "Scanning" view when filesProcessed is 0 or no progress yet
            if indexManager.currentProgress == nil || indexManager.currentProgress?.filesProcessed == 0 {
                HStack(spacing: Spacing.medium) {
                    HStack(spacing: Spacing.xSmall) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .opacity(isScanningAnimating ? 1.0 : 0.5)
                            .animation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isScanningAnimating)
                            .onAppear { isScanningAnimating = true }

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
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, Spacing.Container.horizontalPadding)
                .padding(.bottom, Spacing.medium)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
            } else {
                // Show single-line indexing progress view
                HStack(spacing: Spacing.medium) {
                    HStack(spacing: Spacing.xSmall) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .opacity(isIndexingAnimating ? 1.0 : 0.5)
                            .animation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isIndexingAnimating)
                            .onAppear { isIndexingAnimating = true }

                        Text("INDEXING")
                            .font(AppTypography.statusText)
                            .foregroundColor(.orange)
                    }

                    if let progress = indexManager.currentProgress {
                        Text("\(formatFileCount(progress.filesProcessed)) files indexed")
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .frame(minWidth: 120, alignment: .leading)

                        if !progress.currentFile.isEmpty {
                            Text(progress.currentFile)
                                .font(.system(.caption, design: .monospaced))
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
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, Spacing.Container.horizontalPadding)
                .padding(.bottom, Spacing.medium)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
            }
        }
        .animation(nil, value: indexManager.currentProgress?.filesProcessed)
    }
}

struct ActiveHashingOverlay: View {
    @EnvironmentObject var indexManager: IndexManager
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: Spacing.medium) {
            HStack(spacing: Spacing.xSmall) {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 6, height: 6)
                    .opacity(isAnimating ? 1.0 : 0.5)
                    .animation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isAnimating)
                    .onAppear { isAnimating = true }

                Text("ANALYSING")
                    .font(AppTypography.statusText)
                    .foregroundColor(.purple)
            }

            if let progress = indexManager.hashProgress {
                Text("Computing file hashes")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .frame(minWidth: 120, alignment: .leading)

                Text(String(format: "%.0f%%", progress.percentage))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("Computing file hashes for duplicate detection")
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }

            Spacer()

            // Cancel button
            Button(action: {
                indexManager.cancelHashing()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Cancel hash computation")
        }
        .padding(Spacing.medium)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.Container.horizontalPadding)
        .padding(.bottom, Spacing.medium)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
    }
}

#Preview {
    MainWindowView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 900, height: 600)
}
