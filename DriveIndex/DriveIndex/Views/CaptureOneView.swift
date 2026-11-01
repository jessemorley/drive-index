//
//  CaptureOneView.swift
//  DriveIndex
//
//  Capture One files that can be removed without losing anything: a list of sessions, then the selected one's review
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
    case settings = "Settings Files"
    case masks = "Mask Backups"
    case trash = "Trashes"
}

/// A row of the review's Actions section
private enum ActionNote: Identifiable {
    case safe
    case held(CleanupRow)
    case unchecked(Int)
    case offline

    var id: String {
        switch self {
        case .safe: "safe"
        case .held(let row): row.id
        case .unchecked: "unchecked"
        case .offline: "offline"
        }
    }
}

/// A session and everything in it to clean up
struct SessionGroup: Identifiable {
    let session: CaptureOneSession
    let rows: [CleanupRow]
    let safeSize: Int64

    var id: String { session.id }
    var safe: [CleanupRow] { rows.filter { $0.status == .safe } }
}

private func formatted(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// The whole window while Capture One is selected: the app's sidebar, the sessions with something
/// to clean up, and the selected one's review: its old Settings, mask backups and Trash together. Three native columns, as Duplicates
struct CaptureOneView<Sidebar: View>: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @ViewBuilder let sidebar: Sidebar

    @State private var rows: [CleanupRow]?
    /// `rows` grouped by session, most space to free first
    @State private var groups: [SessionGroup]?
    @State private var errorMessage: String?
    @State private var selection: String?
    /// Counts loads, so each one gives the review a new Form
    @State private var loads = 0
    @State private var pendingDelete: [CleanupRow]?
    @State private var deleteFailures = 0
    /// Bytes deleted of the most expected, while a deletion runs
    @State private var deleting: (done: Int64, total: Int64)?
    /// Bytes freed so far, per tab, across launches
    @AppStorage("captureOne.freed.settings") private var freedSettings = 0
    @AppStorage("captureOne.freed.masks") private var freedMasks = 0
    @AppStorage("captureOne.freed.trash") private var freedTrash = 0

    private var connectedDriveIDs: [String] {
        driveMonitor.drives.filter(\.isConnected).map(\.id)
    }

    private var safeRows: [CleanupRow] {
        (groups ?? []).flatMap(\.safe)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            Group {
                if let groups, errorMessage == nil, !groups.isEmpty { list } else { Color.clear }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 440)
            .navigationTitle("Capture One")
        } detail: {
            content
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .indexingStatusBar(indexManager)
                .toolbar(id: "capture-one-toolbar") {
                    // Detail-column items start at the column's leading edge otherwise
                    ToolbarSpacer(.flexible)
                    ToolbarItem(id: "delete-safe", placement: .automatic) {
                        Button("Delete All Safe", systemImage: "trash") { pendingDelete = safeRows }
                            .disabled(safeRows.isEmpty || deleting != nil)
                            .help("Delete everything marked Safe in every session")
                    }
                    ToolbarItem(id: "refresh", placement: .automatic) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await load() }
                        }
                        .help("Check the drives again")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        // Re-runs when a drive connects or disconnects, so its items get checked
        .task(id: connectedDriveIDs) { await load() }
        // Every scan, FSEvents ones too, so something just moved to a session's Trash shows up
        .onChange(of: indexManager.isIndexing) { _, indexing in
            if !indexing { Task { await load() } }
        }
        .confirmationDialog(deleteTitle, isPresented: isConfirmingDelete, presenting: pendingDelete) { rows in
            Button("Delete", role: .destructive) {
                Task { await delete(rows) }
            }
        } message: { rows in
            let unique = rows.filter(\.forced).reduce(0) { total, row in
                if case .settings(let folders) = row.item { total + folders.orphans } else { total }
            }
            // One sentence for each kind in the deletion, which can mix them now
            let isLoose = { (row: CleanupRow) in if case .loose = row.item { true } else { false } }
            let reasons = [
                (unique > 0, "\(unique) file\(unique == 1 ? " is" : "s are") found nowhere else, so any edits in \(unique == 1 ? "it" : "them") are lost."),
                (rows.contains { !$0.forced && $0.tab != .trash && !isLoose($0) },
                 "The old settings and mask backups also exist in the newer settings or the live masks."),
                (rows.contains(where: isLoose), "Capture One makes a CaptureOne folder in every folder it browses. Those outside a session hold only settings and previews from browsing; any edits made there are lost."),
                (rows.contains { $0.tab == .trash }, "Files from a session's Trash were deleted in Capture One."),
            ]
            Text((reasons.filter(\.0).map(\.1) + ["They're deleted right away and can't be recovered."]).joined(separator: " "))
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
            if groups.isEmpty {
                emptyState
            } else if let group = groups.first(where: { $0.id == selection }) {
                review(group)
            } else {
                ContentUnavailableView("No Selection", systemImage: "camera.aperture")
            }
        } else {
            ProgressView("Checking Capture One sessions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView("Nothing to Clean Up", systemImage: "camera.aperture",
                               description: Text("Old Settings folders, mask backups and files in a session's Trash on your indexed drives will appear here"))
    }

    // MARK: - List

    /// Sessions on a disconnected drive can't be cleaned up, so they wait below the others
    private var sections: [(title: String, groups: [SessionGroup])] {
        let groups = groups ?? []
        let unchecked = { (group: SessionGroup) in group.rows.allSatisfy { $0.status == .unverified } }
        return [("Sessions", groups.filter { $0.session.file != nil && !unchecked($0) }),
                ("Not Checked", groups.filter { $0.session.file != nil && unchecked($0) }),
                ("Folders", groups.filter { $0.session.file == nil })]
            .filter { !$0.groups.isEmpty }
    }

    private var order: [String] { sections.flatMap { $0.groups.map(\.id) } }

    private var list: some View {
        List(selection: $selection) {
            ForEach(sections, id: \.title) { section in
                Section {
                    header(section.title, section.groups.count.formatted(),
                           deleteAll: section.title == "Folders" ? section.groups.flatMap(\.safe).filter { $0.tab == .settings } : [])
                    ForEach(section.groups) { row($0).tag($0.id) }
                }
            }
        }
    }

    /// A row, not a section header: section headers pin under the toolbar
    private func header(_ title: String, _ count: String, deleteAll: [CleanupRow]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Text(count).foregroundStyle(.secondary)
            Spacer()
            if !deleteAll.isEmpty {
                Button("Delete All \(formatted(Self.safeSize(deleteAll)))") { pendingDelete = deleteAll }
                    .controlSize(.small)
                    .disabled(deleting != nil)
                    .help("Delete the CaptureOne folders of every folder here that isn't a session")
            }
        }
        .padding(.top, 8)
        .selectionDisabled()
    }

    private func row(_ group: SessionGroup) -> some View {
        let session = group.session
        return HStack {
            Image(nsImage: NSWorkspace.shared.listIcon(name: session.file ?? session.name, isDirectory: session.file == nil))
            Text(session.name).lineLimit(1).truncationMode(.middle)
            StatusChip(title: group.rows.count.formatted(), color: nil)
                .help("\(group.rows.count) item\(group.rows.count == 1 ? "" : "s")")
            Spacer()
            if group.safeSize > 0 {
                Text(formatted(group.safeSize)).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isConnected(session.driveUUID) ? .primary : .secondary)
        .padding(.vertical, 8)
    }

    /// Under the list: the deletion's progress while it runs, else the space freed so far
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                if let deleting {
                    ProgressView().controlSize(.small)
                    Text("Deleting…")
                    ProgressView(value: Double(deleting.done), total: Double(max(deleting.total, 1)))
                } else {
                    Text("\(formatted(Int64(freedSettings + freedMasks + freedTrash))) saved")
                        .contentTransition(.numericText())
                        .help("Settings \(formatted(Int64(freedSettings))), \(CaptureOneTab.masks.rawValue) \(formatted(Int64(freedMasks))), \(CaptureOneTab.trash.rawValue) \(formatted(Int64(freedTrash)))")
                    Spacer()
                }
            }
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func skip() {
        guard let selection, let i = order.firstIndex(of: selection) else { return }
        self.selection = order[(i + 1) % order.count]
    }

    // MARK: - Review

    private func isConnected(_ driveUUID: String) -> Bool {
        driveMonitor.drives.first { $0.id == driveUUID }?.isConnected ?? false
    }

    private func review(_ group: SessionGroup) -> some View {
        let session = group.session
        let driveName = driveMonitor.drives.first { $0.id == session.driveUUID }?.name ?? "Unknown drive"
        let connected = isConnected(session.driveUUID)
        let safe = group.safe
        let unchecked = group.rows.filter { $0.status == .unverified }
        let held = group.rows.filter { $0.status == .hold }

        let kinds = CaptureOneTab.allCases.filter { kind in group.rows.contains { $0.tab == kind } }

        return Form {
            // Only the kinds present: an empty `if` section left in the Form mis-laid it (rows lost their card, the
            // buttons gained one; in a preview, SwiftUI's table diff crashed)
            ForEach(kinds, id: \.self) { kindSection($0, of: group, driveName: driveName, first: kinds.first) }

            Section {
                // One ForEach, no `if` rows: an empty one mis-lays the Form when it updates in place
                let notes: [ActionNote] = (!safe.isEmpty && held.isEmpty && unchecked.isEmpty ? [.safe] : [])
                    + held.map(ActionNote.held) + (unchecked.isEmpty ? [] : [.unchecked(unchecked.count)])
                    + (connected ? [] : [.offline])
                ForEach(notes) { note in
                    switch note {
                    case .safe:
                        Label {
                            Text("Safe to delete: " + kinds.map(Self.safeReason).joined(separator: "; "))
                        } icon: {
                            Image(systemName: "checkmark.circle").foregroundStyle(.green)
                        }
                    case .held(let row):
                        heldRow(row, connected: connected)
                    case .unchecked(let count):
                        Label("\(count) item\(count == 1 ? "" : "s") not checked", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    case .offline:
                        Label("\(driveName) is offline. Connect it to check and delete these items.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(session.file == nil ? "Show Folder" : "Open Session") {
                        session.file == nil ? showFolder(session) : openSession(session)
                    }
                    .disabled(!connected)
                    .help(session.file == nil ? "Show this folder in Finder" : "Open this session in Capture One")
                    Spacer()
                    Button("Skip") { skip() }
                    // For when the unique files don't matter: every old Settings folder, held ones too
                    if held.contains(where: { if case .settings = $0.item { true } else { false } }) {
                        Button("Delete All Old Settings…") {
                            pendingDelete = group.rows.compactMap { row in
                                guard case .settings = row.item, row.status != .unverified else { return nil }
                                var row = row
                                row.forced = true
                                return row
                            }
                        }
                        .disabled(deleting != nil)
                    }
                    Button("Delete \(safe.count) Safe Item\(safe.count == 1 ? "" : "s")") { pendingDelete = safe }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(safe.isEmpty || deleting != nil)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Actions")
                    .padding(.bottom, 6)
            }
        }
        .formStyle(.grouped)
        // A new Form for each session and each load, as Duplicates does for a new set: updated in place, the
        // Form mis-laid its rows when sections came and went
        .id("\(group.id)#\(loads)")
    }

    /// An item kept back, and why
    private func heldRow(_ row: CleanupRow, connected: Bool) -> some View {
        HStack {
            Image(systemName: "circle.fill").font(.caption2).foregroundStyle(row.status.color)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(row.name): \(row.statusText)")
                if case .settings(let folders) = row.item, row.hasUniqueFiles {
                    Text(folders.uniqueFilesSummary)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer()
            Button("Reveal in Finder") { revealInFinder(row) }
                .controlSize(.small)
                .disabled(!connected)
        }
        .padding(.vertical, 4)
    }

    /// One kind of item in the review; the first one also carries the session's title
    private func kindSection(_ kind: CaptureOneTab, of group: SessionGroup, driveName: String, first: CaptureOneTab?) -> some View {
        let rows = group.rows.filter { $0.tab == kind }
        let safe = rows.filter { $0.status == .safe }
        return Section {
            ForEach(rows) { itemRow($0) }
        } header: {
            // One view, not an `if` and a Text: a conditional header landed inside the card
            VStack(alignment: .leading, spacing: 0) {
                if kind == first {
                    // Atop the review: a three-column window titles the middle column, not this one
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.session.name).font(.title2.bold())
                        Text("\(driveName) · \(group.rows.count) item\(group.rows.count == 1 ? "" : "s")\(group.safeSize > 0 ? " · \(formatted(group.safeSize)) safe to remove" : "")")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 28)
                }
                // A header with more than one view turns grey and small; this matches the plain "Actions" one
                HStack(alignment: .firstTextBaseline) {
                    Text(kind.rawValue).font(.headline)
                    Spacer()
                    Button(safe.isEmpty ? "Delete" : "Delete \(formatted(Self.safeSize(safe)))", systemImage: "trash") { pendingDelete = safe }
                        .disabled(safe.isEmpty || deleting != nil)
                        .help("Delete the safe items in this section")
                }
                .padding(.bottom, 6)
            }
            .foregroundStyle(.primary)
            .textCase(nil)
        }
    }

    private static func safeReason(_ tab: CaptureOneTab) -> String {
        switch tab {
        case .settings: "the old settings are in the newer ones, or are only settings and previews from browsing"
        case .masks: "every image still has its live mask"
        case .trash: "the Trash holds what was deleted in Capture One"
        }
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
                        .help(kept && missing ? folders.uniqueFilesSummary : "")
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
        .onTapGesture(count: 2) { revealInFinder(row) }
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(row) }
                .disabled(row.status == .unverified)
        }
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
            // Settings and masks inside a session's Trash go when the Trash is emptied, so they're only listed under Trashes
            .filter { $0.tab == .trash || !($0.location == "Trash" || $0.location.hasPrefix("Trash/")) }
            regroup()
            loads += 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Regroups `rows` by session. A selection that's gone hands over to whatever took its place in the list
    private func regroup() {
        guard let rows else {
            groups = nil
            return
        }
        let before = order
        groups = Dictionary(grouping: rows, by: \.session)
            .map { SessionGroup(session: $0.key, rows: $0.value.sorted(by: Self.rowOrder), safeSize: Self.safeSize($0.value)) }
            .sorted { $0.safeSize != $1.safeSize ? $0.safeSize > $1.safeSize : $0.session.name.localizedStandardCompare($1.session.name) == .orderedAscending }
        let now = order
        if selection == nil || !now.contains(selection!) {
            let i = selection.flatMap { before.firstIndex(of: $0) } ?? 0
            selection = now.isEmpty ? nil : now[min(i, now.count - 1)]
        }
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

    /// Deletes row by row, the list footer filling as they go, then drops what went from the list at once
    private func delete(_ rows: [CleanupRow]) async {
        // One deletion at a time
        guard deleting == nil else { return }
        deleting = (0, max(Self.safeSize(rows), 1))

        var failed = 0
        var deleted: Set<String> = []
        for row in rows {
            if await deleteRow(row) {
                deleted.insert(row.id)
                addFreed(row)
            } else {
                failed += 1
            }
            withAnimation { deleting?.done += row.size }
        }

        withAnimation {
            // Drop what went rather than rescanning every drive
            // Anything inside a deleted folder (mask backups in a Settings folder, say) went with it
            let deletedFolders = rows.filter { $0.isFolder && deleted.contains($0.id) }.flatMap { row in row.paths.map { "\(row.item.driveUUID)/\($0)/" } }
            self.rows?.removeAll { row in
                deleted.contains(row.id) || row.paths.contains { path in deletedFolders.contains { "\(row.item.driveUUID)/\(path)".hasPrefix($0) } }
            }
            regroup()
        }
        deleting = nil
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

private extension [OldSettingsFolder] {
    /// "1 unique file in Settings1670: IMG_0914.HEIC.cos"
    var uniqueFilesSummary: String {
        filter { $0.orphans > 0 }.map { folder in
            let names = folder.uniqueFiles.prefix(10).joined(separator: ", ")
            let more = folder.orphans > 10 ? " and \(folder.orphans - 10) more" : ""
            return "\(folder.orphans) unique file\(folder.orphans == 1 ? "" : "s") in \(folder.name): \(names)\(more)"
        }.joined(separator: "\n")
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
    CaptureOneView(columnVisibility: .constant(.all)) { Text("Sidebar") }
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 1100, height: 700)
}
