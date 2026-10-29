//
//  CaptureOne.swift
//  DriveIndex
//
//  Capture One files that can be removed without losing anything: mask backups, and Settings
//  folders left behind when a newer Capture One copied a session's settings forward
//

import Foundation

/// Whether removing something loses nothing, decided on disk. The index can't decide it: ".cos"
/// and ".comask" files are excluded from it by default.
enum CleanupStatus {
    /// Everything in it also exists in what stays
    case safe
    /// Holds something found nowhere else, so it's kept
    case hold
    /// Drive disconnected, so it can't be checked
    case unverified
}

/// A Capture One session: the folder holding its "<name>.cosessiondb"
struct CaptureOneSession: Hashable {
    let driveUUID: String
    /// Relative to the drive
    let folder: String
    let name: String
    /// The ".cosessiondb", relative to the drive. nil when the index has none above the item
    /// (a catalog, or a session file that was deleted); the folder then stands in for the session.
    let file: String?

    var id: String { "\(driveUUID)/\(folder)" }
}

enum CaptureOne {
    /// The indexed session files, keyed by "<drive>/<folder holding it>"
    static func sessionFiles() async throws -> [String: String] {
        let files = try await DatabaseManager.shared.getSessionFiles()
        return Dictionary(files.map { file in
            ("\(file.driveUUID)/\(file.path.split(separator: "/").dropLast().joined(separator: "/"))", file.path)
        }) { first, _ in first }
    }

    /// The session an item belongs to: the nearest session file at or above `shootPath`, the folder
    /// holding "CaptureOne". Sessions keep captures in subfolders ("Session/Capture/Shoot/CaptureOne"),
    /// so it's often a few levels up.
    static func session(driveUUID: String, shootPath: String, files: [String: String]) -> CaptureOneSession {
        var parts = shootPath.split(separator: "/")
        while true {
            let folder = parts.joined(separator: "/")
            if let file = files["\(driveUUID)/\(folder)"] {
                let name = (String(file.split(separator: "/").last!) as NSString).deletingPathExtension
                return CaptureOneSession(driveUUID: driveUUID, folder: folder, name: name, file: file)
            }
            if parts.isEmpty { break }
            parts.removeLast()
        }
        return CaptureOneSession(driveUUID: driveUUID, folder: shootPath, name: shootPath.split(separator: "/").last.map(String.init) ?? "Drive root", file: nil)
    }

    /// "IMG.HEIC.comask.backup" or "IMG.HEIC.comask.backup_3" → "IMG.HEIC.comask"; nil for any other name
    static func liveMaskName<S: StringProtocol>(forBackup name: S) -> Substring? {
        String(name).wholeMatch(of: /(.+\.comask)\.backup(_\d+)?/).map { $0.1 }
    }

    static func mountPaths(_ drives: [DriveInfo]) -> [String: URL] {
        Dictionary(drives.filter(\.isConnected).map { ($0.id, URL(fileURLWithPath: $0.path)) }) { first, _ in first }
    }
}

// MARK: - Mask backups

/// One image's Capture One mask backups ("IMG.HEIC.comask.backup", "...backup_3"). They all sit
/// next to the live mask "IMG.HEIC.comask" in the same "CaptureOne/Settings*" folder.
struct MaskBackupSet: Identifiable {
    let driveUUID: String
    let livePath: String
    var backupPaths: [String] = []
    var size: Int64 = 0
    var status: CleanupStatus = .unverified

    var id: String { "\(driveUUID)/\(livePath)" }

    var imageName: String {
        String(livePath.split(separator: "/").last!.dropLast(".comask".count))
    }

    /// The Settings folder holding the masks
    var settingsPath: String {
        livePath.split(separator: "/").dropLast().joined(separator: "/")
    }

    /// The folder holding "CaptureOne". Empty at the drive root.
    var shootPath: String {
        livePath.split(separator: "/").dropLast(3).joined(separator: "/")
    }

    /// The live mask a backup shadows, or nil when the path isn't a mask backup: the name must be
    /// "<image>.comask.backup" or "<image>.comask.backup_<n>", inside "CaptureOne/Settings*".
    static func livePath(for backupPath: String) -> String? {
        let parts = backupPath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3,
              parts[parts.count - 3] == "CaptureOne",
              parts[parts.count - 2].hasPrefix("Settings"),
              let live = CaptureOne.liveMaskName(forBackup: parts[parts.count - 1])
        else { return nil }
        return (parts.dropLast() + [live]).joined(separator: "/")
    }

    /// Groups the indexed mask backups by image, then checks each live mask on connected drives.
    static func load(drives: [DriveInfo]) async throws -> [MaskBackupSet] {
        var sets: [String: MaskBackupSet] = [:]
        for row in try await DatabaseManager.shared.getMaskBackups() {
            guard let live = livePath(for: row.relativePath) else { continue }
            let key = "\(row.driveUUID)/\(live)"
            sets[key, default: MaskBackupSet(driveUUID: row.driveUUID, livePath: live)].backupPaths.append(row.relativePath)
            sets[key]!.size += row.size
        }

        let mountPaths = CaptureOne.mountPaths(drives)
        return sets.values.map { set in
            var set = set
            if let drive = mountPaths[set.driveUUID] {
                set.status = set.liveMaskExists(on: drive) ? .safe : .hold
            }
            return set
        }
    }

