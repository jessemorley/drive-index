//
//  DuplicatesView.swift
//  DriveIndex
//
//  Duplicates by folder: a review list of the sets of folders holding copies of each other's files
//  (pick one to keep, trash the others once nothing blocks it), then the duplicate files with a copy
//  outside every set
//

import SwiftUI

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

extension FolderSet.Member {
    /// Shown under the folder and in the Trash confirmation
    var verdict: String {
        if holdsAnother { return "Holds another folder of this set, so it can't be trashed from here" }
        if isSafeToRemove { return "Safe to remove: every file has a copy in another folder" }
        let reasons = [(onlyHere, "only here"), (changed, "changed"), (unchecked, "not checked yet")]
            .filter { $0.0 > 0 }.map { "\($0.0.formatted()) \($0.1)" }
        return "Not safe to remove: " + reasons.joined(separator: ", ")
    }
}

struct DuplicatesView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor

    // Kept sorted
    @State private var sets: [FolderSet] = []
    @State private var loose: [DuplicateGroup] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var comparing: FolderPair?
    @AppStorage("duplicates.sort") private var sort: DuplicateSort = .wasted
    @AppStorage("duplicates.excludeLocal") private var excludeLocal = false
    @State private var webTopInset: CGFloat = 0

    var body: some View {
        content
            .navigationTitle("Duplicates")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(id: "duplicates-toolbar") {
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
                        Task { await load() }
                    }
                    .help("Refresh duplicates")
                }
            }
            .task(id: excludeLocal) { await load() }
            .onChange(of: sort) { (sets, loose) = (sorted(sets), sorted(loose)) }
            .sheet(item: $comparing) { pair in
                FolderCompareView(pair: pair) { moveToTrash(driveUUID: $0.driveUUID, relativePath: $0.relativePath) }
                    .environmentObject(driveMonitor)
            }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView("Couldn't Load Duplicates", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if !loaded {
            // Only the first load: later ones update the page in place, so changes animate
            ProgressView("Finding duplicates...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sets.isEmpty && loose.isEmpty {
            ContentUnavailableView("No Duplicates", systemImage: "doc.on.doc", description: Text("Files with identical contents will appear here"))
        } else {
            // Not a GeometryReader: that rebuilt the pane, and re-sent every card, on each frame of a resize
            Color.clear
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { webTopInset = $0 }
                .overlay {
                    DuplicatesWebPane(sets: sets, loose: loose, drives: driveMonitor.drives, topInset: webTopInset,
                                      reveal: revealInFinder, trash: moveToTrash,
                                      revealFolder: revealInFinder, trashFolder: confirmTrash,
                                      trashOthers: confirmTrash, compare: { comparing = $0 })
                        // Under the toolbar, like a native ScrollView; the page pads its columns clear of it
                        .ignoresSafeArea(edges: .top)
                }
        }
    }

    // MARK: - Data

    private func sorted(_ sets: [FolderSet]) -> [FolderSet] {
        switch sort {
        case .wasted: sets.sorted { $0.wastedBytes > $1.wastedBytes }
        case .name: sets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .copies: sets.sorted { $0.members.count > $1.members.count }
        }
    }

    private func sorted(_ groups: [DuplicateGroup]) -> [DuplicateGroup] {
        switch sort {
        case .wasted: groups.sorted { $0.wastedBytes > $1.wastedBytes }
        case .name: groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .copies: groups.sorted { $0.files.count > $1.files.count }
        }
    }

    private func load() async {
        do {
            var rows = try await DatabaseManager.shared.getDuplicateScanRows()
            if excludeLocal, let mac = driveMonitor.drives.first(where: \.isLocal) {
                rows.removeAll { $0.driveUUID == mac.id }
            }
            let input = rows
            let overview = await Task.detached { DuplicateOverview(rows: input) }.value
            (sets, loose) = (sorted(overview.sets), sorted(overview.loose))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
    }

    // MARK: - Actions

    private func revealInFinder(_ file: DuplicateFile) {
        revealInFinder(FolderLocation(driveUUID: file.driveUUID, driveName: file.driveName, relativePath: file.relativePath))
    }

    private func revealInFinder(_ location: FolderLocation) {
        guard let url = location.url(in: driveMonitor.drives) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

    /// A whole folder goes only after a native confirmation that says what's in it and what isn't elsewhere
    private func confirmTrash(_ member: FolderSet.Member) {
        guard !member.holdsAnother else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Move “\(member.folder.name)” on \(member.folder.driveName) to the Trash?"
        alert.informativeText = "\(member.files.formatted()) files, \(ByteCountFormatter.string(fromByteCount: member.bytes, countStyle: .file)). \(member.verdict)."
        alert.alertStyle = member.isSafeToRemove ? .warning : .critical
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        moveToTrash([member.folder])
    }

    /// Every folder of the set but the kept one, only when each file in them has a copy in the kept one.
    /// The page disables the button in the same case; this is the check that counts
    private func confirmTrash(_ set: FolderSet, keeping keep: Int) {
        let kept = set.members[keep]
        let removed = set.members.indices.filter { $0 != keep }.map { set.members[$0] }
        let connected = Set(driveMonitor.drives.filter(\.isConnected).map(\.id))
        guard removed.allSatisfy({ connected.contains($0.folder.driveUUID) && !$0.holdsAnother && $0.unchecked == 0 && $0.missingFrom[keep] == 0 }) else {
            NSSound.beep()
            return
        }
        let alert = NSAlert()
        alert.messageText = removed.count == 1 ? "Move 1 folder to the Trash?" : "Move \(removed.count) folders to the Trash?"
        alert.informativeText = removed.map { "\($0.folder.driveName): \($0.folder.relativePath), \($0.files.formatted()) files, \(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file))" }
            .joined(separator: "\n") + "\n\nEvery file in \(removed.count == 1 ? "it" : "them") has a copy in \(kept.folder.relativePath) on \(kept.folder.driveName), which stays."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        moveToTrash(removed.map(\.folder))
    }

    private func moveToTrash(driveUUID: String, relativePath: String) {
        moveToTrash([FolderLocation(driveUUID: driveUUID, driveName: "", relativePath: relativePath)])
    }

    /// Trashes files or folders, drops them (and anything inside) from the index, then recomputes the cards once
    private func moveToTrash(_ items: [FolderLocation]) {
        let trashed = items.filter { item in
            guard let drive = driveMonitor.drives.first(where: { $0.id == item.driveUUID }),
                  let driveURL = driveMonitor.getDriveURL(for: drive),
                  (try? FileManager.default.trashItem(at: driveURL.appendingPathComponent(item.relativePath), resultingItemURL: nil)) != nil else {
                NSSound.beep()
                return false
            }
            return true
        }
        // ponytail: drop them from the index now so they don't reappear before FSEvents rescans; if this fails, that rescan catches up
        Task {
            for item in trashed {
                try? await DatabaseManager.shared.deleteFiles(driveUUID: item.driveUUID, relativePaths: [item.relativePath])
            }
            await load()
        }
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(DriveMonitor())
        .frame(width: 900, height: 700)
}
