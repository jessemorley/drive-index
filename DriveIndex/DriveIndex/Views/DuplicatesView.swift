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

extension FolderSet {
    /// The most recent folder, else the one with the most files
    var defaultKeep: Int { mostRecent ?? members.indices.max { members[$0].files < members[$1].files } ?? 0 }

    /// From the index: every folder's files all have copies in the others
    var isExactMatch: Bool { members.allSatisfy { $0.shared == $0.files } }
}

extension FolderSet.Member {
    /// Shown in the Trash confirmation for this one folder
    var verdict: String {
        if holdsAnother { return "Holds another folder of this set, so it can't be trashed from here" }
        if isSafeToRemove { return "Safe to remove: every file has a copy in another folder" }
        let reasons = [(onlyHere, "only here"), (changed, "changed"), (unchecked, "not checked yet")]
            .filter { $0.0 > 0 }.map { "\($0.0.formatted()) \($0.1)" }
        return "Not safe to remove: " + reasons.joined(separator: ", ")
    }

    /// What stops this folder going to the Trash while the set's folder at `kept` stays, with counts.
    /// None for a session: the index can't see its adjustments, so the disk check before trashing decides
    func blockers(keeping kept: Int) -> [(Blocker, Int)] {
        guard !isSession else { return [] }
        // Files with no copy in the kept folder beyond the ones only here or changed: their other copy is in a folder going too
        let all: [(Blocker, Int)] = [(.holdsAnother, holdsAnother ? 1 : 0), (.onlyHere, onlyHere), (.changed, changed),
                                     (.notInKept, max(0, missingFrom[kept] - onlyHere - changed)), (.unchecked, unchecked)]
        return all.filter { $0.1 > 0 }
    }
}

enum Blocker {
    case holdsAnother, onlyHere, changed, notInKept, unchecked

    var color: Color {
        switch self {
        case .holdsAnother, .unchecked: .secondary
        case .onlyHere, .notInKept: .blue
        case .changed: .orange
        }
    }

    /// In the folder's status line
    func short(_ n: Int) -> String {
        switch self {
        case .holdsAnother: "holds another folder of this set"
        case .onlyHere: "\(n.formatted()) only here"
        case .changed: "\(n.formatted()) changed"
        case .notInKept: "\(n.formatted()) not in kept folder"
        case .unchecked: "\(n.formatted()) not checked"
        }
    }

    func long(_ n: Int) -> String {
        let one = n == 1
        return switch self {
        case .holdsAnother: "Holds another folder of this set"
        case .onlyHere: "\(n.formatted()) \(one ? "file exists" : "files exist") only in this folder"
        case .changed: "\(n.formatted()) \(one ? "file differs" : "files differ") from the other copies"
        case .notInKept: "\(n.formatted()) \(one ? "file has its" : "files have their") only other copy in a folder you’re removing"
        case .unchecked: "\(n.formatted()) \(one ? "file hasn’t" : "files haven’t") been checked"
        }
    }

    var action: String {
        switch self {
        case .holdsAnother: "Reveal in Finder"
        case .onlyHere, .notInKept: "Copy to Kept Folder"
        case .changed: "Compare…"
        case .unchecked: "Check Now"
        }
    }
}

enum DuplicateSelection: Hashable {
    case set(String)
    case file(Int64)
}

private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

/// For a count that ticks up: "4.00 GB", not "4 GB", so its width doesn't flicker at each whole number
private let paddedBytes: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.zeroPadsFractionDigits = true
    return formatter
}()