    private func liveMaskExists(on drive: URL) -> Bool {
        let size = (try? drive.appending(path: livePath).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    /// Deletes the backups for good, checking again first: the live mask must still be
    /// there, and each backup must be a plain file (not a symlink) that maps to this live mask.
    /// The live mask itself is never touched.
    func delete(on drive: URL) async -> (deleted: [String], failed: [String]) {
        guard liveMaskExists(on: drive) else { return ([], backupPaths) }

        var deleted: [String] = []
        var failed: [String] = []
        for path in backupPaths {
            let url = drive.appending(path: path)
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            if isFile, Self.livePath(for: path) == livePath,
               (try? FileManager.default.removeItem(at: url)) != nil {
                deleted.append(path)
            } else {
                failed.append(path)
            }
        }
        return (deleted, failed)
    }
}

// MARK: - Old Settings folders

/// An older "CaptureOne/Settings<version>" folder beside a newer one. A newer Capture One copies a
/// session's settings forward the first time it opens each image, and never removes the old folder.
struct OldSettingsFolder: Identifiable {
    let driveUUID: String
    /// ".../CaptureOne/Settings1670"
    let path: String
    /// The folder(s) kept beside it ("Settings1680")
    var kept: [String] = []
    /// Unknown until the drive is connected
    var size: Int64?
    /// Files here that no kept folder has. Zero means removing it loses nothing.
    var orphans = 0
    var status: CleanupStatus = .unverified

    var id: String { "\(driveUUID)/\(path)" }
    var name: String { String(path.split(separator: "/").last!) }
    var shootPath: String { path.split(separator: "/").dropLast(2).joined(separator: "/") }
    private var captureOnePath: String { path.split(separator: "/").dropLast().joined(separator: "/") }

    /// "Settings1680" → [16, 8, 0], "Settings17" → [17]: two digits of major version, then one per
    /// component. Plain numeric order would put Settings1680 above Settings17. nil for other names.
    static func version<S: StringProtocol>(of name: S) -> [Int]? {
        guard let match = String(name).wholeMatch(of: /Settings(\d{2})(\d*)/) else { return nil }
        return [Int(match.1)!] + match.2.compactMap(\.wholeNumberValue)
    }

    /// The folders to keep: the highest version, plus any whose settings were edited more recently,
    /// in case the version reading is wrong. Keeping one too many is the safe mistake.
    static func keep(_ folders: [(name: String, modified: Date)]) -> Set<String> {
        guard let newest = folders.max(by: { version(of: $0.name)!.lexicographicallyPrecedes(version(of: $1.name)!) })
        else { return [] }
        return Set(folders.filter { $0.modified > newest.modified }.map(\.name) + [newest.name])
    }

    /// Lists the old Settings folders in every indexed "CaptureOne" folder holding more than one,
    /// and checks them on connected drives.
    static func load(drives: [DriveInfo]) async throws -> [OldSettingsFolder] {
        var groups: [String: [(driveUUID: String, path: String)]] = [:]
        for row in try await DatabaseManager.shared.getSettingsFolders() {
            let parts = row.path.split(separator: "/")
            guard parts.count >= 2, parts[parts.count - 2] == "CaptureOne", version(of: parts.last!) != nil else { continue }
            groups["\(row.driveUUID)/\(parts.dropLast().joined(separator: "/"))", default: []].append(row)
        }

        let mountPaths = CaptureOne.mountPaths(drives)
        var folders: [OldSettingsFolder] = []
        for group in groups.values where group.count > 1 {
            let driveUUID = group[0].driveUUID
            let paths = group.map(\.path)
            if let drive = mountPaths[driveUUID] {
                folders += check(paths, driveUUID: driveUUID, on: drive)
            } else {
                // Offline: only the version number is known, so the pick is provisional
                let newest = paths.max { version(of: $0.split(separator: "/").last!)!.lexicographicallyPrecedes(version(of: $1.split(separator: "/").last!)!) }!
                let newestName = String(newest.split(separator: "/").last!)
                folders += paths.filter { $0 != newest }.map { OldSettingsFolder(driveUUID: driveUUID, path: $0, kept: [newestName]) }
            }
        }
        return folders
    }

    /// Compares the Settings folders of one "CaptureOne" folder on disk and returns the ones not kept.
    static func check(_ paths: [String], driveUUID: String, on drive: URL) -> [OldSettingsFolder] {
        let listed = paths.map { (path: $0, name: String($0.split(separator: "/").last!), contents: contents(of: drive.appending(path: $0))) }
        let keepNames = keep(listed.map { ($0.name, $0.contents?.modified ?? .distantFuture) })
        let keptFiles = Set(listed.filter { keepNames.contains($0.name) }.flatMap { $0.contents?.files.keys.map { $0 } ?? [] })

        return listed.filter { !keepNames.contains($0.name) }.map { folder in
            var old = OldSettingsFolder(driveUUID: driveUUID, path: folder.path, kept: keepNames.sorted())
            guard let contents = folder.contents else {
                old.status = .hold  // unreadable: can't show it's covered
                return old
            }
            old.size = contents.files.values.reduce(0, +)
            old.orphans = contents.files.keys.filter { file in
                // A mask backup whose live mask was carried forward is disposable anyway
                !keptFiles.contains(file) && !(CaptureOne.liveMaskName(forBackup: file).map { keptFiles.contains(String($0)) } ?? false)
            }.count
            old.status = old.orphans == 0 ? .safe : .hold
            return old
        }
    }

    /// Every file in a Settings folder by relative path, with its size, and when Capture One last
    /// wrote a settings file there (the folder's own date if it has none). nil when unreadable.
    private static func contents(of folder: URL) -> (files: [String: Int64], modified: Date)? {
        guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil,
              let enumerator = FileManager.default.enumerator(atPath: folder.path) else { return nil }
        var files: [String: Int64] = [:]
        var newestSettings: Date?
        while let relative = enumerator.nextObject() as? String {
            let values = try? folder.appending(path: relative).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            files[relative] = Int64(values?.fileSize ?? 0)
            if relative.hasSuffix(".cos"), let date = values?.contentModificationDate {
                newestSettings = max(newestSettings ?? date, date)
            }
        }
        let folderDate = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
        return (files, newestSettings ?? folderDate)
    }

    /// Deletes the folder for good, after comparing it with its siblings again on disk.
    func delete(on drive: URL) async -> Bool {
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: drive.appending(path: captureOnePath).path)) ?? []
        let paths = siblings.filter { Self.version(of: $0) != nil }.map { "\(captureOnePath)/\($0)" }
        let url = drive.appending(path: path)
        guard Self.check(paths, driveUUID: driveUUID, on: drive).first(where: { $0.path == path })?.status == .safe,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false
        else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }
}

