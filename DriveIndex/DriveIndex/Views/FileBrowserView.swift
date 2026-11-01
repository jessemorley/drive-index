//
//  FileBrowserView.swift
//  DriveIndex
//
//  Hierarchical file browser for indexed drives
//

import SwiftUI

struct FileBrowserView: View {
    let drive: DriveInfo
    /// The folder it opens at; its contents are the table's top level
    let folder: FileBrowserItem
    private let browserManager = FileBrowserManager()
    @State private var rootItems: [FileBrowserItem]? = nil
    /// Children of each expanded folder, keyed by its relative path; loaded on first expand
    @State private var childrenByPath: [String: [FileBrowserItem]] = [:]
    @State private var selection: FileNode.ID?
    @State private var sortOrder = [KeyPathComparator(\FileNode.name, comparator: .localizedStandard)]
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                Text("Error loading files: \(error)")
                    .foregroundStyle(.red)
            } else if let rootItems = rootItems {
                if rootItems.isEmpty {
                    ContentUnavailableView("Empty Folder", systemImage: "folder")
                } else {
                    table(rootItems)
                }
            }
        }
        .task {
            await loadRootItems()
        }
    }

    private func table(_ rootItems: [FileBrowserItem]) -> some View {
        Table(nodes(rootItems), children: \.children, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { node in
                if let item = node.item {
                    Label {
                        Text(item.name)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.listIcon(name: item.name, isDirectory: item.isDirectory))
                    }
                } else {
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                        .onAppear { Task { await loadChildren(of: node.parentPath) } }
                }
            }
            TableColumn("Size", value: \.size) { node in
                Text(node.item?.formattedSize ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 80)
            TableColumn("Date Modified", value: \.modifiedAt) { node in
                Text(node.item?.formattedDate ?? "")
                    .foregroundStyle(.secondary)
            }
            .width(ideal: 110)
        }
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            if let item = file(for: ids) {
                Button("Reveal in Finder") { revealInFinder(item) }
            }
        } primaryAction: { ids in
            if let item = file(for: ids) { revealInFinder(item) }
        }
    }

    /// Builds the tree from loaded data. A folder whose children aren't loaded yet gets a
    /// "Loading…" placeholder child, which loads them when it appears (i.e. on expand).
    private func nodes(_ items: [FileBrowserItem]) -> [FileNode] {
        items.map { item in
            var children: [FileNode]? = nil
            if item.isDirectory {
                children = childrenByPath[item.relativePath].map(nodes)
                    ?? [FileNode(id: item.relativePath + "/\u{0}loading", item: nil, parentPath: item.relativePath, children: nil)]
            }
            return FileNode(id: item.relativePath, item: item, parentPath: "", children: children)
        }
        .sorted(using: sortOrder)
    }

    private func file(for ids: Set<FileNode.ID>) -> FileBrowserItem? {
        guard let id = ids.first else { return nil }
        let item = (rootItems ?? []).first { $0.relativePath == id }
            ?? childrenByPath.values.lazy.flatMap { $0 }.first { $0.relativePath == id }
        return item?.isDirectory == false ? item : nil
    }

    private func loadRootItems() async {
        do {
            rootItems = try await browserManager.getChildren(driveUUID: drive.id, parentPath: folder.relativePath)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadChildren(of path: String) async {
        guard childrenByPath[path] == nil else { return }

        do {
            childrenByPath[path] = try await browserManager.getChildren(driveUUID: drive.id, parentPath: path)
        } catch {
            print("Error loading children: \(error)")
        }
    }

    private func revealInFinder(_ item: FileBrowserItem) {
        // Requires the drive to be connected
        let fullPath = (drive.path as NSString).appendingPathComponent(item.relativePath)

        if drive.isConnected && FileManager.default.fileExists(atPath: fullPath) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: fullPath)])
        } else {
            NSSound.beep()
        }
    }
}

/// The drive's top-level folders as rows in the drive detail Form; clicking one opens it in `FileBrowserView`.
struct RootFolderList: View {
    let drive: DriveInfo
    @State private var rootItems: [FileBrowserItem]?

    init(drive: DriveInfo) {
        self.drive = drive
        // From the cache before the first frame, so a revisit doesn't flash a spinner
        _rootItems = State(initialValue: FileBrowserCache.shared.get(driveUUID: drive.id, currentScanDate: drive.lastScanDate))
    }

    var body: some View {
        Group {
            if let folders = rootItems?.filter(\.isDirectory).sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard)) {
                if folders.isEmpty {
                    Text("No folders").foregroundStyle(.secondary)
                }
                ForEach(folders) { folder in
                    NavigationLink(value: folder) {
                        HStack {
                            Label {
                                Text(folder.name)
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.listIcon(name: folder.name, isDirectory: true))
                            }
                            Spacer()
                            Text(folder.formattedDate)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                // Never an empty body: a Form drops empty rows, so .task would never run
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task {
            guard rootItems == nil,
                  let items = try? await FileBrowserManager().getChildren(driveUUID: drive.id, parentPath: "") else { return }
            rootItems = items
            FileBrowserCache.shared.set(driveUUID: drive.id, rootItems: items, scanDate: drive.lastScanDate)
        }
    }
}

/// A row in the file Table: a file or folder, or a folder's "Loading…" placeholder (`item == nil`).
struct FileNode: Identifiable {
    let id: String
    let item: FileBrowserItem?
    let parentPath: String
    let children: [FileNode]?

    var name: String { item?.name ?? "" }
    var size: Int64 { item?.size ?? 0 }
    var modifiedAt: Date { item?.modifiedAt ?? .distantPast }
}

// MARK: - Preview

#Preview {
    let drive = DriveInfo(
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
    )
    Form {
        Section("Files") {
            RootFolderList(drive: drive)
        }
    }
    .formStyle(.grouped)
}

