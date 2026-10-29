//
//  DuplicatesView.swift
//  DriveIndex
//
//  Files with identical content (same hash), or folders with identical contents; one card per file
//  or folder, one row per copy
//

import SwiftUI

enum DuplicateKind: String, CaseIterable {
    case files = "Files"
    case folders = "Folders"
}

enum DuplicateSort: String, CaseIterable {
    case wasted = "Wasted Space"
    case name = "Name"
    case copies = "Copies"
}

extension DuplicateGroup {
    /// Space freed by keeping one copy
    var wastedBytes: Int64 { size * Int64(files.count - 1) }

    /// DuplicateGroup.id (name + size) isn't unique; a file belongs to exactly one group, so its id is
    var cardID: Int64 { files[0].id }
}

struct DuplicatesView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor

    @State private var groups: [DuplicateGroup] = []  // kept sorted
    @State private var expanded: Set<Int64> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var comparing: FolderPair?
    @AppStorage("duplicates.sort") private var sort: DuplicateSort = .wasted
    @AppStorage("duplicates.kind") private var kind: DuplicateKind = .files
    @AppStorage("duplicates.excludeLocal") private var excludeLocal = false

    /// The groups shown: without this Mac's copies, a group needs two copies on drives
    private var shownGroups: [DuplicateGroup] {
        guard excludeLocal, let mac = driveMonitor.drives.first(where: \.isLocal) else { return groups }
        return groups.compactMap { group in
            let files = group.files.filter { $0.driveUUID != mac.id }
            return files.count > 1 ? DuplicateGroup(name: group.name, size: group.size, count: files.count, files: files) : nil
        }
    }

    var body: some View {
        content
            .navigationTitle("Duplicates")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(id: "duplicates-toolbar") {
                ToolbarItem(id: "kind", placement: .automatic) {
                    Picker("Show", selection: $kind) {
                        ForEach(DuplicateKind.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .help("Show duplicate files or folders")
                }
                ToolbarItem(id: "sort", placement: .automatic) {
                    Picker("Sort By", selection: $sort) {
                        ForEach(DuplicateSort.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    .help("Sort duplicates")
                }
                if let mac = driveMonitor.drives.first(where: \.isLocal) {
                    ToolbarItem(id: "excludeLocal", placement: .automatic) {
                        Toggle("Exclude \(mac.name)", systemImage: "laptopcomputer", isOn: $excludeLocal)
                            .help("Hide copies on \(mac.name)")
                    }
                }
                ToolbarItem(id: "compare", placement: .automatic) {
                    Button("Compare Folders…", systemImage: "arrow.left.arrow.right") { chooseFoldersToCompare() }
                        .help("Compare two folders")
                }
                ToolbarItem(id: "refresh", placement: .automatic) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await loadGroups() }
                    }
                    .help("Refresh duplicates")
                }
            }
            .task(id: kind) { await loadGroups() }
            .onChange(of: sort) { groups = sorted(groups) }
            .sheet(item: $comparing) { pair in
                FolderCompareView(pair: pair) { moveToTrash(driveUUID: $0.driveUUID, relativePath: $0.relativePath) }
                    .environmentObject(driveMonitor)
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView(kind == .files ? "Finding duplicates..." : "Comparing folders...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView("Couldn't Load Duplicates", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if shownGroups.isEmpty {
            ContentUnavailableView("No Duplicates", systemImage: "doc.on.doc", description: Text("\(kind.rawValue) with identical contents will appear here"))
        } else {
            ScrollView {
                // Lazy: there can be thousands of groups
                LazyVStack {
                    ForEach(shownGroups, id: \.cardID) { group in
                        card(group)
                    }
                }
                .padding()
            }
        }
    }

    private func card(_ group: DuplicateGroup) -> some View {
        GroupBox {
            DisclosureGroup(isExpanded: isExpanded(group)) {
                // DisclosureGroup adds no gap under the label, so the first divider hits the header
                VStack {
                    ForEach(group.files, id: \.id) { file in
                        Divider()
                        copyRow(file, in: group)
                    }
                }
                .padding(.top, 6)
            } label: {
                header(group)
                    .contentShape(Rectangle())
                    // macOS only toggles from the chevron; let the whole header do it
                    .onTapGesture { isExpanded(group).wrappedValue.toggle() }
                    .padding(.leading, 4)
            }
            // GroupBox's inset puts the chevron tight against the card edge
            .padding(4)
        }
    }

    private func isExpanded(_ group: DuplicateGroup) -> Binding<Bool> {
        Binding {
            expanded.contains(group.cardID)
        } set: { isOn in
            if isOn { expanded.insert(group.cardID) } else { expanded.remove(group.cardID) }
        }
    }

    private func header(_ group: DuplicateGroup) -> some View {
        HStack {
            Label {
                Text(group.name)
            } icon: {
                Image(nsImage: NSWorkspace.shared.listIcon(name: group.name, isDirectory: kind == .folders))
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Text(formatted(group.size))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(group.files.count) copies")
                .foregroundStyle(.secondary)
            Text("\(formatted(group.wastedBytes)) wasted")
        }
    }

    private func copyRow(_ file: DuplicateFile, in group: DuplicateGroup) -> some View {
        let drive = driveMonitor.drives.first { $0.id == file.driveUUID }
        let connected = drive?.isConnected ?? false
        return HStack {
            Label {
                Text(file.driveName)
                    .foregroundStyle(connected ? .primary : .tertiary)
            } icon: {
                if let drive {
                    Image(nsImage: drive.finderIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
            }
            Text(file.relativePath)
                .foregroundStyle(connected ? .secondary : .tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let modifiedAt = file.modifiedAt {
                Text(modifiedAt, format: .dateTime.day().month().year())
                    .foregroundStyle(.secondary)
            }
            Button("Move to Trash", systemImage: "trash") { moveToTrash(file) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!connected)
                .help("Move this copy to the Trash")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { revealInFinder(file) }
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(file) }
                .disabled(!connected)
            Button("Move to Trash") { moveToTrash(file) }
                .disabled(!connected)
            if kind == .folders {
                Menu("Compare Parent Folder With") {
                    ForEach(group.files.filter { $0.id != file.id }, id: \.id) { other in
                        Button("\(other.driveName): \(parentLocation(other).relativePath)") {
                            comparing = FolderPair(a: parentLocation(file), b: parentLocation(other))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func sorted(_ groups: [DuplicateGroup]) -> [DuplicateGroup] {
        switch sort {
        case .wasted: groups.sorted { $0.wastedBytes > $1.wastedBytes }
        case .name: groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .copies: groups.sorted { $0.files.count > $1.files.count }
        }
    }

    private func loadGroups() async {
        isLoading = true
        errorMessage = nil
        do {
            groups = sorted(try await kind == .files
                ? DatabaseManager.shared.getDuplicateGroups()
                : DatabaseManager.shared.getDuplicateFolderGroups())
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Actions

    private func revealInFinder(_ file: DuplicateFile) {
        guard let drive = driveMonitor.drives.first(where: { $0.id == file.driveUUID }),
              let driveURL = driveMonitor.getDriveURL(for: drive) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([driveURL.appendingPathComponent(file.relativePath)])
    }

    private func parentLocation(_ folder: DuplicateFile) -> FolderLocation {
        FolderLocation(driveUUID: folder.driveUUID, driveName: folder.driveName,
                       relativePath: (folder.relativePath as NSString).deletingLastPathComponent)
    }

    /// Two Open panels, for any two folders
    private func chooseFoldersToCompare() {
        func choose(_ message: String) -> FolderLocation? {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.message = message
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return FolderLocation(url: url, drives: driveMonitor.drives)
        }
        guard let a = choose("Choose the first folder to compare"),
              let b = choose("Choose the folder to compare it with") else { return }
        comparing = FolderPair(a: a, b: b)
    }

    private func moveToTrash(_ file: DuplicateFile) {
        moveToTrash(driveUUID: file.driveUUID, relativePath: file.relativePath)
    }

    /// Trashes a file or folder, then drops it (and anything inside it) from the index and the cards
    private func moveToTrash(driveUUID: String, relativePath: String) {
        guard let drive = driveMonitor.drives.first(where: { $0.id == driveUUID }),
              let driveURL = driveMonitor.getDriveURL(for: drive),
              (try? FileManager.default.trashItem(at: driveURL.appendingPathComponent(relativePath), resultingItemURL: nil)) != nil else {
            NSSound.beep()
            return
        }
        // ponytail: drop it from the index now so it doesn't reappear before FSEvents rescans; if this fails, that rescan catches up
        Task { try? await DatabaseManager.shared.deleteFiles(driveUUID: driveUUID, relativePaths: [relativePath]) }

        func isGone(_ copy: DuplicateFile) -> Bool {
            copy.driveUUID == driveUUID
                && (copy.relativePath == relativePath || copy.relativePath.hasPrefix(relativePath + "/"))
        }
        withAnimation {
            groups = groups.compactMap { group in
                let files = group.files.filter { !isGone($0) }
                return files.count > 1 ? DuplicateGroup(name: group.name, size: group.size, count: files.count, files: files) : nil
            }
        }
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(DriveMonitor())
        .frame(width: 900, height: 700)
}