// MARK: - Session Trash

/// One entry in a Capture One session's own Trash folder ("Session/Trash"): an image deleted in
/// Capture One, or the "CaptureOne" folder holding those images' settings and previews.
struct SessionTrashItem: Identifiable {
    let driveUUID: String
    /// "Session/Trash/IMG_0490.jpeg"
    let path: String
    var isDirectory = false
    var size: Int64 = 0
    var status: CleanupStatus = .unverified

    var id: String { "\(driveUUID)/\(path)" }
    var name: String { String(path.split(separator: "/").last!) }
    /// The session folder, the one holding "Trash"
    var sessionFolder: String { path.split(separator: "/").dropLast(2).joined(separator: "/") }

    /// The top-level entry a path falls under, when it's inside the Trash folder of a session in
    /// `sessionFiles` ("<drive>/<session folder>" keys); nil otherwise.
    static func entry(driveUUID: String, path: String, sessionFiles: [String: String]) -> String? {
        let parts = path.split(separator: "/")
        for index in parts.indices.dropLast() where parts[index] == "Trash" {
            if sessionFiles["\(driveUUID)/\(parts[..<index].joined(separator: "/"))"] != nil {
                return parts[...(index + 1)].joined(separator: "/")
            }
        }
        return nil
    }

    /// The indexed contents of every session's Trash, one item per top-level entry. On connected
    /// drives sizes are measured on disk: the index skips the ".cos"/".cot"/".cop" files inside.
    static func load(drives: [DriveInfo], sessionFiles: [String: String]) async throws -> [SessionTrashItem] {
        var items: [String: SessionTrashItem] = [:]
        for row in try await DatabaseManager.shared.getTrashContents() {
            guard let entry = entry(driveUUID: row.driveUUID, path: row.path, sessionFiles: sessionFiles) else { continue }
            let key = "\(row.driveUUID)/\(entry)"
            items[key, default: SessionTrashItem(driveUUID: row.driveUUID, path: entry)].size += row.isDirectory ? 0 : row.size
            if row.path != entry || row.isDirectory { items[key]!.isDirectory = true }
        }

        let mountPaths = CaptureOne.mountPaths(drives)
        return items.values.compactMap { item in
            var item = item
            if let drive = mountPaths[item.driveUUID] {
                let url = drive.appending(path: item.path)
                // Gone from disk but still indexed: the next scan drops it
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                item.status = .safe
                if item.isDirectory { item.size = diskSize(of: url) }
            }
            return item
        }
    }

    private static func diskSize(of folder: URL) -> Int64 {
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(atPath: folder.path)
        while let relative = enumerator?.nextObject() as? String {
            total += Int64((try? folder.appending(path: relative).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Deletes the entry for good, checking first that it still sits directly in a
    /// "Trash" folder next to a session file, and isn't a symlink.
    func delete(on drive: URL) async -> Bool {
        let url = drive.appending(path: path)
        let sessionFolder = drive.appending(path: sessionFolder)
        let isSession = ((try? FileManager.default.contentsOfDirectory(atPath: sessionFolder.path)) ?? []).contains { $0.hasSuffix(".cosessiondb") }
        guard path.split(separator: "/").dropLast().last == "Trash", isSession,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false
        else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }
}
