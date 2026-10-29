//
//  MaskBackups.swift
//  DriveIndex
//
//  Capture One mask backups and whether the live mask they shadow still exists
//

import Foundation

/// One image's Capture One mask backups ("IMG.HEIC.comask.backup", "...backup_3"). They all sit
/// next to the live mask "IMG.HEIC.comask" in the same "CaptureOne/Settings*" folder.
struct MaskBackupSet: Identifiable {
    enum Status {
        /// The live mask exists on disk, so the backups duplicate it
        case safe
        /// No live mask: a backup may be the only copy, so keep them
        case hold
        /// Drive disconnected: the live mask isn't in the index, so it can't be checked
        case unverified
    }

    let driveUUID: String
    let livePath: String
    var backupPaths: [String] = []
    var size: Int64 = 0
    var status: Status = .unverified

    var id: String { "\(driveUUID)/\(livePath)" }

    var imageName: String {
        String(livePath.split(separator: "/").last!.dropLast(".comask".count))
    }

    /// The folder holding "CaptureOne", i.e. the session. Empty for a session at the drive root.
    var sessionPath: String {
        livePath.split(separator: "/").dropLast(3).joined(separator: "/")
    }

    /// The live mask a backup shadows, or nil when the path isn't a mask backup: the name must be
    /// "<image>.comask.backup" or "<image>.comask.backup_<n>", inside "CaptureOne/Settings*".
    static func livePath(for backupPath: String) -> String? {
        let parts = backupPath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              parts[parts.count - 3] == "CaptureOne",
              parts[parts.count - 2].hasPrefix("Settings"),
              let match = parts[parts.count - 1].wholeMatch(of: /(.+\.comask)\.backup(_\d+)?/)
        else { return nil }
        return (parts.dropLast() + [match.1]).joined(separator: "/")
    }

    /// Groups the indexed mask backups by image, then checks each live mask on connected drives.
    /// Read-only: nothing is moved or deleted.
    static func load(drives: [DriveInfo]) async throws -> [MaskBackupSet] {
        var sets: [String: MaskBackupSet] = [:]
        for row in try await DatabaseManager.shared.getMaskBackups() {
            guard let live = livePath(for: row.relativePath) else { continue }
            let key = "\(row.driveUUID)/\(live)"
            sets[key, default: MaskBackupSet(driveUUID: row.driveUUID, livePath: live)].backupPaths.append(row.relativePath)
            sets[key]!.size += row.size
        }

        let mountPaths = Dictionary(drives.filter(\.isConnected).map { ($0.id, $0.path) }) { first, _ in first }
        return sets.values.map { set in
            var set = set
            if let mountPath = mountPaths[set.driveUUID] {
                set.status = set.liveMaskExists(on: URL(fileURLWithPath: mountPath)) ? .safe : .hold
            }
            return set
        }
    }

    /// The nearest "<name>.cosessiondb" at or above the folder holding "CaptureOne". Sessions keep
    /// their captures in subfolders ("Session/Capture/Shoot/CaptureOne"), so it's often a few levels up.
    func sessionFile(on drive: URL) -> URL? {
        let parts = sessionPath.split(separator: "/")
        for depth in stride(from: parts.count, through: 0, by: -1) {
            let folder = drive.appending(path: parts.prefix(depth).joined(separator: "/"))
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            if let session = files.first(where: { $0.pathExtension == "cosessiondb" }) {
                return session
            }
        }
        return nil
    }

    private func liveMaskExists(on drive: URL) -> Bool {
        let size = (try? drive.appending(path: livePath).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    /// Moves the backups to the drive's Trash, checking again first: the live mask must still be
    /// there, and each backup must be a plain file (not a symlink) that maps to this live mask.
    /// The live mask itself is never touched.
    func moveToTrash(on drive: URL) async -> (trashed: [String], failed: [String]) {
        guard liveMaskExists(on: drive) else { return ([], backupPaths) }

        var trashed: [String] = []
        var failed: [String] = []
        for path in backupPaths {
            let url = drive.appending(path: path)
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            if isFile, Self.livePath(for: path) == livePath,
               (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                trashed.append(path)
            } else {
                failed.append(path)
            }
        }
        return (trashed, failed)
    }
}
