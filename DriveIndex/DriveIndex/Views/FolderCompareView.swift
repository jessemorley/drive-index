//
//  FolderCompareView.swift
//  DriveIndex
//
//  Sheet comparing two folders: which one is the complete or newer copy, how many files are
//  shared, and side by side, the files only each side has
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

    private var urls: (URL, URL)? {
        guard let a = pair.a.url(in: driveMonitor.drives), let b = pair.b.url(in: driveMonitor.drives) else { return nil }
        return (a, b)
    }

    /// Reruns on disk when a drive connects
    private var connected: [Bool] {
        [pair.a, pair.b].map { $0.url(in: driveMonitor.drives) != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                columns { header($0) }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                } else if let result {
                    summary(result)
                    let listing = result.listingFolders()
                    columns { side in
                        filesList(side == .a ? result.onlyA : result.onlyB, side == .a ? listing.a : listing.b,
                                  root: side == .a ? urls?.0 : urls?.1)
                    }
                    changedList(result.changed)
                    movedList(result.moved)
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Comparing… \(progress.files) files, \(formatted(progress.bytes)) hashed")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 480, idealHeight: 680)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(result == nil && errorMessage == nil ? "Cancel" : "Done") { dismiss() }
            }
        }
        .task(id: connected) { await run() }
    }

    // MARK: - Sections

    /// Side A on the left, side B on the right, equal widths
    private func columns(@ViewBuilder _ content: (FolderComparison.Side) -> some View) -> some View {
        HStack(alignment: .top, spacing: 16) {
            content(.a).frame(maxWidth: .infinity, alignment: .topLeading)
            content(.b).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// The drive, the folder, and the trash button when this side is the one that can go
    private func header(_ side: FolderComparison.Side) -> some View {
        let folder = side == .a ? pair.a : pair.b
        let drive = driveMonitor.drives.first { $0.id == folder.driveUUID }
        return VStack(spacing: 6) {
            if let drive {
                Image(nsImage: drive.finderIcon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }
            Text(folder.driveName)
                .font(.headline)
            Text(folder.relativePath.isEmpty ? "/" : folder.relativePath)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let result, !fromIndex, trashable(result.verdict).contains(side) {
                Button("Move “\(folder.name)” to Trash", role: .destructive) {
                    onTrash(folder)
                    dismiss()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Verdict, the safe-elsewhere lines and the availability bar, full width
    private func summary(_ result: FolderComparison) -> some View {
        // By file count; changed files are neither shared nor on one side only
        let counts = (onlyA: result.onlyA.count, shared: result.both.count + result.moved.count, onlyB: result.onlyB.count)
        let fileTotal = max(counts.onlyA + counts.shared + counts.onlyB, 1)
        func percent(_ n: Int) -> String {
            (Double(n) / Double(fileTotal)).formatted(.percent.precision(.fractionLength(0...1)))
        }

        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verdictText(result))
            } icon: {
                Image(systemName: result.verdict == .neither ? "arrow.left.arrow.right" : "checkmark.circle")
            }
            .font(.headline)
            ForEach([FolderComparison.Side.a, .b], id: \.self) { side in
                let files = side == .a ? result.onlyA : result.onlyB
                if !files.isEmpty, files.allSatisfy({ $0.elsewhere != nil }) {
                    Text("Everything only in \(name(side)) is safe elsewhere")
                        .foregroundStyle(.secondary)
                }
            }
            if fromIndex {
                let offline = [pair.a, pair.b].filter { $0.url(in: driveMonitor.drives) == nil }.map(\.driveName)
                Text("From the index. Connect \(offline.joined(separator: " and ")) to compare on disk. The index skips Capture One sidecars and can be out of date.")
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let scale = geometry.size.width / CGFloat(fileTotal)
                HStack(spacing: 0) {
                    Rectangle().fill(.blue).frame(width: CGFloat(counts.onlyA) * scale)
                    Rectangle().fill(.tertiary).frame(width: CGFloat(counts.shared) * scale)
                    Rectangle().fill(.orange).frame(width: CGFloat(counts.onlyB) * scale)
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            HStack {
                legend("Only in \(name(.a)): \(percent(counts.onlyA))", .blue)
                Spacer()
                legend("Shared: \(percent(counts.shared))", .tertiary)
                Spacer()
                legend("Only in \(name(.b)): \(percent(counts.onlyB))", .orange)
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

    /// The files only this side has: folders first (expandable), then the loose files
    @ViewBuilder
    private func filesList(_ files: [FolderComparison.File], _ listing: [String: String], root: URL?) -> some View {
        if files.isEmpty {
            Text("Nothing only here")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        } else {
            let groups = Dictionary(grouping: files) { listing[$0.path] ?? "" }
            let folders = groups.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let entries = folders.map { ListEntry(folder: $0, files: groups[$0]!) }
                + (groups[""] ?? []).map { ListEntry(folder: "", files: [$0]) }
            card("Only here: ^[\(files.count) file](inflect: true), \(formatted(total(files)))", entries, id: \.id) { entry in
                if entry.folder.isEmpty {
                    fileRow(entry.files[0], label: entry.files[0].path, root: root)
                } else {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(entry.files, id: \.path) { fileRow($0, label: String($0.path.dropFirst(entry.folder.count + 1)), root: root) }
                        }
                        .padding(.top, 4)
                    } label: {
                        HStack {
                            Label {
                                Text(entry.folder)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.listIcon(name: (entry.folder as NSString).lastPathComponent, isDirectory: true))
                            }
                            Spacer()
                            Text(formatted(total(entry.files)))
                                .foregroundStyle(.secondary)
                        }
                    }
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

    private func fileRow(_ file: FolderComparison.File, label: String, root: URL?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(formatted(file.size))
                    .foregroundStyle(.secondary)
            }
            if let copy = file.elsewhere {
                Text("Safe elsewhere: \(copy.driveName) \((copy.relativePath as NSString).deletingLastPathComponent)/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") { reveal(root.map { [$0.appending(path: file.path)] }) }
                .disabled(root == nil)
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

    /// The folder's name, with its drive when both folders share a name
    private func name(_ side: FolderComparison.Side) -> String {
        let folder = side == .a ? pair.a : pair.b
        return pair.a.name == pair.b.name ? "\(folder.name) on \(folder.driveName)" : folder.name
    }

    private func verdictText(_ result: FolderComparison) -> String {
        switch result.verdict {
        case .identical:
            return "\(name(.a)) and \(name(.b)) have the same files"
                + (result.moved.isEmpty ? "" : ", \(result.moved.count) in different places")
        case .complete(let side):
            let other: FolderComparison.Side = side == .a ? .b : .a
            let extra = total(side == .a ? result.onlyA : result.onlyB)
            let more = extra > 0 ? ", plus \(formatted(extra)) more" : ""
            return result.changed.isEmpty
                ? "\(name(side)) has everything in \(name(other))\(more)"
                : "\(name(side)) is the newer copy: everything in \(name(other)), \(result.changed.count) newer edits\(more)"
        case .neither:
            return result.onlyA.isEmpty && result.onlyB.isEmpty
                ? "Each copy has newer edits the other lacks"
                : "Neither copy has everything the other has"
        }
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

    private func run() async {
        result = nil
        errorMessage = nil
        progress = (0, 0)
        let urls = urls
        fromIndex = urls == nil
        do {
            var comparison: FolderComparison
            if let urls {
                comparison = try await FolderComparison.compare(urls.0, urls.1) { files, bytes in
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
