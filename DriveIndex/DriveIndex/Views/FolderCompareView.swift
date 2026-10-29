//
//  FolderCompareView.swift
//  DriveIndex
//
//  Sheet comparing two folders side by side: how many files each shares with the other, the files
//  only each has, copying them across, and trashing a folder once the other has everything
//

import SwiftUI

struct FolderPair: Identifiable {
    let id = UUID()
    let a: FolderLocation
    let b: FolderLocation
}

struct FolderCompareView: View {
    let pair: FolderPair
    /// Trashes a folder from disk and drops it from the index and the cards
    let onTrash: (FolderLocation) -> Void

    @EnvironmentObject var driveMonitor: DriveMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var result: FolderComparison?
    @State private var fromIndex = false
    @State private var progress: (files: Int, bytes: Int64) = (0, 0)
    @State private var errorMessage: String?
    @State private var copying: (done: Int64, total: Int64)?
    @State private var copyTask: Task<Void, Never>?
    @State private var copyFailures: [String] = []
    /// Comparing again after a copy, with the earlier result still on screen
    @State private var checking = false

    private var urls: (URL, URL)? {
        guard let a = pair.a.url(in: driveMonitor.drives), let b = pair.b.url(in: driveMonitor.drives) else { return nil }
        return (a, b)
    }

    /// The first run, before there's anything to show
    private var isLoading: Bool { result == nil && errorMessage == nil }

