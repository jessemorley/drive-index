//
//  FolderCompareView.swift
//  DriveIndex
//
//  Sheet comparing two folders: which one is the complete or newer copy, where the files only one
//  side has live, and the lists of what differs
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
        Form {
            Section {
                LabeledContent(pair.a.driveName, value: pair.a.relativePath)
                LabeledContent(pair.b.driveName, value: pair.b.relativePath)
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                }
            } else if let result {
                summary(result)
                strip(result)
                filesSection("Only in \(name(.a))", result.onlyA, root: urls?.0)
                filesSection("Only in \(name(.b))", result.onlyB, root: urls?.1)
                changedSection(result.changed)
                movedSection(result.moved)
            } else {
                Section {
                    LabeledContent {
                        ProgressView().controlSize(.small)
                    } label: {
                        Text("Comparing…")
                        Text("\(progress.files) files, \(formatted(progress.bytes)) hashed")
                            .monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 600, idealWidth: 680, minHeight: 480, idealHeight: 640)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(result == nil && errorMessage == nil ? "Cancel" : "Done") { dismiss() }
            }
            if let result, !fromIndex {
                ForEach(trashable(result.verdict), id: \.self) { side in
                    let folder = side == .a ? pair.a : pair.b
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Move “\(folder.name)” to Trash", role: .destructive) {
                            onTrash(folder)
                            dismiss()
                        }
                    }
                }
            }
        }
        .task(id: connected) { await run() }
    }

    // MARK: - Sections

    private func summary(_ result: FolderComparison) -> some View {
        Section {
            Label {
                Text(verdictText(result))
            } icon: {
                Image(systemName: result.verdict == .neither ? "arrow.left.arrow.right" : "checkmark.circle")
            }
            ForEach([FolderComparison.Side.a, .b], id: \.self) { side in
                let files = side == .a ? result.onlyA : result.onlyB
                if !files.isEmpty, files.allSatisfy({ $0.elsewhere != nil }) {
                    Text("Everything only in \(name(side)) is safe elsewhere")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if fromIndex {
                let offline = [pair.a, pair.b].filter { $0.url(in: driveMonitor.drives) == nil }.map(\.driveName)
                Text("From the index. Connect \(offline.joined(separator: " and ")) to compare on disk. The index skips Capture One sidecars and can be out of date.")
            }
        }
    }

    private struct StripRow: Identifiable {
        var id: String
        var onlyA: Int64 = 0
        var both: Int64 = 0
        var onlyB: Int64 = 0
    }

    /// One bar for the whole pair, then the size only on each side per top-level subfolder; those
    /// entirely in both share one row
    private func strip(_ result: FolderComparison) -> some View {
        var rows: [String: StripRow] = [:]
        func top(_ path: String) -> String { path.contains("/") ? String(path.prefix { $0 != "/" }) : "" }
        for file in result.onlyA { rows[top(file.path), default: StripRow(id: top(file.path))].onlyA += file.size }
        for file in result.onlyB { rows[top(file.path), default: StripRow(id: top(file.path))].onlyB += file.size }
        for file in result.both { rows[top(file.path), default: StripRow(id: top(file.path))].both += file.size }
        for move in result.moved { rows[top(move.path), default: StripRow(id: top(move.path))].both += move.size }

        let inBoth = rows.values.filter { $0.onlyA == 0 && $0.onlyB == 0 }
        // Folders by name, loose files last
        var shown = rows.values.filter { $0.onlyA > 0 || $0.onlyB > 0 }
            .sorted { ($0.id.isEmpty ? 1 : 0, $0.id.lowercased()) < ($1.id.isEmpty ? 1 : 0, $1.id.lowercased()) }
        if inBoth.count == 1 {
            shown.append(inBoth[0])
        } else if !inBoth.isEmpty {
            shown.append(StripRow(id: "\(inBoth.count) folders, all in both", both: inBoth.reduce(0) { $0 + $1.both }))
        }

        // By file count; changed files are neither shared nor on one side only
        let shared = result.both.count + result.moved.count
        let counts = (onlyA: result.onlyA.count, shared: shared, onlyB: result.onlyB.count)
        let fileTotal = max(counts.onlyA + counts.shared + counts.onlyB, 1)
        func percent(_ n: Int) -> String {
            (Double(n) / Double(fileTotal)).formatted(.percent.precision(.fractionLength(0...1)))
        }

        return Section("Availability") {
            VStack(alignment: .leading) {
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
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Folder")
                    Text("Only in \(name(.a))").gridColumnAlignment(.trailing)
                    Text("Only in \(name(.b))").gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(shown) { row in
                    GridRow {
                        Text(row.id.isEmpty ? "Loose files" : row.id)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.onlyA > 0 ? formatted(row.onlyA) : "")
                        Text(row.onlyB > 0 ? formatted(row.onlyB) : "")
                    }
                }
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

    /// Folders first (by top-level subfolder, expandable), then the loose files
    @ViewBuilder
    private func filesSection(_ title: String, _ files: [FolderComparison.File], root: URL?) -> some View {
        if !files.isEmpty {
            let groups = Dictionary(grouping: files) { $0.path.contains("/") ? String($0.path.prefix { $0 != "/" }) : "" }
            let folders = groups.keys.filter { !$0.isEmpty }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            Section("\(title): ^[\(files.count) file](inflect: true), \(formatted(total(files)))") {
                ForEach(folders, id: \.self) { folder in
                    let contents = groups[folder]!
                    DisclosureGroup {
                        ForEach(contents, id: \.path) { fileRow($0, label: String($0.path.dropFirst(folder.count + 1)), root: root) }
                    } label: {
                        LabeledContent {
                            Text("^[\(contents.count) file](inflect: true), \(formatted(total(contents)))")
                        } label: {
                            Label {
                                Text(folder)
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.listIcon(name: folder, isDirectory: true))
                            }
                        }
                    }
                }
                ForEach(groups[""] ?? [], id: \.path) { fileRow($0, label: $0.path, root: root) }
            }
        }
    }

    private func fileRow(_ file: FolderComparison.File, label: String, root: URL?) -> some View {
        LabeledContent {
            Text(formatted(file.size))
        } label: {
            Text(label)
            if let copy = file.elsewhere {
                Text("Safe elsewhere: \(copy.driveName) \((copy.relativePath as NSString).deletingLastPathComponent)/")
            }
        }
        .contextMenu {
            Button("Reveal in Finder") { reveal(root.map { [$0.appending(path: file.path)] }) }
                .disabled(root == nil)
        }
    }

    @ViewBuilder
    private func changedSection(_ changed: [FolderComparison.Changed]) -> some View {
        if !changed.isEmpty {
            Section("Changed: ^[\(changed.count) file](inflect: true)") {
                ForEach(changed, id: \.path) { file in
                    LabeledContent {
                        Text(file.newer.map { "Newer in \(name($0))" } ?? "Same date")
                    } label: {
                        Text(file.path)
                        Text("\(formatted(file.sizeA)) in \(name(.a)), \(formatted(file.sizeB)) in \(name(.b))")
                    }
                    .contextMenu {
                        Button("Reveal in Finder") { reveal(urls.map { [$0.0.appending(path: file.path), $0.1.appending(path: file.path)] }) }
                            .disabled(urls == nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func movedSection(_ moved: [FolderComparison.Moved]) -> some View {
        if !moved.isEmpty {
            Section("Moved: ^[\(moved.count) file](inflect: true)") {
                ForEach(moved, id: \.path) { move in
                    let other: FolderComparison.Side = move.side == .a ? .b : .a
                    LabeledContent {
                        Text(formatted(move.size))
                    } label: {
                        Text(move.path)
                        Text("At \(move.otherPath) in \(name(other))")
                    }
                    .contextMenu {
                        Button("Reveal in Finder") {
                            reveal(urls.map { [(move.side == .a ? $0.0 : $0.1).appending(path: move.path)] })
                        }
                        .disabled(urls == nil)
                    }
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
