//
//  CaptureOneView.swift
//  DriveIndex
//
//  Capture One files that can be removed without losing anything, one card per session
//

import SwiftUI

/// One thing to remove: an image's mask backups, or an old Settings folder
struct CleanupRow: Identifiable {
    enum Item {
        case masks(MaskBackupSet)
        case settings(OldSettingsFolder)

        var driveUUID: String {
            switch self {
            case .masks(let set): set.driveUUID
            case .settings(let folder): folder.driveUUID
            }
        }

        var shootPath: String {
            switch self {
            case .masks(let set): set.shootPath
            case .settings(let folder): folder.shootPath
            }
        }
    }

    let item: Item
    let session: CaptureOneSession

    var id: String {
        switch item {
        case .masks(let set): "masks:\(set.id)"
        case .settings(let folder): "settings:\(folder.id)"
        }
    }

    var tab: CaptureOneTab {
        if case .settings = item { return .settings }
        return .masks
    }

    var status: CleanupStatus {
        switch item {
        case .masks(let set): set.status
        case .settings(let folder): folder.status
        }
    }

    var name: String {
        switch item {
        case .masks(let set): set.imageName
        case .settings(let folder): folder.name
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
        case .masks(let set): "\(set.backupPaths.count) backup\(set.backupPaths.count == 1 ? "" : "s")"
        case .settings(let folder): "Replaced by \(folder.kept.joined(separator: " and "))"
        }
    }

    var size: Int64 {
        switch item {
        case .masks(let set): set.size
        case .settings(let folder): folder.size ?? 0
        }
    }

