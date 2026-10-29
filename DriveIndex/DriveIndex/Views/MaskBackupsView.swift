//
//  MaskBackupsView.swift
//  DriveIndex
//
//  Read-only report of Capture One mask backups, one card per session, one row per image
//

import SwiftUI

struct MaskBackupsView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor

    @State private var sets: [MaskBackupSet]?
    @State private var errorMessage: String?
    @State private var pendingTrash: [MaskBackupSet]?
    @State private var trashFailures = 0

    private var connectedDriveIDs: [String] {
        driveMonitor.drives.filter(\.isConnected).map(\.id)
    }

    var body: some View {
        content
            .navigationTitle("Capture One")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await load() }
                }
                .help("Check the drives again")
            }
            // Re-runs when a drive connects or disconnects, so its backups get checked
            .task(id: connectedDriveIDs) { await load() }
            .confirmationDialog(trashTitle, isPresented: isConfirmingTrash, presenting: pendingTrash) { sets in
                Button("Move to Trash", role: .destructive) {
                    Task { await trash(sets) }
                }
            } message: { _ in
                Text("The live masks stay in place. The backups go to the Trash on their drive and are deleted when you empty it.")
            }
            .alert("Some Backups Weren't Moved", isPresented: Binding { trashFailures > 0 } set: { if !$0 { trashFailures = 0 } }) {
            } message: {
                Text("\(trashFailures) backup\(trashFailures == 1 ? "" : "s") stayed in place: the drive was disconnected, the live mask had gone, or the file couldn't be moved.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView("Couldn't Load Mask Backups", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if let sets, sets.isEmpty {
            ContentUnavailableView("No Mask Backups", systemImage: "camera.aperture", description: Text("Capture One mask backups on your indexed drives will appear here"))
        } else if let sets {
            let sessions = Dictionary(grouping: sets) { "\($0.driveUUID)/\($0.sessionPath)" }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            ScrollView {
                VStack {
                    summary(sets)
                    ForEach(sessions, id: \.key) { _, sessionSets in
                        card(sessionSets.sorted { $0.imageName.localizedStandardCompare($1.imageName) == .orderedAscending })
                    }
                }
                .padding()
            }
        } else {
            ProgressView("Finding mask backups...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func load() async {
        do {
            sets = try await MaskBackupSet.load(drives: driveMonitor.drives)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Trash

    private func safe(_ sets: [MaskBackupSet]) -> [MaskBackupSet] {
        sets.filter { $0.status == .safe }
    }

    private var isConfirmingTrash: Binding<Bool> {
        Binding { pendingTrash != nil } set: { if !$0 { pendingTrash = nil } }
    }

    private var trashTitle: String {
        let sets = pendingTrash ?? []
        let count = sets.reduce(0) { $0 + $1.backupPaths.count }
        return "Move \(count) backup\(count == 1 ? "" : "s") (\(formatted(sets.reduce(0) { $0 + $1.size }))) to the Trash?"
    }

    private func trashButton(_ sets: [MaskBackupSet], help: String) -> some View {
        Button("Move to Trash", systemImage: "trash") { pendingTrash = sets }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(help)
    }

    private func trash(_ sets: [MaskBackupSet]) async {
        var failed = 0
        for set in sets {
            guard let drive = driveMonitor.drives.first(where: { $0.id == set.driveUUID }),
                  let driveURL = driveMonitor.getDriveURL(for: drive) else {
                failed += set.backupPaths.count
                continue
            }
            let result = await set.moveToTrash(on: driveURL)
            failed += result.failed.count
            // ponytail: drop them from the index now so they don't reappear before FSEvents rescans; if this fails, that rescan catches up
            try? await DatabaseManager.shared.deleteFiles(driveUUID: set.driveUUID, relativePaths: result.trashed)
        }
        await load()
        trashFailures = failed
    }

    // MARK: - Summary

    private func summary(_ sets: [MaskBackupSet]) -> some View {
        GroupBox {
            VStack {
                ForEach(Array([MaskBackupSet.Status.safe, .hold, .unverified].enumerated()), id: \.offset) { index, status in
                    if index > 0 { Divider() }
                    summaryRow(status, sets: sets.filter { $0.status == status })
                }
            }
            .padding(4)
        }
    }

    private func summaryRow(_ status: MaskBackupSet.Status, sets: [MaskBackupSet]) -> some View {
        let count = sets.reduce(0) { $0 + $1.backupPaths.count }
        return HStack {
            Label(status.summary, systemImage: status.symbol)
                .foregroundStyle(sets.isEmpty ? .tertiary : .primary)
            Spacer()
            Text("\(count) backup\(count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Text(formatted(sets.reduce(0) { $0 + $1.size }))
            if status == .safe {
                Button("Move All to Trash") { pendingTrash = sets }
                    .disabled(sets.isEmpty)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Session cards

    private func card(_ sets: [MaskBackupSet]) -> some View {
        let drive = driveMonitor.drives.first { $0.id == sets[0].driveUUID }
        let session = sets[0].sessionPath
        return GroupBox {
            VStack {
                HStack {
                    Label {
                        Text(session.isEmpty ? "Drive root" : (session as NSString).lastPathComponent)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.listIcon(name: "CaptureOne", isDirectory: true))
                    }
                    Text((session as NSString).deletingLastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Label {
                        Text(drive?.name ?? "Unknown drive")
                            .foregroundStyle(drive?.isConnected == true ? .primary : .tertiary)
                    } icon: {
                        if let drive {
                            Image(nsImage: drive.finderIcon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                    }
                    Text(formatted(sets.reduce(0) { $0 + $1.size }))
                    Button("Open Session", systemImage: "arrow.up.forward.app") { openSession(sets[0], drive: drive) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(drive?.isConnected != true)
                        .help("Open this session in Capture One")
                    if !safe(sets).isEmpty {
                        trashButton(safe(sets), help: "Move this session's safe backups to the Trash")
                    }
                }
                // Same gap under the header as the Duplicates cards
                .padding(.bottom, 2)

                ForEach(sets) { set in
                    Divider()
                    imageRow(set, drive: drive)
                }
            }
            // GroupBox's inset sits tight against the content
            .padding(4)
        }
    }

    private func imageRow(_ set: MaskBackupSet, drive: DriveInfo?) -> some View {
        HStack {
            Label {
                Text(set.imageName)
            } icon: {
                Image(nsImage: NSWorkspace.shared.listIcon(name: set.imageName, isDirectory: false))
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Text("\(set.backupPaths.count) backup\(set.backupPaths.count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            Spacer()
            Label(set.status.detail(driveName: drive?.name ?? "the drive"), systemImage: set.status.symbol)
                .foregroundStyle(set.status.color)
            Text(formatted(set.size))
            if set.status == .safe {
                trashButton([set], help: "Move this image's backups to the Trash")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help(set.backupPaths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: "\n"))
        .onTapGesture(count: 2) { revealInFinder(set, drive: drive) }
        .contextMenu {
            Button("Reveal in Finder") { revealInFinder(set, drive: drive) }
                .disabled(drive?.isConnected != true)
            Button("Move Backups to Trash") { pendingTrash = [set] }
                .disabled(set.status != .safe)
        }
    }

    // MARK: - Actions

    private func revealInFinder(_ set: MaskBackupSet, drive: DriveInfo?) {
        guard let drive, let driveURL = driveMonitor.getDriveURL(for: drive) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting(set.backupPaths.map { driveURL.appendingPathComponent($0) })
    }

    private func openSession(_ set: MaskBackupSet, drive: DriveInfo?) {
        guard let drive, let driveURL = driveMonitor.getDriveURL(for: drive),
              let session = set.sessionFile(on: driveURL) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(session)
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension MaskBackupSet.Status {
    var summary: String {
        switch self {
        case .safe: return "Safe to remove: live mask present"
        case .hold: return "Keep: no live mask"
        case .unverified: return "Not checked: drive disconnected"
        }
    }

    func detail(driveName: String) -> String {
        switch self {
        case .safe: return "Safe"
        case .hold: return "Keep"
        case .unverified: return "Connect \(driveName)"
        }
    }

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
    MaskBackupsView()
        .environmentObject(DriveMonitor())
        .frame(width: 900, height: 700)
}
