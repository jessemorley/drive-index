//
//  FileBrowserView.swift
//  DriveIndex
//
//  Hierarchical file browser for indexed drives
//

import SwiftUI

struct FileBrowserView: View {
    let drive: DriveInfo
    private let browserManager = FileBrowserManager()
    @State private var rootItems: [FileBrowserItem]? = nil
    @State private var expandedPaths: Set<String> = []
    @State private var isLoading = false
    @State private var error: String?

    init(drive: DriveInfo) {
        self.drive = drive

        // Populate state synchronously BEFORE first render
        // No await needed - FileBrowserCache is @MainActor
        let cached = FileBrowserCache.shared.get(
            driveUUID: drive.id,
            currentScanDate: drive.lastScanDate
        )
        _rootItems = State(initialValue: cached)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Files")
                .sectionHeader()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let error = error {
                Text("Error loading files: \(error)")
                    .foregroundColor(.red)
                    .font(DesignSystem.Typography.caption)
                    .padding()
            } else if let rootItems = rootItems {
                if rootItems.isEmpty {
                    Text("No files found")
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .font(DesignSystem.Typography.body)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rootItems) { item in
                                FileBrowserLevel(
                                    item: item,
                                    driveUUID: drive.id,
                                    depth: 0,
                                    expandedPaths: $expandedPaths,
                                    browserManager: browserManager
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 400)
                    .card()
                }
            }
        }
        .task {
            await loadRootItems()
        }
    }

    private func loadRootItems() async {
        // If we already have items from cache init, don't reload
        if rootItems != nil {
            return
        }

        // No cache hit during init - load from database
        isLoading = true
        error = nil

        do {
            let items = try await browserManager.getChildren(driveUUID: drive.id, parentPath: "")
            rootItems = items

            // Cache the result for future use
            FileBrowserCache.shared.set(
                driveUUID: drive.id,
                rootItems: items,
                scanDate: drive.lastScanDate
            )

            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Recursive Level Component

struct FileBrowserLevel: View {
    let item: FileBrowserItem
    let driveUUID: String
    let depth: Int
    @Binding var expandedPaths: Set<String>
    let browserManager: FileBrowserManager

    @State private var children: [FileBrowserItem] = []
    @State private var isLoadingChildren = false

    private var isExpanded: Bool {
        expandedPaths.contains(item.relativePath)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Current item row
            Button(action: handleTap) {
                FileTreeRow(
                    item: item,
                    depth: depth,
                    isExpanded: isExpanded,
                    onToggle: toggleExpansion
                )
            }
            .buttonStyle(.plain)

            // Children (if expanded)
            if isExpanded {
                if isLoadingChildren {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    .padding(.leading, CGFloat(depth + 1) * 20 + 60)
                    .padding(.vertical, DesignSystem.Spacing.small)
                } else {
                    ForEach(children) { child in
                        FileBrowserLevel(
                            item: child,
                            driveUUID: driveUUID,
                            depth: depth + 1,
                            expandedPaths: $expandedPaths,
                            browserManager: browserManager
                        )
                    }
                }
            }
        }
    }

    private func handleTap() {
        if item.isDirectory {
            toggleExpansion()
        } else {
            // Reveal file in Finder
            revealInFinder()
        }
    }

    private func toggleExpansion() {
        guard item.isDirectory else { return }

        if isExpanded {
            // Collapse
            expandedPaths.remove(item.relativePath)
        } else {
            // Expand and load children
            expandedPaths.insert(item.relativePath)
            Task {
                await loadChildren()
            }
        }
    }

    private func loadChildren() async {
        guard children.isEmpty else { return }

        isLoadingChildren = true

        do {
            children = try await browserManager.getChildren(driveUUID: driveUUID, parentPath: item.relativePath)
            isLoadingChildren = false
        } catch {
            print("Error loading children: \(error)")
            isLoadingChildren = false
        }
    }

    private func revealInFinder() {
        // Construct full path by combining drive path with relative path
        // Note: This requires the drive to be connected
        let driveMonitor = DriveMonitor()

        Task {
            if let drives = try? await driveMonitor.drives,
               let matchingDrive = drives.first(where: { $0.id == driveUUID }),
               matchingDrive.isConnected {
                let fullPath = (matchingDrive.path as NSString).appendingPathComponent(item.relativePath)
                let url = URL(fileURLWithPath: fullPath)

                if FileManager.default.fileExists(atPath: fullPath) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSSound.beep()
                }
            } else {
                NSSound.beep()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FileBrowserView(drive: DriveInfo(
        id: "test-uuid",
        name: "My External Drive",
        path: "/Volumes/MyDrive",
        totalCapacity: 500_000_000_000,
        availableCapacity: 200_000_000_000,
        isConnected: true,
        lastSeen: Date(),
        lastScanDate: Date(),
        fileCount: 15432,
        isExcluded: false
    ))
    .padding()
}