    /// nil when unknown (an old Settings folder on a disconnected drive)
    var sizeText: String? {
        if case .settings(let folder) = item, folder.size == nil { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var statusText: String {
        switch (status, item) {
        case (.safe, _): "Safe"
        case (.hold, .masks): "Keep: no live mask"
        case (.hold, .settings(let folder)): folder.orphans == 0 ? "Keep: unreadable" : "\(folder.orphans) unique file\(folder.orphans == 1 ? "" : "s")"
        case (.unverified, _): "Not checked"
        }
    }

    /// What Reveal in Finder selects, relative to the drive
    var paths: [String] {
        switch item {
        case .masks(let set): set.backupPaths
        case .settings(let folder): [folder.path]
        }
    }
}

enum CaptureOneTab: String, CaseIterable {
    case settings = "Settings"
    case masks = "Mask Backups"
}

struct CaptureOneView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor

    @AppStorage("captureOne.tab") private var tab: CaptureOneTab = .settings
    @State private var rows: [CleanupRow]?
    @State private var errorMessage: String?
    @State private var expanded: Set<String> = []
    @State private var pendingTrash: [CleanupRow]?
    @State private var trashFailures = 0

    private var connectedDriveIDs: [String] {
        driveMonitor.drives.filter(\.isConnected).map(\.id)
    }

    /// The current tab's rows, one card per session, most space to free first
    private var sessions: [(session: CaptureOneSession, rows: [CleanupRow])]? {
        guard let rows else { return nil }
        return Dictionary(grouping: rows.filter { $0.tab == tab }, by: \.session)
            .map { (session: $0.key, rows: $0.value.sorted(by: rowOrder)) }
            .sorted { safeSize($0.rows) != safeSize($1.rows) ? safeSize($0.rows) > safeSize($1.rows) : $0.session.name.localizedStandardCompare($1.session.name) == .orderedAscending }
    }

    private var safeRows: [CleanupRow] {
        (sessions ?? []).flatMap(\.rows).filter { $0.status == .safe }
    }

    var body: some View {
        content
            .navigationTitle("Capture One")
            .navigationSubtitle(safeRows.isEmpty ? "" : "\(formatted(safeSize(safeRows))) safe to remove")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(id: "capture-one-toolbar") {
                ToolbarItem(id: "tab", placement: .principal) {
                    Picker("View", selection: $tab) {
                        ForEach(CaptureOneTab.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                ToolbarItem(id: "trash-safe", placement: .automatic) {
                    Button("Move All Safe to Trash", systemImage: "trash") { pendingTrash = safeRows }
                        .disabled(safeRows.isEmpty)
                        .help("Move everything marked Safe on this tab to the Trash")
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
            .confirmationDialog(trashTitle, isPresented: isConfirmingTrash, presenting: pendingTrash) { rows in
                Button("Move to Trash", role: .destructive) {
                    Task { await trash(rows) }
                }
            } message: { _ in
                Text("Everything in them also exists in the newer settings or the live masks. They go to the Trash on their drive and are deleted when you empty it.")
            }
            .alert("Some Items Weren't Moved", isPresented: Binding { trashFailures > 0 } set: { if !$0 { trashFailures = 0 } }) {
            } message: {
                Text("\(trashFailures) item\(trashFailures == 1 ? "" : "s") stayed in place: the drive was disconnected, a check just before moving found it was no longer safe, or the Finder couldn't move it.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView("Couldn't Load Capture One Files", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if let sessions, sessions.isEmpty {
            switch tab {
            case .settings:
                ContentUnavailableView("No Old Settings Folders", systemImage: "folder", description: Text("Settings folders left behind when a newer Capture One opened a session will appear here"))
            case .masks:
                ContentUnavailableView("No Mask Backups", systemImage: "camera.aperture", description: Text("Capture One mask backups on your indexed drives will appear here"))
            }
        } else if let sessions {
            let loose = sessions.filter { $0.session.file == nil }
            ScrollView {
                LazyVStack {
                    ForEach(sessions.filter { $0.session.file != nil }, id: \.session.id) { session in
                        card(session.session, rows: session.rows)
                    }
                    if !loose.isEmpty {
                        Section {
                            ForEach(loose, id: \.session.id) { session in
                                card(session.session, rows: session.rows)
                            }
                        } header: {
                            Text("No Session File")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top)
                        }
                    }
                }
                .padding()
            }
        } else {
            ProgressView("Checking Capture One sessions...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Cards

    private func card(_ session: CaptureOneSession, rows: [CleanupRow]) -> some View {
        GroupBox {
            DisclosureGroup(isExpanded: isExpanded(session)) {
                // DisclosureGroup adds no gap under the label, so the first divider hits the header
                VStack {
                    ForEach(rows) { row in
                        Divider()
                        itemRow(row)
                            // ponytail: measured, lines child icons up with the session icon past the chevron; adjust if the disclosure chevron changes
                            .padding(.leading, 17)
                    }
                }
                .padding(.top, 6)
            } label: {
                header(session, rows: rows)
                    .contentShape(Rectangle())
                    // macOS only toggles from the chevron; let the whole header do it
                    .onTapGesture { isExpanded(session).wrappedValue.toggle() }
                    .padding(.leading, 4)
            }
            // GroupBox's inset puts the chevron tight against the card edge
            .padding(4)
        }
    }

    private func isExpanded(_ session: CaptureOneSession) -> Binding<Bool> {
        Binding {
            expanded.contains(session.id)
        } set: { isOn in
            if isOn { expanded.insert(session.id) } else { expanded.remove(session.id) }
        }
    }

    private func header(_ session: CaptureOneSession, rows: [CleanupRow]) -> some View {
        let drive = driveMonitor.drives.first { $0.id == session.driveUUID }
        let connected = drive?.isConnected ?? false
        let safe = rows.filter { $0.status == .safe }
        return HStack {
            Label {
                Text(session.name)
            } icon: {
                Image(nsImage: NSWorkspace.shared.listIcon(name: session.file ?? session.name, isDirectory: session.file == nil))
            }
            .lineLimit(1)
            .truncationMode(.middle)
            if session.file == nil {
                Button("Show Folder") { showFolder(session) }
                    .controlSize(.small)
                    .disabled(!connected)
                    .help("Show this folder in Finder")
            } else {
                Button("Open Session") { openSession(session) }
                    .controlSize(.small)
                    .disabled(!connected)
                    .help("Open this session in Capture One")
            }
            Text(drive?.name ?? "Unknown drive")
                .foregroundStyle(connected ? .secondary : .tertiary)
            Spacer()
            if !safe.isEmpty {
                Button("Delete \(formatted(safeSize(safe)))", systemImage: "trash") { pendingTrash = safe }
                    .controlSize(.small)
                    .help("Move this session's safe items to the Trash")
            } else if !connected {
                Text("Connect \(drive?.name ?? "the drive") to check")
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing safe to remove")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func itemRow(_ row: CleanupRow) -> some View {
        HStack {
            Label {
                Text(row.name)
            } icon: {
                Image(nsImage: NSWorkspace.shared.listIcon(name: row.name, isDirectory: row.tab == .settings))
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Text(row.location)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(row.details)
                .foregroundStyle(.secondary)
            Label(row.statusText, systemImage: row.status.symbol)
                .foregroundStyle(row.status.color)
            if let size = row.sizeText {
                Text(size)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { revealInFinder(row) }
        .contextMenu {
            Button("Move to Trash") { pendingTrash = [row] }
                .disabled(row.status != .safe)
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

            // A safe old Settings folder takes its mask backups with it, so they aren't listed twice
            let leaving = Set(folders.filter { $0.status == .safe }.map(\.id))
            let items = folders.map(CleanupRow.Item.settings)
                + maskSets.filter { !leaving.contains("\($0.driveUUID)/\($0.settingsPath)") }.map(CleanupRow.Item.masks)

            rows = items.map { item in
                CleanupRow(item: item, session: CaptureOne.session(driveUUID: item.driveUUID, shootPath: item.shootPath, files: files))
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Safe first, then by name
    private func rowOrder(_ a: CleanupRow, _ b: CleanupRow) -> Bool {
        if (a.status == .safe) != (b.status == .safe) { return a.status == .safe }
        return "\(a.location)/\(a.name)".localizedStandardCompare("\(b.location)/\(b.name)") == .orderedAscending
    }

    private func safeSize(_ rows: [CleanupRow]) -> Int64 {
        rows.filter { $0.status == .safe }.reduce(0) { $0 + $1.size }
    }

    // MARK: - Trash

    private var isConfirmingTrash: Binding<Bool> {
        Binding { pendingTrash != nil } set: { if !$0 { pendingTrash = nil } }
    }

    private var trashTitle: String {
        let rows = pendingTrash ?? []
        return "Move \(rows.count) item\(rows.count == 1 ? "" : "s") (\(formatted(safeSize(rows)))) to the Trash?"
    }

    private func trash(_ rows: [CleanupRow]) async {
        var failed = 0
        for row in rows {
            guard let driveURL = driveURL(row.item.driveUUID) else {
                failed += 1
                continue
            }
            var removed: [String] = []
            switch row.item {
            case .masks(let set):
                let result = await set.moveToTrash(on: driveURL)
                removed = result.trashed
                if !result.failed.isEmpty { failed += 1 }
            case .settings(let folder):
                if await folder.moveToTrash(on: driveURL) { removed = [folder.path] } else { failed += 1 }
            }
            // ponytail: drop them from the index now so they don't reappear before FSEvents rescans; if this fails, that rescan catches up
            try? await DatabaseManager.shared.deleteFiles(driveUUID: row.item.driveUUID, relativePaths: removed)
        }
        await load()
        trashFailures = failed
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

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
