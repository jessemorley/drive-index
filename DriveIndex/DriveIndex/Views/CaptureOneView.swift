//
//  CaptureOneView.swift
//  DriveIndex
//
//  Capture One files that can be removed without losing anything, one card per session
//

import SwiftUI

/// One thing to remove: an image's mask backups, the old Settings folders of one CaptureOne folder, or an entry in a session's Trash
struct CleanupRow: Identifiable {
    enum Item {
        case masks(MaskBackupSet)
        /// Every old Settings folder in one "CaptureOne" folder
        case settings([OldSettingsFolder])
        case loose(LooseCaptureOneFolder)
        case trash(SessionTrashItem)

        var driveUUID: String {
            switch self {
            case .masks(let set): set.driveUUID
            case .settings(let folders): folders[0].driveUUID
            case .loose(let folder): folder.driveUUID
            case .trash(let entry): entry.driveUUID
            }
        }

        var shootPath: String {
            switch self {
            case .masks(let set): set.shootPath
            case .settings(let folders): folders[0].shootPath
            case .loose(let folder): folder.shootPath
            case .trash(let entry): entry.sessionFolder
            }
        }
    }

    let item: Item
    let session: CaptureOneSession
    /// Old Settings folders the user chose to delete despite their unique files; counts as safe
    var forced = false

    var id: String {
        switch item {
        case .masks(let set): "masks:\(set.id)"
        case .settings(let folders): "settings:\(folders[0].driveUUID)/\(folders[0].captureOnePath)"
        case .loose(let folder): "loose:\(folder.id)"
        case .trash(let entry): "trash:\(entry.id)"
        }
    }

    var tab: CaptureOneTab {
        switch item {
        case .masks: .masks
        case .settings, .loose: .settings
        case .trash: .trash
        }
    }

    var isFolder: Bool {
        switch item {
        case .masks: false
        case .settings, .loose: true
        case .trash(let entry): entry.isDirectory
        }
    }

    var status: CleanupStatus {
        if forced { return .safe }
        return switch item {
        case .masks(let set): set.status
        case .settings(let folders):
            folders.contains { $0.status == .unverified } ? .unverified
                : folders.allSatisfy { $0.status == .safe } ? .safe : .hold
        case .loose(let folder): folder.status
        case .trash(let entry): entry.status
        }
    }

    var name: String {
        switch item {
        case .masks(let set): set.imageName
        // The capture folder; its Settings folders show as chips
        case .settings: location.isEmpty ? String(item.shootPath.split(separator: "/").last ?? "Drive root") : location
        case .loose: "CaptureOne"
        case .trash(let entry): entry.name
        }
    }

    /// The shoot folder within the session ("Capture/BRUNY"); empty when it's the session folder itself
    var location: String {
        let shoot = item.shootPath
        guard shoot.hasPrefix(session.folder) else { return shoot }
        return String(shoot.dropFirst(session.folder.count).drop { $0 == "/" })
    }

    var details: String {
        switch item {
        case .masks: ""  // the chips list the backups
        case .settings: ""
        case .loose: "Not in a session"
        case .trash(let entry): entry.name == "CaptureOne" ? "Settings and previews" : ""
        }
    }

    var size: Int64 {
        switch item {
        case .masks(let set): set.size
        case .settings(let folders): folders.reduce(0) { $0 + ($1.size ?? 0) }
        case .loose(let folder): folder.size ?? 0
        case .trash(let entry): entry.size
        }
    }