    /// Reruns on disk when a drive connects
    private var connected: [Bool] {
        [pair.a, pair.b].map { $0.url(in: driveMonitor.drives) != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                columns { side in
                    GroupBox {
                        VStack(spacing: 16) {
                            header(side)
                            if let result { availability(side, result) }
                        }
                        .padding(8)
                    }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                } else if let result {
                    copyControls(result)
                    let listing = result.listingFolders()
                    columns { side in
                        filesList(side, side == .a ? result.onlyA : result.onlyB, side == .a ? listing.a : listing.b,
                                  root: side == .a ? urls?.0 : urls?.1)
                    }
                    changedList(result.changed)
                    movedList(result.moved)
                }
            }
            .padding()
        }
        .overlay {
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Comparing…")
                    Text("\(progress.files) files, \(formatted(progress.bytes)) hashed")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 480, idealHeight: 680)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isLoading || copying != nil ? "Cancel" : "Done") { dismiss() }
            }
        }
        .task(id: connected) { await run() }
        .onDisappear { copyTask?.cancel() }
    }

    // MARK: - Sections

    /// Side A on the left, side B on the right, equal widths
    private func columns(@ViewBuilder _ content: (FolderComparison.Side) -> some View) -> some View {
        HStack(alignment: .top, spacing: 16) {
            content(.a).frame(maxWidth: .infinity, alignment: .topLeading)
            content(.b).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// The drive and the folder, dimmed until the first comparison is done
    private func header(_ side: FolderComparison.Side) -> some View {
        let folder = side == .a ? pair.a : pair.b
        let drive = driveMonitor.drives.first { $0.id == folder.driveUUID }
        return VStack(spacing: 6) {
            if let drive {
                Image(nsImage: drive.finderIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
                    // ponytail: no system dimmed style for an image; matches the tertiary text
                    .opacity(isLoading ? 0.4 : 1)
            }
            Text(folder.driveName)
                .font(.headline)
                .foregroundStyle(isLoading ? .tertiary : .primary)
            Text(folder.relativePath.isEmpty ? "/" : folder.relativePath)
                .foregroundStyle(isLoading ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
    }

    /// This side's files by count: shared with the other side (in both, or moved), or only here.
    /// Changed files are neither.
    private func availability(_ side: FolderComparison.Side, _ result: FolderComparison) -> some View {
        let unique = side == .a ? result.onlyA.count : result.onlyB.count
        let shared = result.both.count + result.moved.count
        let fileTotal = max(unique + shared, 1)
        let color: Color = side == .a ? .blue : .orange
        func percent(_ n: Int) -> String {
            (Double(n) / Double(fileTotal)).formatted(.percent.precision(.fractionLength(0...1)))
        }

        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let scale = geometry.size.width / CGFloat(fileTotal)
                HStack(spacing: 0) {
                    Rectangle().fill(.tertiary).frame(width: CGFloat(shared) * scale)
                    Rectangle().fill(color).frame(width: CGFloat(unique) * scale)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            HStack {
                legend("Shared: \(percent(shared))", .tertiary)
                Spacer()
                legend("Only here: \(percent(unique))", color)
            }
        }
    }

    /// Copy what's missing one way or both, then compare again. A folder can be trashed only once
    /// that fresh comparison shows the other copy has everything.
    @ViewBuilder
    private func copyControls(_ result: FolderComparison) -> some View {
        if fromIndex {
            let offline = [pair.a, pair.b].filter { $0.url(in: driveMonitor.drives) == nil }.map(\.driveName)
            Text("From the index. Connect \(offline.joined(separator: " and ")) to compare on disk. The index skips Capture One sidecars and can be out of date.")
                .foregroundStyle(.secondary)
        } else if checking {
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking copies… \(formatted(progress.bytes)) hashed")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else if let copying {
            ProgressView(value: Double(copying.done), total: Double(max(copying.total, 1))) {
                Text("Copying… \(formatted(copying.done)) of \(formatted(copying.total))")
                    .monospacedDigit()
            }
        } else if !result.onlyA.isEmpty || !result.onlyB.isEmpty {
            HStack {
                Button("Copy to \(driveName(.b))", systemImage: "arrow.right") { startCopy([.a]) }
                    .disabled(result.onlyA.isEmpty)
                    .help("Copy the \(result.onlyA.count) files only in \(name(.a)) to \(name(.b)) on \(pair.b.driveName)")
                Spacer()
                if !result.onlyA.isEmpty, !result.onlyB.isEmpty {
                    Button("Make All Files Available in Both", systemImage: "arrow.left.arrow.right") { startCopy([.a, .b]) }
                    Spacer()
                }
                Button("Copy to \(driveName(.a))", systemImage: "arrow.left") { startCopy([.b]) }
                    .disabled(result.onlyB.isEmpty)
                    .help("Copy the \(result.onlyB.count) files only in \(name(.b)) to \(name(.a)) on \(pair.a.driveName)")
            }
        }
        if !copyFailures.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label("^[\(copyFailures.count) file](inflect: true) weren't copied", systemImage: "exclamationmark.triangle")
                ForEach(copyFailures.prefix(5), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private func legend(_ title: String, _ style: some ShapeStyle) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: "circle.fill").foregroundStyle(style)
        }
        .font(.caption)
    }

    /// A titled card of rows, divided like the duplicate cards
    private func card<Item>(_ title: LocalizedStringKey, _ items: [Item], id: KeyPath<Item, String>,
                            @ViewBuilder row: @escaping (Item) -> some View) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: id) { item in
                        if item[keyPath: id] != items[0][keyPath: id] { Divider() }
                        row(item)
                    }
                }
                .padding(4)
            }
        }
    }

    /// The files only this side has: folders first, one row each, then the loose files. With none,
    /// the trash button for this folder, when the other side has everything.
    @ViewBuilder
    private func filesList(_ side: FolderComparison.Side, _ files: [FolderComparison.File], _ listing: [String: String],
                           root: URL?) -> some View {
        if files.isEmpty {
            // The side with nothing of its own is the one that can go
            VStack(spacing: 12) {
                Text("Nothing only here")
                    .foregroundStyle(.secondary)
                if let result, !fromIndex, copying == nil, !checking, trashable(result.verdict).contains(side) {
                    let folder = side == .a ? pair.a : pair.b
                    Button("Move “\(folder.name)” to Trash", role: .destructive) {
                        onTrash(folder)
                        dismiss()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            let groups = Dictionary(grouping: files) { listing[$0.path] ?? "" }
            let folders = groups.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let entries = folders.map { ListEntry(folder: $0, files: groups[$0]!) }
                + (groups[""] ?? []).map { ListEntry(folder: "", files: [$0]) }
            card("Only here: ^[\(files.count) file](inflect: true), \(formatted(total(files)))", entries, id: \.id) { entry in
                if entry.folder.isEmpty {
                    let file = entry.files[0]
                    row(file.path, size: file.size, note: file.elsewhere.map(safeNote), at: root?.appending(path: file.path))
                } else {
                    let safe = entry.files.filter { $0.elsewhere != nil }
                    let note = safe.count == entry.files.count
                        ? safeNote(safe[0].elsewhere!)
                        : safe.isEmpty ? nil : "\(safe.count) of \(entry.files.count) files safe elsewhere"
                    row(entry.folder, isFolder: true, size: total(entry.files), note: note, at: root?.appending(path: entry.folder))
                }
            }
        }
    }

    /// A folder and its files, or one loose file
    private struct ListEntry {
        let folder: String  // "" for a loose file
        let files: [FolderComparison.File]
        var id: String { folder.isEmpty ? files[0].path : folder + "/" }
    }

    /// A copy's folder; for a folder row, the first file's copy stands for the rest
    private func safeNote(_ copy: DuplicateFile) -> String {
        "Safe elsewhere: \(copy.driveName) \((copy.relativePath as NSString).deletingLastPathComponent)/"
    }

    /// A file, or a folder of files, only one side has
    private func row(_ name: String, isFolder: Bool = false, size: Int64, note: String?, at url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label {
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.listIcon(name: (name as NSString).lastPathComponent, isDirectory: isFolder))
                }
                Spacer()
                Text(formatted(size))
                    .foregroundStyle(.secondary)
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") { reveal(url.map { [$0] }) }
                .disabled(url == nil)
        }
    }

    /// Changed files exist on both sides, so they span both columns
    @ViewBuilder
    private func changedList(_ changed: [FolderComparison.Changed]) -> some View {
        if !changed.isEmpty {
            card("Changed: ^[\(changed.count) file](inflect: true)", changed, id: \.path) { file in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(formatted(file.sizeA)) in \(name(.a)), \(formatted(file.sizeB)) in \(name(.b))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(file.newer.map { "Newer in \(name($0))" } ?? "Same date")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Reveal in Finder") { reveal(urls.map { [$0.0.appending(path: file.path), $0.1.appending(path: file.path)] }) }
                        .disabled(urls == nil)
                }
            }
        }
    }

    @ViewBuilder
    private func movedList(_ moved: [FolderComparison.Moved]) -> some View {
        if !moved.isEmpty {
            card("Moved: ^[\(moved.count) file](inflect: true)", moved, id: \.path) { move in
                let other: FolderComparison.Side = move.side == .a ? .b : .a
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(move.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("At \(move.otherPath) in \(name(other))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(formatted(move.size))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Reveal in Finder") {
                        reveal(urls.map { [(move.side == .a ? $0.0 : $0.1).appending(path: move.path)] })
                    }
                    .disabled(urls == nil)
                }
            }
        }
    }

    // MARK: - Text

    /// The drive's name, or the folder's when both folders are on the same drive
    private func driveName(_ side: FolderComparison.Side) -> String {
        pair.a.driveUUID == pair.b.driveUUID ? name(side) : (side == .a ? pair.a : pair.b).driveName
    }

    /// The folder's name, with its drive when both folders share a name
    private func name(_ side: FolderComparison.Side) -> String {
        let folder = side == .a ? pair.a : pair.b
        return pair.a.name == pair.b.name ? "\(folder.name) on \(folder.driveName)" : folder.name
    }

    private func total(_ files: [FolderComparison.File]) -> Int64 { files.reduce(0) { $0 + $1.size } }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Actions

    /// The folders that can go: the other side, when one side is complete or newer
    /// Never a drive itself, or either of two nested folders (the parent holds the other copy)
    private func trashable(_ verdict: FolderComparison.Verdict) -> [FolderComparison.Side] {
        let (a, b) = (pair.a, pair.b)
        guard !a.relativePath.isEmpty, !b.relativePath.isEmpty,
              !a.contains(driveUUID: b.driveUUID, path: b.relativePath),
              !b.contains(driveUUID: a.driveUUID, path: a.relativePath) else { return [] }
        return switch verdict {
        case .identical: [.a, .b]
        case .complete(.a): [.b]
        case .complete(.b): [.a]
        case .neither: []
        }
    }

    private func reveal(_ urls: [URL]?) {
        guard let urls else { return NSSound.beep() }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func startCopy(_ sides: [FolderComparison.Side]) {
        copyTask = Task { await copyMissing(sides) }
    }

    /// Copies the files only the given sides have to the other side, then compares again
    private func copyMissing(_ sides: [FolderComparison.Side]) async {
        guard let urls, let result else { return }
        let batches = sides.map { side in
            side == .a ? (files: result.onlyA, from: urls.0, to: urls.1) : (files: result.onlyB, from: urls.1, to: urls.0)
        }
        let all = batches.reduce(0) { $0 + total($1.files) }
        copying = (0, all)
        copyFailures = []
        var done: Int64 = 0
        do {
            for batch in batches {
                let base = done
                let failures = try await FolderComparison.copy(batch.files, from: batch.from, to: batch.to) { bytes in
                    Task { @MainActor in copying = (base + bytes, all) }
                }
                copyFailures += failures.map { "\($0.path): \($0.error.localizedDescription)" }
                done += total(batch.files)
            }
        } catch is CancellationError {
            copying = nil
            return
        } catch {
            copyFailures.append(error.localizedDescription)
        }
        copying = nil
        checking = true
        await run(reusing: result)
        checking = false
    }

    /// - Parameter earlier: kept on screen while this runs, and its hashes reused
    private func run(reusing earlier: FolderComparison? = nil) async {
        if earlier == nil { result = nil }
        errorMessage = nil
        progress = (0, 0)
        let urls = urls
        fromIndex = urls == nil
        do {
            var comparison: FolderComparison
            if let urls {
                comparison = try await FolderComparison.compare(urls.0, urls.1, reusing: earlier?.hashes ?? [:]) { files, bytes in
                    Task { @MainActor in progress = (files, bytes) }
                }
            } else {
                let database = DatabaseManager.shared
                comparison = try FolderComparison.compare(
                    index: try await database.getFolderFiles(driveUUID: pair.a.driveUUID, path: pair.a.relativePath),
                    try await database.getFolderFiles(driveUUID: pair.b.driveUUID, path: pair.b.relativePath))
            }
            try await comparison.findCopiesElsewhere(a: pair.a, b: pair.b, urls: urls)
            result = comparison
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let pair = FolderPair(a: FolderLocation(driveUUID: "D0A21232-443D-4505-BEE3-874050B79CBF", driveName: "Jesse T72", relativePath: "TRANSFER/Downloads"),
                          b: FolderLocation(driveUUID: "41F738A7-61C2-4313-823C-DAA8F78D445E", driveName: "Macintosh HD", relativePath: "Users/jmorley/Downloads/Old"))
    FolderCompareView(pair: pair) { _ in }
        .environmentObject(DriveMonitor())
}