/// The whole window while Duplicates is selected: the app's sidebar, the list of sets and loose files, and
/// the review. Three native columns, so the toolbar title sits over the review
struct DuplicatesView<Sidebar: View>: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @Binding var columnVisibility: NavigationSplitViewVisibility
    @ViewBuilder let sidebar: Sidebar

    // Kept sorted
    @State private var sets: [FolderSet] = []
    @State private var loose: [DuplicateGroup] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var comparing: FolderPair?
    @State private var selection: DuplicateSelection?
    /// Set id → index of the folder to keep, once picked
    @State private var keep: [String: Int] = [:]
    /// "kept member id|other member id" → the two folders compared from the index; cleared on each load
    @State private var comparisons: [String: FolderComparison] = [:]
    @State private var loads = 0
    /// Check on Disk, by "set id#kept member id": each other folder, and what it has that the kept one lacks (nil: nothing)
    @State private var diskVerdicts: [String: [(folder: FolderLocation, losses: String?)]] = [:]
    /// Every disk check's hashes, so the next action on the same folders only re-walks them and
    /// hashes files whose size or modified date changed since
    @State private var diskHashes: [String: String] = [:]
    /// Checking a set's folders on disk, or updating its older copies: what, and bytes done of the most expected
    @State private var working: (set: String, label: String, done: Int64, total: Int64)?
    @State private var workTask: Task<Void, Never>?
    @AppStorage("duplicates.sort") private var sort: DuplicateSort = .wasted
    @AppStorage("duplicates.excludeLocal") private var excludeLocal = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            Group {
                if loaded && errorMessage == nil && !(sets.isEmpty && loose.isEmpty) { list } else { Color.clear }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 440)
            .navigationTitle("Duplicates")
            .toolbar {
                // As Mail's filter: filled while it hides something
                Menu("Filter", systemImage: excludeLocal ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease") {
                    Picker("Sort By", selection: $sort) {
                        ForEach(DuplicateSort.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    if let mac = driveMonitor.drives.first(where: \.isLocal) {
                        Toggle("Exclude \(mac.name)", isOn: $excludeLocal)
                    }
                }
                .help("Sort and filter duplicates")
            }
        } detail: {
            content
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .indexingStatusBar(indexManager)
                .toolbar(id: "duplicates-toolbar") {
                    // Detail-column items start at the column's leading edge otherwise
                    ToolbarSpacer(.flexible)
                    ToolbarItem(id: "compare", placement: .automatic) {
                        let pairs = comparablePairs
                        if pairs.count > 1 {
                            Menu("Compare Folders", systemImage: "arrow.left.arrow.right") {
                                ForEach(pairs.indices, id: \.self) { i in
                                    Button("\(pairs[i].a.driveName): \(pairs[i].a.relativePath)  ↔  \(pairs[i].b.driveName): \(pairs[i].b.relativePath)") { comparing = pairs[i] }
                                }
                            }
                            .help("Compare the selected folders")
                        } else {
                            Button("Compare Folders", systemImage: "arrow.left.arrow.right") { comparing = pairs.first }
                                .help("Compare the selected folders")
                                .disabled(pairs.isEmpty)
                        }
                    }
                    ToolbarSpacer(.fixed)
                    ToolbarItem(id: "refresh", placement: .automatic) {
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            Task { await load() }
                        }
                        .help("Refresh duplicates")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: excludeLocal) { await load() }
        .task(id: comparisonKey) { await compareKept() }
        .onChange(of: selection) { workTask?.cancel() }
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
            // Only the first load: later ones update the lists in place, so changes animate
            ProgressView("Finding duplicates...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if sets.isEmpty && loose.isEmpty {
            ContentUnavailableView("No Duplicates", systemImage: "doc.on.doc", description: Text("Files with identical contents will appear here"))
        } else {
            detail
        }
    }

    // MARK: - List

    private var order: [DuplicateSelection] { sets.map { .set($0.id) } + loose.map { .file($0.cardID) } }

    private var list: some View {
        List(selection: $selection) {
            if !sets.isEmpty {
                Section {
                    header("Folders", sets.count.formatted())
                    ForEach(sets) { set in
                        row(icon: icon(set), name: set.name, copies: set.members.count, size: set.wastedBytes)
                            .tag(DuplicateSelection.set(set.id))
                    }
                }
            }
            if !loose.isEmpty {
                Section {
                    header("Files", loose.count.formatted())
                    ForEach(loose, id: \.cardID) { group in
                        row(icon: NSWorkspace.shared.listIcon(name: group.name, isDirectory: false), name: group.name, copies: group.files.count, size: group.wastedBytes)
                            .tag(DuplicateSelection.file(group.cardID))
                    }
                }
            }
        }
    }

    /// A row, not a section header: section headers pin under the toolbar
    private func header(_ title: String, _ count: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Text(count).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .selectionDisabled()
    }

    /// A session shows Finder's icon for a Capture One session (its .cosessiondb)
    private func icon(_ set: FolderSet) -> NSImage {
        let isSession = set.members.contains(where: \.isSession)
        return NSWorkspace.shared.listIcon(name: isSession ? "Session.cosessiondb" : "", isDirectory: !isSession)
    }

    private func row(icon: NSImage, name: String, copies: Int, size: Int64) -> some View {
        HStack {
            Image(nsImage: icon)
            Text(name).lineLimit(1)
            StatusChip(title: copies.formatted(), color: nil)
                .help("\(copies) copies")
            Spacer()
            Text(bytes(size)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func skip() {
        guard let selection, let i = order.firstIndex(of: selection) else { return }
        self.selection = order[(i + 1) % order.count]
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .set(let id):
            if let set = sets.first(where: { $0.id == id }) { review(set) }
        case .file(let id):
            if let group = loose.first(where: { $0.cardID == id }) { copies(group) }
        case nil:
            ContentUnavailableView("No Selection", systemImage: "doc.on.doc")
        }
    }

    private func isConnected(_ driveUUID: String) -> Bool {
        driveMonitor.drives.first { $0.id == driveUUID }?.isConnected ?? false
    }

    @ViewBuilder
    private func driveIcon(_ driveUUID: String, size: CGFloat = 16) -> some View {  // Finder list-view icon size
        if let drive = driveMonitor.drives.first(where: { $0.id == driveUUID }) {
            Image(nsImage: drive.finderIcon)
                .resizable()
                .frame(width: size, height: size)
        }
    }

    private func review(_ set: FolderSet) -> some View {
        let kept = keep[set.id] ?? set.defaultKeep
        let removed = set.members.indices.filter { $0 != kept }
        let blockers = removed.flatMap { i in set.members[i].blockers(keeping: kept).map { (member: i, kind: $0.0, count: $0.1) } }
        let offline = Array(Set(removed.map { set.members[$0].folder }.filter { !isConnected($0.driveUUID) }.map(\.driveName))).sorted()

        return Form {
            Section {
                ForEach(Array(set.members.enumerated()), id: \.element.id) { i, _ in
                    member(set.members[i], kept: i == kept, mostRecent: i == set.mostRecent, identical: set.isExactMatch, blockers: set.members[i].blockers(keeping: kept))
                        .onTapGesture { keep[set.id] = i }
                }
            } header: {
                paneTitle
                HStack {
                    Text("Keep which folder?")
                    Spacer()
                    legend
                }
                .padding(.bottom, 6)
            }

            keptFiles(set, kept: kept)

            Section {
                if let verdicts = diskVerdicts[set.id + "#" + set.members[kept].id] {
                    if verdicts.allSatisfy({ $0.losses == nil }) {
                        Label {
                            Text("Clear to delete: on disk, every file in the other \(verdicts.count == 1 ? "copy" : "copies") is in the kept folder")
                        } icon: {
                            Image(systemName: "checkmark.circle").foregroundStyle(.green)
                        }
                    }
                    ForEach(verdicts.indices, id: \.self) { i in
                        if let losses = verdicts[i].losses {
                            Label {
                                Text("Not clear to delete \(verdicts[i].folder.driveName) · \(verdicts[i].folder.relativePath): \(losses), on disk")
                            } icon: {
                                Image(systemName: "xmark.circle").foregroundStyle(.red)
                            }
                        }
                    }
                } else if let session = removed.map({ set.members[$0] }).first(where: { $0.isSession && $0.onlyHere + $0.changed > 0 }) {
                    // Sessions have no index blockers, but the index still sees their photos
                    Label {
                        Text("\(session.folder.name) has \((session.onlyHere + session.changed).formatted()) files the kept folder lacks or has changed. It's in a Capture One session, so Check on Disk decides")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                } else if blockers.isEmpty {
                    Label {
                        Text(set.isExactMatch
                             ?"Safe to delete: the folders are an exact match"
                             : "Safe to delete: the kept folder has every file")
                    } icon: {
                        Image(systemName: "checkmark.circle").foregroundStyle(.green)
                    }
                }
                ForEach(blockers.indices, id: \.self) { index in
                    let b = blockers[index]
                    let m = set.members[b.member]
                    HStack {
                        Image(systemName: "circle.fill").font(.caption2).foregroundStyle(b.kind.color)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(b.kind.long(b.count))
                            Text("\(m.folder.driveName) · \(m.folder.relativePath)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button(b.kind.action) {
                            switch b.kind {
                            case .holdsAnother: revealInFinder(m.folder)
                            case .changed: comparing = FolderPair(a: set.members[kept].folder, b: m.folder)
                            default: break
                            }
                        }
                        .controlSize(.small)
                        // ponytail: Copy to Kept Folder and Check Now aren't built yet
                        .disabled(b.kind != .holdsAnother && b.kind != .changed)
                    }
                    .padding(.vertical, 4)
                }
                if !offline.isEmpty {
                    let one = offline.count == 1
                    Label("\(offline.formatted()) \(one ? "is" : "are") offline. Connect \(one ? "it" : "them") to update or trash \(one ? "its" : "their") folders.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if let working, working.set == set.id {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Text(working.label).foregroundStyle(.secondary)
                        ProgressView(value: Double(working.done), total: Double(max(working.total, 1)))
                            .frame(width: 120)
                        // Until both folders are walked there's nothing to measure against
                        if working.total > 0 {
                            // Sized by the widest count it'll show, so the bar doesn't shift as the count changes length
                            ZStack(alignment: .leading) {
                                Text("888.88 GB of \(bytes(working.total))").hidden()
                                Text("\(paddedBytes.string(fromByteCount: working.done)) of \(bytes(working.total))")
                            }
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                        Button("Cancel") { workTask?.cancel() }
                    } else {
                        // "Older" only when the kept folder is the most recent
                        let copies = (kept == set.mostRecent && !set.isExactMatch ? "Older " : "Other ") + (removed.count == 1 ? "Copy" : "Copies")
                        Button("Check on Disk") { onDisk(set, keeping: kept, then: .check) }
                            .help("Check on disk whether the other copies are clear to delete, including files the index leaves out")
                            .disabled(!offline.isEmpty || !isConnected(set.members[kept].folder.driveUUID))
                        Spacer()
                        Button("Skip") { skip() }
                        Button("Update \(removed.count) \(copies)…") { onDisk(set, keeping: kept, then: .update) }
                            .disabled(!offline.isEmpty || set.members.contains(where: \.holdsAnother))
                        Button("Move \(removed.count) \(copies) to Trash") { onDisk(set, keeping: kept, then: .trash) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!blockers.isEmpty || !offline.isEmpty || removed.contains { set.members[$0].holdsAnother })
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Actions")
                    .padding(.top, 12)
                    .padding(.bottom, 6)
            }
        }
        .formStyle(.grouped)
        // A new set gets a new Form: reusing one across sets mis-laid the rows it added
        .id(set.id)
    }

    /// The kept folder against the others, from the index: its files no other folder has, then the files
    /// at the same path whose contents differ, with which copy is newer
    @ViewBuilder
    private func keptFiles(_ set: FolderSet, kept: Int) -> some View {
        let keptMember = set.members[kept]
        let results = set.members.filter { $0.id != keptMember.id }.compactMap { other in
            comparisons[keptMember.id + "|" + other.id].map { (other: other, result: $0) }
        }
        let root = keptMember.folder.url(in: driveMonitor.drives)
        if !results.isEmpty, results.count == set.members.count - 1 {
            let unique = results.dropFirst().reduce(Set(results[0].result.onlyA.map(\.path))) { $0.intersection($1.result.onlyA.map(\.path)) }
            let files = results[0].result.onlyA.filter { unique.contains($0.path) }
            let changed = results.flatMap { r in r.result.changed.map { (other: r.other, file: $0) } }
            if !files.isEmpty || !changed.isEmpty {
                Section {
                    if !files.isEmpty {
                        subheader("Unique files: \(files.count.formatted()) \(files.count == 1 ? "file" : "files"), \(bytes(files.reduce(0) { $0 + $1.size }))")
                        OnlyHereList(files: files, listing: results[0].result.listingFolders().a, changed: 0, otherName: "",
                                     root: root, boxed: false) { EmptyView() }
                    }
                    if !changed.isEmpty {
                        subheader("Changed: \(changed.count.formatted()) \(changed.count == 1 ? "file" : "files")")
                        // ponytail: the first 200; a session can change thousands of files
                        ForEach(changed.prefix(200).indices, id: \.self) { i in
                            let (other, file) = changed[i]
                            HStack {
                                Label {
                                    Text(file.path).lineLimit(1).truncationMode(.middle)
                                } icon: {
                                    Image(nsImage: NSWorkspace.shared.listIcon(name: (file.path as NSString).lastPathComponent, isDirectory: false))
                                }
                                Spacer()
                                switch file.newer {
                                case .a: Text("Newer here").foregroundStyle(.secondary)
                                case .b: Text("Newer on \(other.folder.driveName)").foregroundStyle(.orange)
                                case nil: Text("Same date on \(other.folder.driveName)").foregroundStyle(.secondary)
                                }
                            }
                            .contextMenu {
                                Button("Reveal in Finder") { root.map { NSWorkspace.shared.activateFileViewerSelecting([$0.appending(path: file.path)]) } }
                                    .disabled(root == nil)
                            }
                        }
                        if changed.count > 200 {
                            Text("…and \((changed.count - 200).formatted()) more").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func subheader(_ title: String) -> some View {
        Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([("Copied elsewhere", "square.fill", AnyShapeStyle(.tertiary)), ("Only here", "square.fill", AnyShapeStyle(.blue)),
                     ("Changed", "square.fill", AnyShapeStyle(.orange)), ("Not checked", "square", AnyShapeStyle(.secondary))], id: \.0) { title, symbol, style in
                Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(style) }
                    .lineLimit(1)
            }
        }
        .fixedSize()
        .font(.caption)
        .fontWeight(.regular)
        .foregroundStyle(.secondary)
    }

    /// A folder of the set: radio, drive and path, how its files overlap the others, and what blocks trashing it
    private func member(_ m: FolderSet.Member, kept: Bool, mostRecent: Bool, identical: Bool, blockers: [(Blocker, Int)]) -> some View {
        let status = kept ? nil
            : blockers.isEmpty ? nil
            : blockers.map { $0.0.short($0.1) }.joined(separator: ", ")
        return HStack(spacing: 8) {
            Image(systemName: kept ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(kept ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    driveIcon(m.folder.driveUUID)
                    Text(m.folder.driveName).fontWeight(.medium)
                    Text(m.folder.relativePath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if identical {
                        StatusChip(title: "Identical", color: .orange)
                    } else if mostRecent {
                        StatusChip(title: "Most recent", color: .green)
                    }
                }
                .foregroundStyle(isConnected(m.folder.driveUUID) ? .primary : .secondary)
                OverlapBar(member: m)
                Text("\(m.files.formatted()) files · \(bytes(m.bytes))\(m.latest.map { " · modified \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")\(status.map { " — \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(m.folder) }
                .disabled(!isConnected(m.folder.driveUUID))
            Button("Move to Trash…") { confirmTrash(m) }
                .disabled(!isConnected(m.folder.driveUUID) || m.holdsAnother)
        }
    }

    /// The copies of a duplicate file outside every set
    private func copies(_ group: DuplicateGroup) -> some View {
        Form {
            Section {
                ForEach(group.files, id: \.id) { file in
                    let connected = isConnected(file.driveUUID)
                    HStack {
                        driveIcon(file.driveUUID)
                        Text(file.driveName).fontWeight(.medium)
                        Text(file.relativePath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if let date = file.modifiedAt { Text(date, format: .dateTime.day().month().year()).foregroundStyle(.secondary) }
                        Button("Move to Trash", systemImage: "trash") { moveToTrash(file) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .disabled(!connected)
                    }
                    .foregroundStyle(connected ? .primary : .secondary)
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                    .onTapGesture(count: 2) { revealInFinder(file) }
                    .contextMenu {
                        Button("Reveal in Finder") { revealInFinder(file) }.disabled(!connected)
                        Button("Move to Trash") { moveToTrash(file) }.disabled(!connected)
                    }
                }
            } header: {
                paneTitle
                Text("Copies")
            }
        }
        .formStyle(.grouped)
    }

    /// Atop the review: a three-column window titles the middle column (as Mail does), not this one
    private var paneTitle: some View {
        HStack {
            // The list's icon at a size spanning both lines, as in Capture One
            if let icon = titles.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(titles.title).font(.title2.bold()).foregroundStyle(.primary)
                Text(titles.subtitle).font(.body).foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.bottom, 16)
    }

    /// The selected set or file, and its copies
    private var titles: (icon: NSImage?, title: String, subtitle: String) {
        switch selection {
        case .set(let id):
            guard let set = sets.first(where: { $0.id == id }) else { break }
            return (icon(set), set.name, "\(set.members.count) copies · \(bytes(set.wastedBytes))")
        case .file(let id):
            guard let group = loose.first(where: { $0.cardID == id }) else { break }
            return (NSWorkspace.shared.listIcon(name: group.name, isDirectory: false), group.name, "\(group.files.count) copies · \(bytes(group.size)) each")
        case nil:
            break
        }
        return (nil, "Duplicates", "")
    }

    // MARK: - Data

    private var selectedSet: FolderSet? {
        guard case .set(let id) = selection else { return nil }
        return sets.first { $0.id == id }
    }

    /// Changes with the selected set, its kept folder, and each load
    private var comparisonKey: String {
        selectedSet.map { "\(loads)#\($0.id)#\(keep[$0.id] ?? $0.defaultKeep)" } ?? ""
    }

    /// The selected set's kept folder against each other one, from the index: no disk, no hashing
    private func compareKept() async {
        guard let set = selectedSet else { return }
        let kept = set.members[keep[set.id] ?? set.defaultKeep]
        let database = DatabaseManager.shared
        guard let keptFiles = try? await database.getFolderFiles(driveUUID: kept.folder.driveUUID, path: kept.folder.relativePath) else { return }
        for other in set.members where other.id != kept.id && comparisons[kept.id + "|" + other.id] == nil {
            // One folder inside the other: the outer one's files leave the inner one out, or they'd match themselves
            let (innerOfKept, innerOfOther) = (kept.folder.path(of: other.folder), other.folder.path(of: kept.folder))
            let a = keptFiles.filter { file in innerOfKept.map { !file.path.hasPrefix($0 + "/") } ?? true }
            guard let all = try? await database.getFolderFiles(driveUUID: other.folder.driveUUID, path: other.folder.relativePath),
                  case let b = all.filter({ file in innerOfOther.map { !file.path.hasPrefix($0 + "/") } ?? true }),
                  let result = try? await Task.detached(operation: { try FolderComparison.compare(index: a, b) }).value,
                  !Task.isCancelled else { continue }
            comparisons[kept.id + "|" + other.id] = result
        }
    }

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
            let before = order
            withAnimation { (sets, loose) = (sorted(overview.sets), sorted(overview.loose)) }
            // A trashed selection hands it to whatever took its place in the list
            let now = order
            if selection == nil || !now.contains(selection!) {
                let i = selection.flatMap { before.firstIndex(of: $0) } ?? 0
                selection = now.isEmpty ? nil : now[min(i, now.count - 1)]
            }
            keep = keep.filter { id, _ in sets.contains { $0.id == id } }
            comparisons = [:]
            diskVerdicts = [:]
            loads += 1
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

    /// What the toolbar's Compare offers: a set's kept folder against each other one, or each two of
    /// the folders holding a file's copies
    private var comparablePairs: [FolderPair] {
        switch selection {
        case .set(let id):
            guard let set = sets.first(where: { $0.id == id }) else { return [] }
            let kept = set.members[keep[set.id] ?? set.defaultKeep]
            return set.members.filter { $0.id != kept.id }.map { FolderPair(a: kept.folder, b: $0.folder) }
        case .file(let id):
            guard let group = loose.first(where: { $0.cardID == id }) else { return [] }
            let folders = group.files.map {
                FolderLocation(driveUUID: $0.driveUUID, driveName: $0.driveName, relativePath: ($0.relativePath as NSString).deletingLastPathComponent)
            }
            .reduce(into: [FolderLocation]()) { if !$0.contains($1) { $0.append($1) } }
            return folders.indices.flatMap { i in folders[(i + 1)...].map { FolderPair(a: folders[i], b: $0) } }
        case nil:
            return []
        }
    }

    private func moveToTrash(_ file: DuplicateFile) {
        moveToTrash(driveUUID: file.driveUUID, relativePath: file.relativePath)
    }

    /// A whole folder goes only after a native confirmation that says what's in it and what isn't elsewhere
    private func confirmTrash(_ member: FolderSet.Member) {
        guard !member.holdsAnother else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "Move “\(member.folder.name)” on \(member.folder.driveName) to the Trash?"
        alert.informativeText = "\(member.files.formatted()) files, \(bytes(member.bytes)). \(member.verdict)."
        alert.alertStyle = member.isSafeToRemove ? .warning : .critical
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        moveToTrash([member.folder])
    }

    /// The set's other folders, trashed or updated from the kept one. The index can't see everything
    /// (Capture One's adjustments aren't indexed), so each is compared with the kept one on disk first,
    /// as Folder Compare does. Trashing: an ordinary folder holding anything the kept one lacks, or any
    /// changed file, isn't moved; a session has no blockers, and the confirmation says what it would
    /// lose. The trash button is disabled while the index finds blockers; this is the check that counts
    private enum DiskAction { case check, update, trash }

    /// Check: says whether the other folders are clear to delete, and changes nothing
    private func onDisk(_ set: FolderSet, keeping keep: Int, then action: DiskAction) {
        let kept = set.members[keep]
        let others = set.members.indices.filter { $0 != keep }.map { set.members[$0] }
        let urls = others.compactMap { $0.folder.url(in: driveMonitor.drives) }
        // Nested folders: updating one from the other copies it into itself, and trashing the outer one takes the
        // inner one too. Trashing the inner one is fine: the outer one's counts and disk check leave it out
        let allowed = switch action {
        case .check: true
        case .update: !set.members.contains(where: \.holdsAnother)
        case .trash: others.allSatisfy { $0.blockers(keeping: keep).isEmpty && !$0.holdsAnother }
        }
        guard allowed,
              urls.count == others.count, let keptURL = kept.folder.url(in: driveMonitor.drives) else {
            NSSound.beep()
            return
        }
        workTask?.cancel()
        workTask = Task {
            defer { if working?.set == set.id { working = nil } }
            var results: [(member: FolderSet.Member, result: FolderComparison)] = []
            do {
                for (member, url) in zip(others, urls) {
                    working = (set.id, "Checking on disk…", 0, 0)
                    let result = try await FolderComparison.compare(keptURL, url, reusing: diskHashes, skipping: (kept.folder.path(of: member.folder), member.folder.path(of: kept.folder))) { _, hashed, total in
                        Task { @MainActor in if working?.set == set.id { working = (set.id, "Checking on disk…", hashed, total) } }
                    }
                    diskHashes = result.hashes
                    results.append((member, result))
                }
            } catch {
                if !(error is CancellationError) { NSAlert(error: error).runModal() }
                return
            }
            working = nil
            switch action {
            case .check:
                diskVerdicts[set.id + "#" + kept.id] = results.map { ($0.member.folder, Self.losses($0.result)) }
            case .update: await update(results, from: kept, at: keptURL, to: urls, set: set.id)
            case .trash: confirmTrash(results, kept: kept)
            }
        }
    }

    /// After the disk check: makes each other copy match the kept one, as Folder Compare's Sync does.
    /// Replaced and extra files go to the Trash, missing ones are copied in, keeping their dates
    private func update(_ results: [(member: FolderSet.Member, result: FolderComparison)], from kept: FolderSet.Member,
                        at source: URL, to urls: [URL], set: String) async {
        let plans = results.map { $0.result.mirrorPlan(from: .a) }
        let alert = NSAlert()
        guard plans.contains(where: { !$0.replace.isEmpty || !$0.remove.isEmpty || !$0.add.isEmpty }) else {
            alert.messageText = "Already up to date"
            alert.informativeText = "On disk, every other copy matches \(kept.folder.relativePath) on \(kept.folder.driveName)."
            alert.runModal()
            return
        }
        alert.messageText = results.count == 1 ? "Update 1 copy?" : "Update \(results.count) copies?"
        alert.informativeText = zip(results, plans).map { r, plan in
            "\(r.member.folder.driveName): \(r.member.folder.relativePath)\n    \(plan.add.count.formatted()) added, \(plan.replace.count.formatted()) replaced, \(plan.remove.count.formatted()) removed"
                + (plan.replacingNewer > 0 ? "\n    Careful: \(plan.replacingNewer.formatted()) of the replaced files are newer there" : "")
        }.joined(separator: "\n")
            + "\n\n\(results.count == 1 ? "It" : "Each") will match \(kept.folder.relativePath) on \(kept.folder.driveName). Replaced and removed files go to the Trash."
        alert.alertStyle = plans.contains { $0.replacingNewer > 0 || !$0.remove.isEmpty } ? .critical : .warning
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var failures: [String] = []
        for ((r, plan), url) in zip(zip(results, plans), urls) {
            let label = "Updating \(r.member.folder.driveName)…"
            let total = plan.add.reduce(0) { $0 + $1.size } + r.result.changed.reduce(0) { $0 + $1.sizeA }
            working = (set, label, 0, total)
            do {
                failures += try await FolderComparison.mirror(plan, from: source, to: url) { done in
                    Task { @MainActor in if working?.set == set { working = (set, label, done, total) } }
                }
                .map { "\(r.member.folder.driveName): \($0.path): \($0.error.localizedDescription)" }
            } catch is CancellationError {
                break
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        working = nil
        if !failures.isEmpty {
            let report = NSAlert()
            report.messageText = "Some files weren't updated"
            report.informativeText = failures.prefix(20).joined(separator: "\n") + (failures.count > 20 ? "\n…and \(failures.count - 20) more" : "")
            report.runModal()
        }
        await load()
    }

    /// What trashing the other side (B) of a disk comparison loses, the kept side staying; nil when nothing.
    /// Its older edits and superseded Capture One settings don't count
    private static func losses(_ r: FolderComparison) -> String? {
        let lost = r.lostWithoutB()
        var parts: [String] = []
        if !lost.only.isEmpty {
            // Where they are: the folder rows Folder Compare would list, else the files
            let listing = r.listingFolders().b
            let places = lost.only.map { file in ((listing[file.path].flatMap { $0.isEmpty ? nil : $0 } ?? file.path) as NSString).lastPathComponent }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            parts.append("\(lost.only.count.formatted()) \(lost.only.count == 1 ? "file" : "files") only there (\(bytes(lost.only.reduce(0) { $0 + $1.size }))), in "
                         + places.prefix(3).joined(separator: ", ") + (places.count > 3 ? " and \(places.count - 3) more" : ""))
        }
        let newer = lost.changed.count { $0.newer == .b }, sameDate = lost.changed.count - newer
        if newer > 0 { parts.append("\(newer.formatted()) changed \(newer == 1 ? "file is" : "files are") newer there") }
        if sameDate > 0 { parts.append("\(sameDate.formatted()) changed \(sameDate == 1 ? "file has" : "files have") the same date in both") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// After the disk check: refuses when an ordinary folder would lose anything, otherwise asks,
    /// listing what each session would lose
    private func confirmTrash(_ results: [(member: FolderSet.Member, result: FolderComparison)], kept: FolderSet.Member) {
        let losses = Self.losses
        let refused = results.filter { !$0.member.isSession && losses($0.result) != nil }
        let alert = NSAlert()
        guard refused.isEmpty else {
            alert.messageText = "Not moved to the Trash"
            alert.informativeText = "Compared on disk with \(kept.folder.relativePath) on \(kept.folder.driveName):\n"
                + refused.map { "\($0.member.folder.driveName): \($0.member.folder.relativePath): \(losses($0.result)!)" }.joined(separator: "\n")
                + "\n\nOpen Compare Folders to copy or sync what's missing."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        let anyLoss = results.contains { losses($0.result) != nil }
        alert.messageText = results.count == 1 ? "Move 1 folder to the Trash?" : "Move \(results.count) folders to the Trash?"
        alert.informativeText = results.map { r in
            "\(r.member.folder.driveName): \(r.member.folder.relativePath)" + (losses(r.result).map { "\n    Would lose: \($0)" } ?? "")
        }.joined(separator: "\n")
            + "\n\nCompared on disk with \(kept.folder.relativePath) on \(kept.folder.driveName), which stays."
            + (anyLoss ? " A Capture One session above has files the kept one lacks." : " Every file has a copy there.")
        alert.alertStyle = anyLoss ? .critical : .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        moveToTrash(results.map(\.member.folder))
    }

    private func moveToTrash(driveUUID: String, relativePath: String) {
        moveToTrash([FolderLocation(driveUUID: driveUUID, driveName: "", relativePath: relativePath)])
    }

    /// Trashes files or folders, drops them (and anything inside) from the index, then recomputes the sets once
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

/// How a folder's files overlap the rest of its set, by file count. Not checked yet is the empty track
private struct OverlapBar: View {
    let member: FolderSet.Member

    var body: some View {
        GeometryReader { g in
            let unit = g.size.width / CGFloat(max(member.files, 1))
            HStack(spacing: 0) {
                Rectangle().fill(.tertiary).frame(width: unit * CGFloat(member.shared))
                Rectangle().fill(.orange).frame(width: unit * CGFloat(member.changed))
                Rectangle().fill(.blue).frame(width: unit * CGFloat(member.onlyHere))
            }
        }
        .frame(height: 4)
        .background(.quaternary)
        .clipShape(.capsule)
        .help("\(member.shared.formatted()) copied elsewhere, \(member.changed.formatted()) changed, \(member.onlyHere.formatted()) only here, \(member.unchecked.formatted()) not checked yet")
    }
}

#Preview {
    DuplicatesView(columnVisibility: .constant(.all)) { Text("Sidebar") }
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 900, height: 700)
}
