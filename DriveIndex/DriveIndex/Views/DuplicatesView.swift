//
//  DuplicatesView.swift
//  DriveIndex
//
//  Duplicates by folder: a card per set of folders holding copies of each other's files, with a
//  verdict per folder, then a card per duplicate file with a copy outside every set
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
                                      compare: { comparing = $0 })
                        // Under the toolbar, like a native ScrollView; the web view keeps content clear of it
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
        moveToTrash(driveUUID: member.folder.driveUUID, relativePath: member.folder.relativePath)
    }

    /// Trashes a file or folder, drops it (and anything inside it) from the index, then recomputes the cards
    private func moveToTrash(driveUUID: String, relativePath: String) {
        guard let drive = driveMonitor.drives.first(where: { $0.id == driveUUID }),
              let driveURL = driveMonitor.getDriveURL(for: drive),
              (try? FileManager.default.trashItem(at: driveURL.appendingPathComponent(relativePath), resultingItemURL: nil)) != nil else {
            NSSound.beep()
            return
        }
        // ponytail: drop it from the index now so it doesn't reappear before FSEvents rescans; if this fails, that rescan catches up
        Task {
            try? await DatabaseManager.shared.deleteFiles(driveUUID: driveUUID, relativePaths: [relativePath])
            await load()
        }
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(DriveMonitor())
        .frame(width: 900, height: 700)
}
