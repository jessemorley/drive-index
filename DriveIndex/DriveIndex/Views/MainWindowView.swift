//
//  MainWindowView.swift
//  DriveIndex
//
//  Main application window with macOS System Settings-style navigation
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

    @State private var selectedItem: NavigationItem? = .drives
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
            // Detail view with overlay
            ZStack(alignment: .bottom) {
                Group {
                    if let selectedItem = selectedItem {
                        detailView(for: selectedItem)
                    } else {
                        Text("Select an item from the sidebar")
                            .secondaryText()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Indexing progress overlay at bottom of detail area
                if indexManager.isIndexing {
                    IndexingProgressOverlay()
                        .environmentObject(indexManager)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(100)  // Ensure overlay appears above content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // Constrain ZStack to detail area bounds
            .clipped()  // Prevent content from extending outside bounds
            .animation(DesignSystem.Animation.standard, value: indexManager.isIndexing)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func detailView(for item: NavigationItem) -> some View {
        switch item {
        case .drives:
            DrivesView()
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
        case .files:
            FilesView()
        case .appearance:
            AppearanceView()
        case .shortcut:
            ShortcutView()
        case .indexing:
            IndexingView()
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
        case .advanced:
            AdvancedView()
                .environmentObject(driveMonitor)
        case .raycast:
            RaycastView()
        }
    }
}

// MARK: - Indexing Progress Overlay

struct IndexingProgressOverlay: View {
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
                .frame(minHeight: 44)
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(minHeight: 44)
            }
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

// MARK: - Preview

#Preview {
    MainWindowView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 900, height: 600)
}