    /// nil when unknown (an old Settings folder on a disconnected drive)
    var sizeText: String? {
        if case .settings(let folders) = item, folders.contains(where: { $0.size == nil }) { return nil }
        if case .loose(let folder) = item, folder.size == nil { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var statusText: String {
        switch (status, item) {
        case (.safe, _): "Safe"
        case (.hold, .masks): "Keep: no live mask"
        case (.hold, .trash): "Keep"
        case (.hold, .loose): "Keep: in a session"
        case (.hold, .settings(let folders)):
            folders.orphans == 0 ? "Keep: unreadable" : "\(folders.orphans) unique file\(folders.orphans == 1 ? "" : "s")"
        case (.unverified, _): "Not checked"
        }
    }

    /// Everything in a session's Trash was deleted in Capture One, and on the Settings tab the chips
    /// already say a row is safe or has unique files; a status would only repeat that
    var showsStatus: Bool {
        if tab == .trash || (tab == .settings && status == .safe) { return false }
        if tab == .masks, status != .unverified { return false }
        return !hasUniqueFiles
    }

    /// Old Settings folders with files the kept one lacks; shown as an orange chip
    var hasUniqueFiles: Bool {
        if case .settings(let folders) = item { status == .hold && folders.orphans > 0 } else { false }
    }

    /// What Reveal in Finder selects, relative to the drive
    var paths: [String] {
        switch item {
        case .masks(let set): set.backupPaths
        case .settings(let folders): folders.map(\.path)
        case .loose(let folder): [folder.path]
        case .trash(let entry): [entry.path]
        }
    }
}

private extension [OldSettingsFolder] {
    var orphans: Int { reduce(0) { $0 + $1.orphans } }
}

enum CaptureOneTab: String, CaseIterable {
    case settings = "Settings"
    case masks = "Mask Backups"
    case trash = "Trash"
}

/// One card: a session and its rows on the current tab
struct SessionGroup: Identifiable {
    let session: CaptureOneSession
    let rows: [CleanupRow]
    let safeSize: Int64

    var id: String { session.id }
}

private func formatted(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct CaptureOneView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor

    @AppStorage("captureOne.tab") private var tab: CaptureOneTab = .settings
    @State private var rows: [CleanupRow]?
    /// `rows` on the current tab grouped into cards, most space to free first. Stored, not
    /// computed: regrouping on every redraw made the delete animation stutter.
    @State private var groups: [SessionGroup]?
    @State private var errorMessage: String?
    @State private var expanded: Set<String> = []
    @State private var pendingDelete: [CleanupRow]?
    @State private var deleteFailures = 0
    /// Share of each session's deletion done, by bytes, while it runs
    @State private var deleteProgress: [String: Double] = [:]
    /// Sessions whose Delete button is showing "Deleted" before the card goes
    @State private var flashingDeleted: Set<String> = []
    /// Emptied cards, faded out before they're removed
    @State private var fadedCards: Set<String> = []
    @State private var isDeleting = false
    /// Bytes freed so far, per tab, across launches
    @AppStorage("captureOne.freed.settings") private var freedSettings = 0
    @AppStorage("captureOne.freed.masks") private var freedMasks = 0
    @AppStorage("captureOne.freed.trash") private var freedTrash = 0

    private var connectedDriveIDs: [String] {
        driveMonitor.drives.filter(\.isConnected).map(\.id)
    }

    private var safeRows: [CleanupRow] {
        (groups ?? []).flatMap { $0.rows.filter { $0.status == .safe } }
    }

    var body: some View {
        content
            .navigationTitle("Capture One")
            .navigationSubtitle(safeRows.isEmpty ? "" : "\(formatted(Self.safeSize(safeRows))) safe to remove")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(id: "capture-one-toolbar") {
                ToolbarItem(id: "tab", placement: .principal) {
                    Picker("View", selection: $tab) {
                        ForEach(CaptureOneTab.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(id: "delete-safe", placement: .automatic) {
                    Button("Delete All Safe", systemImage: "trash") { pendingDelete = safeRows }
                        .disabled(safeRows.isEmpty)
                        .help("Delete everything marked Safe on this tab")
                }
                ToolbarItem(id: "refresh", placement: .automatic) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await load() }
                    }
                    .help("Check the drives again")
                }
            }
            // Re-runs when a drive connects or disconnects, so its items get checked
            .task(id: connectedDriveIDs) { await load() }
            .onChange(of: tab) { regroup() }
            .confirmationDialog(deleteTitle, isPresented: isConfirmingDelete, presenting: pendingDelete) { rows in
                Button("Delete", role: .destructive) {
                    Task { await delete(rows) }
                }
            } message: { rows in
                let unique = rows.filter(\.forced).reduce(0) { total, row in
                    if case .settings(let folders) = row.item { total + folders.orphans } else { total }
                }
                if unique > 0 {
                    Text("\(unique) file\(unique == 1 ? " is" : "s are") found nowhere else, so any edits in \(unique == 1 ? "it" : "them") are lost. They're deleted right away and can't be recovered.")
                } else if rows.contains(where: { if case .loose = $0.item { true } else { false } }) {
                    Text("Capture One makes a CaptureOne folder in every folder it browses. These aren't in any session, so they hold only settings and previews from browsing; any edits made there are lost. They're deleted right away and can't be recovered.")
                } else if rows.contains(where: { $0.tab == .trash }) {
                    Text("These are files you deleted in Capture One, waiting in the session's Trash. They're deleted right away and can't be recovered.")
                } else {
                    Text("Everything in them also exists in the newer settings or the live masks. They're deleted right away and can't be recovered.")
                }
            }
            .alert("Some Items Weren't Deleted", isPresented: Binding { deleteFailures > 0 } set: { if !$0 { deleteFailures = 0 } }) {
            } message: {
                Text("\(deleteFailures) item\(deleteFailures == 1 ? "" : "s") stayed in place: the drive was disconnected, a check just before deleting found it was no longer safe, or it couldn't be deleted.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView("Couldn't Load Capture One Files", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if let groups {
            // Session Trash on a disconnected drive can't be emptied, so it waits at the bottom
            let unchecked = { (group: SessionGroup) in tab == .trash && group.rows.allSatisfy { $0.status == .unverified } }
            ScrollView {
                LazyVStack {
                    SpaceSavedCard(settings: freedSettings, masks: freedMasks, trash: freedTrash)
                    if groups.isEmpty {
                        emptyState
                            .padding(.top, 40)
                    }
                    section("Sessions", groups.filter { $0.session.file != nil && !unchecked($0) })
                    section("Not Checked", groups.filter { $0.session.file != nil && unchecked($0) })
                    let folders = groups.filter { $0.session.file == nil }
                    section("Folders", folders, deleteAll: tab == .settings ? folders.flatMap { $0.rows.filter { $0.status == .safe } } : [])
                }
                .padding()
            }
        } else {
            ProgressView("Checking Capture One sessions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch tab {
        case .settings:
            ContentUnavailableView("No Old Settings Folders", systemImage: "folder", description: Text("Settings folders left behind when a newer Capture One opened a session will appear here"))
        case .masks:
            ContentUnavailableView("No Mask Backups", systemImage: "camera.aperture", description: Text("Capture One mask backups on your indexed drives will appear here"))
        case .trash:
            ContentUnavailableView("Session Trash Is Empty", systemImage: "trash", description: Text("Images you delete in Capture One wait in each session's Trash folder; they'll appear here"))
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func section(_ title: String, _ groups: [SessionGroup], deleteAll: [CleanupRow] = []) -> some View {
        if !groups.isEmpty {
            Section {
                ForEach(groups) { card($0) }
            } header: {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    if !deleteAll.isEmpty {
                        Button("Delete All \(formatted(Self.safeSize(deleteAll)))", systemImage: "trash") { pendingDelete = deleteAll }
                            .controlSize(.small)
                            .help("Delete the CaptureOne folders of every folder here that isn't a session")
                    }
                }
                .padding(.top)
            }
        }
    }

    private func card(_ group: SessionGroup) -> some View {
        let drive = driveMonitor.drives.first { $0.id == group.session.driveUUID }
        return SessionCard(
            group: group,
            driveName: drive?.name ?? "Unknown drive",
            connected: drive?.isConnected ?? false,
            isExpanded: expanded.contains(group.id),
            progress: deleteProgress[group.id],
            flashingDeleted: flashingDeleted.contains(group.id),
            toggle: { if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) } },
            open: { group.session.file == nil ? showFolder(group.session) : openSession(group.session) },
            showInFinder: { showFolder(group.session) },
            delete: { pendingDelete = $0 },
            reveal: { revealInFinder($0) }
        )
        .equatable()
        .opacity(fadedCards.contains(group.id) ? 0 : 1)
    }

    // MARK: - Data

    private func load() async {
        do {
            let drives = driveMonitor.drives
            async let masks = MaskBackupSet.load(drives: drives)
            async let settings = OldSettingsFolder.load(drives: drives)
            async let sessionFiles = CaptureOne.sessionFiles()
            let (maskSets, folders, files) = try await (masks, settings, sessionFiles)
            async let trash = SessionTrashItem.load(drives: drives, sessionFiles: files)
            async let loose = LooseCaptureOneFolder.load(drives: drives, sessionFiles: files)
            let (trashEntries, looseFolders) = try await (trash, loose)

            // A loose CaptureOne folder takes its old Settings folders with it, so they aren't listed twice
            let looseIDs = Set(looseFolders.map(\.id))
            let byCaptureOne = Dictionary(grouping: folders) { "\($0.driveUUID)/\($0.captureOnePath)" }
            let items = byCaptureOne.filter { !looseIDs.contains($0.key) }.values.map(CleanupRow.Item.settings)
                + looseFolders.map(CleanupRow.Item.loose)
                + maskSets.map(CleanupRow.Item.masks)
                + trashEntries.map(CleanupRow.Item.trash)

            rows = items.map { item in
                CleanupRow(item: item, session: CaptureOne.session(driveUUID: item.driveUUID, shootPath: item.shootPath, files: files))
            }
            // Settings and masks inside a session's Trash go when the Trash is emptied, so they're only on the Trash tab
            .filter { $0.tab == .trash || !($0.location == "Trash" || $0.location.hasPrefix("Trash/")) }
            regroup()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func regroup() {
        guard let rows else {
            groups = nil
            return
        }
        groups = Dictionary(grouping: rows.filter { $0.tab == tab }, by: \.session)
            .map { SessionGroup(session: $0.key, rows: $0.value.sorted(by: Self.rowOrder), safeSize: Self.safeSize($0.value)) }
            .sorted { $0.safeSize != $1.safeSize ? $0.safeSize > $1.safeSize : $0.session.name.localizedStandardCompare($1.session.name) == .orderedAscending }
    }

    /// Safe first, then by name
    private static func rowOrder(_ a: CleanupRow, _ b: CleanupRow) -> Bool {
        if (a.status == .safe) != (b.status == .safe) { return a.status == .safe }
        return "\(a.location)/\(a.name)".localizedStandardCompare("\(b.location)/\(b.name)") == .orderedAscending
    }

    static func safeSize(_ rows: [CleanupRow]) -> Int64 {
        rows.filter { $0.status == .safe }.reduce(0) { $0 + $1.size }
    }

    // MARK: - Delete

    private var isConfirmingDelete: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
    }

    private var deleteTitle: String {
        let rows = pendingDelete ?? []
        return "Delete \(rows.count) item\(rows.count == 1 ? "" : "s") (\(formatted(Self.safeSize(rows))))?"
    }

    /// Deletes session by session in card order. Each card's button fills as its items go, then
    /// shows "Deleted"; the cards all leave together once every session is done, so the list
    /// doesn't shuffle while small sessions finish in quick succession.
    private func delete(_ rows: [CleanupRow]) async {
        // One deletion at a time; the buttons stay live rather than greying out
        guard !isDeleting else { return }
        isDeleting = true

        let order = (groups ?? []).map(\.id)
        let bySession = Dictionary(grouping: rows, by: \.session.id)
        let sessionIDs = bySession.keys.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        for id in sessionIDs { deleteProgress[id] = 0 }

        var failed = 0
        var deleted: Set<String> = []
        var finishing: [Task<Void, Never>] = []
        for id in sessionIDs {
            let sessionRows = bySession[id]!
            let total = max(Self.safeSize(sessionRows), 1)
            var done: Int64 = 0
            var sessionFailed = false
            for row in sessionRows {
                if await deleteRow(row) {
                    deleted.insert(row.id)
                    addFreed(row)
                } else {
                    failed += 1
                    sessionFailed = true
                }
                done += row.size
                withAnimation(.easeInOut(duration: 0.4)) {
                    deleteProgress[id] = Double(done) / Double(total)
                }
            }
            if !sessionFailed {
                finishing.append(Task { await showDeleted(id) })
            }
        }

        for task in finishing { await task.value }
        // Hold the last "Deleted" a moment, then everything that went leaves at once
        try? await Task.sleep(for: .milliseconds(700))
        // Fade the emptied cards out first, then close the gap, so the cards below don't slide under a fading one
        let emptied = Set((groups ?? []).filter { $0.rows.allSatisfy { deleted.contains($0.id) } }.map(\.id))
        withAnimation(.easeOut(duration: 0.25)) { fadedCards = emptied }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.25)) {
            // Drop what went rather than rescanning every drive
            // Anything inside a deleted folder (mask backups in a Settings folder, say) went with it
            let deletedFolders = rows.filter { $0.isFolder && deleted.contains($0.id) }.flatMap { row in row.paths.map { "\(row.item.driveUUID)/\($0)/" } }
            self.rows?.removeAll { row in
                deleted.contains(row.id) || row.paths.contains { path in deletedFolders.contains { "\(row.item.driveUUID)/\(path)".hasPrefix($0) } }
            }
            regroup()
        } completion: {
            // Only now: clearing during the fade would flip "Deleted" back to "Delete…"
            deleteProgress = [:]
            flashingDeleted = []
            fadedCards = []
        }
        isDeleting = false
        deleteFailures = failed
    }

    /// Counts a fully deleted row towards its tab's total. Sizes are what was listed: measured on
    /// disk for Settings folders and session Trash, from the index for mask backups.
    private func addFreed(_ row: CleanupRow) {
        let bytes = Int(row.size)
        switch row.tab {
        case .settings: freedSettings += bytes
        case .masks: freedMasks += bytes
        case .trash: freedTrash += bytes
        }
    }

    /// Lets the fill reach the end, then turns the button to "Deleted". Only for sessions where
    /// every item went; a partial one keeps its fill and stays listed with what's left.
    private func showDeleted(_ sessionID: String) async {
        try? await Task.sleep(for: .milliseconds(450))
        flashingDeleted.insert(sessionID)
    }

    /// Deletes one row's files after the on-disk checks; true when all of them went
    private func deleteRow(_ row: CleanupRow) async -> Bool {
        guard let driveURL = driveURL(row.item.driveUUID) else { return false }
        var removed: [String] = []
        var complete = false
        switch row.item {
        case .masks(let set):
            let result = await set.delete(on: driveURL)
            removed = result.deleted
            complete = result.failed.isEmpty
        case .settings(let folders):
            for folder in folders where await folder.delete(on: driveURL, force: row.forced) {
                removed.append(folder.path)
            }
            complete = removed.count == folders.count
        case .loose(let folder):
            complete = await folder.delete(on: driveURL)
            if complete { removed = [folder.path] }
        case .trash(let entry):
            complete = await entry.delete(on: driveURL)
            if complete { removed = [entry.path] }
        }
        // ponytail: drop them from the index now so they don't reappear before FSEvents rescans; if this fails, that rescan catches up
        try? await DatabaseManager.shared.deleteFiles(driveUUID: row.item.driveUUID, relativePaths: removed)
        return complete
    }

    // MARK: - Actions

    private func driveURL(_ uuid: String) -> URL? {
        driveMonitor.drives.first { $0.id == uuid }.flatMap { driveMonitor.getDriveURL(for: $0) }
    }

    private func revealInFinder(_ row: CleanupRow) {
        guard let driveURL = driveURL(row.item.driveUUID) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(row.paths.map { driveURL.appendingPathComponent($0) })
    }

    private func openSession(_ session: CaptureOneSession) {
        guard let file = session.file, let driveURL = driveURL(session.driveUUID),
              NSWorkspace.shared.open(driveURL.appendingPathComponent(file)) else {
            NSSound.beep()
            return
        }
    }

    private func showFolder(_ session: CaptureOneSession) {
        guard let driveURL = driveURL(session.driveUUID) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([driveURL.appendingPathComponent(session.folder)])
    }
}

/// A session's card. Equatable on what it shows (not its actions), so while one session is
/// being deleted only that card redraws.
private struct SessionCard: View, Equatable {
    let group: SessionGroup
    let driveName: String
    let connected: Bool
    let isExpanded: Bool
    let progress: Double?
    let flashingDeleted: Bool
    let toggle: () -> Void
    let open: () -> Void
    let showInFinder: () -> Void
    let delete: ([CleanupRow]) -> Void
    let reveal: (CleanupRow) -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.group.id == b.group.id && a.group.rows.map(\.id) == b.group.rows.map(\.id)
            && a.group.rows.map(\.status) == b.group.rows.map(\.status) && a.group.safeSize == b.group.safeSize
            && a.driveName == b.driveName && a.connected == b.connected
            && a.isExpanded == b.isExpanded && a.progress == b.progress && a.flashingDeleted == b.flashingDeleted
    }

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: Binding { isExpanded } set: { _ in toggle() }) {
                // DisclosureGroup adds no gap under the label, so the first divider hits the header
                VStack {
                    ForEach(group.rows) { row in
                        Divider()
                        itemRow(row)
                            // ponytail: measured, lines child icons up with the session icon past the chevron; adjust if the disclosure chevron changes
                            .padding(.leading, 17)
                    }
                }
                .padding(.top, 6)
            } label: {
                header
                    .contentShape(Rectangle())
                    // macOS only toggles from the chevron; let the whole header do it
                    .onTapGesture { toggle() }
                    .contextMenu { headerMenu }
                    .padding(.leading, 4)
            }
            // GroupBox's inset puts the chevron tight against the card edge
            .padding(4)
        }
    }

    private var header: some View {
        let session = group.session
        let safe = group.rows.filter { $0.status == .safe }
        return HStack {
            Label {
                Text(session.name)
            } icon: {
                Image(nsImage: NSWorkspace.shared.listIcon(name: session.file ?? session.name, isDirectory: session.file == nil))
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Button(session.file == nil ? "Show Folder" : "Open Session", action: open)
                .controlSize(.small)
                .disabled(!connected)
                .help(session.file == nil ? "Show this folder in Finder" : "Open this session in Capture One")
            Text(driveName)
                .foregroundStyle(connected ? .secondary : .tertiary)
            Spacer()
            if !safe.isEmpty {
                let title = "Delete \(formatted(group.safeSize))"
                Button(title, systemImage: "trash") { delete(safe) }
                    .controlSize(.small)
                    .overlay {
                        if flashingDeleted {
                            DeleteProgressFill(title: "Deleted", systemImage: "checkmark", progress: 1)
                        } else {
                            DeleteProgressFill(title: title, systemImage: "trash", progress: progress)
                        }
                    }
                    // Some of what's left here holds files found nowhere else
                    .foregroundStyle(group.rows.contains(where: \.hasUniqueFiles) ? .orange : .primary)
                    .help("Delete this session's safe items")
            } else if !connected {
                Text("Connect \(driveName)")
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing safe to remove")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var headerMenu: some View {
        let safe = group.rows.filter { $0.status == .safe }
        if group.session.file != nil {
            Button("Open Session", action: open)
                .disabled(!connected)
        }
        Button("Show in Finder", action: showInFinder)
            .disabled(!connected)
        Divider()
        Button("Delete Safe Items") { delete(safe) }
            .disabled(safe.isEmpty)
        // For when the unique files don't matter: every old Settings folder, held ones too
        let held = group.rows.contains { if case .settings = $0.item { $0.status == .hold } else { false } }
        if held {
            Button("Delete All Old Settings…") {
                delete(group.rows.compactMap { row in
                    guard case .settings = row.item, row.status != .unverified else { return nil }
                    var row = row
                    row.forced = true
                    return row
                })
            }
        }
    }

    /// "1 unique file in Settings1670: IMG_0914.HEIC.cos"
    private static func uniqueFilesHelp(_ folders: [OldSettingsFolder]) -> String {
        folders.filter { $0.orphans > 0 }.map { folder in
            let names = folder.uniqueFiles.prefix(10).joined(separator: ", ")
            let more = folder.orphans > 10 ? " and \(folder.orphans - 10) more" : ""
            return "\(folder.orphans) unique file\(folder.orphans == 1 ? "" : "s") in \(folder.name): \(names)\(more)"
        }.joined(separator: "\n")
    }

    private func itemRow(_ row: CleanupRow) -> some View {
        HStack {
            Label {
                Text(row.name)
            } icon: {
                Image(nsImage: NSWorkspace.shared.listIcon(name: row.name, isDirectory: row.isFolder))
            }
            .lineLimit(1)
            .truncationMode(.middle)
            if case .settings(let folders) = row.item {
                // Oldest first; the kept one green, or orange when it lacks files an old one has
                let missing = row.hasUniqueFiles
                ForEach(Set(folders.map(\.name) + folders[0].kept).sorted { OldSettingsFolder.version(of: $0)!.lexicographicallyPrecedes(OldSettingsFolder.version(of: $1)!) }, id: \.self) { name in
                    let kept = folders[0].kept.contains(name)
                    StatusChip(title: name, color: kept ? (missing ? .orange : .green) : nil)
                        .help(kept && missing ? Self.uniqueFilesHelp(folders) : "")
                }
            } else if case .masks(let set) = row.item {
                Text(row.location)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Green while the live mask is there, orange when it's missing
                StatusChip(title: "\(set.backupPaths.count) backup\(set.backupPaths.count == 1 ? "" : "s")",
                           color: row.status == .safe ? .green : row.status == .hold ? .orange : nil)
                    .help(row.status == .hold ? "Original mask file missing" : "")
            } else {
                Text(row.location)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(row.details)
                .foregroundStyle(.secondary)
            if row.showsStatus {
                Label(row.statusText, systemImage: row.status.symbol)
                    .foregroundStyle(row.status.color)
            }
            if let size = row.sizeText {
                Text(size)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { reveal(row) }
        .contextMenu {
            Button("Reveal in Finder") { reveal(row) }
                .disabled(row.status == .unverified)
        }
    }
}

/// Space freed by deleting from each tab, kept across launches; the same card tops every tab
private struct SpaceSavedCard: View {
    let settings: Int
    let masks: Int
    let trash: Int

    var body: some View {
        GroupBox {
            HStack(spacing: 32) {
                stat("Space Saved", settings + masks + trash)
                Divider()
                stat("Settings", settings)
                stat(CaptureOneTab.masks.rawValue, masks)
                stat(CaptureOneTab.trash.rawValue, trash)
                Spacer()
            }
            // A vertical Divider takes all the height it's offered; keep the card to its content
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
        }
        .padding(.bottom, 12)
    }

    private func stat(_ label: String, _ bytes: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(formatted(Int64(bytes)))
                .font(.title2)
                .contentTransition(.numericText())
        }
    }
}

/// Red fill sweeping across a Delete button while its session is deleted. The button's own
/// label is repeated in white over the red so it stays legible; nothing in macOS draws a
/// progress fill inside a button.
private struct DeleteProgressFill: View {
    let title: String
    let systemImage: String
    let progress: Double?

    var body: some View {
        if let progress {
            GeometryReader { geometry in
                ZStack {
                    Color.red
                    Label(title, systemImage: systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: geometry.size.width * progress)
                }
            }
            // ponytail: measured, the corner of a small bordered button on macOS 27; adjust if the system shape changes
            .clipShape(.rect(cornerRadius: 5))
            .allowsHitTesting(false)
        }
    }
}

extension CleanupStatus {
    var symbol: String {
        switch self {
        case .safe: return "checkmark.circle.fill"
        case .hold: return "exclamationmark.triangle.fill"
        case .unverified: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .safe: return .green
        case .hold: return .orange
        case .unverified: return .secondary
        }
    }
}

#Preview {
    CaptureOneView()
        .environmentObject(DriveMonitor())
        .frame(width: 900, height: 700)
}

#Preview("Space saved") {
    SpaceSavedCard(settings: 63_078_400, masks: 1_642_137_000, trash: 2_830_000_000)
        .padding()
        .frame(width: 800)
}
