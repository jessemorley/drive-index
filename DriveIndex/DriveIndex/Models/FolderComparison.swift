//
//  FolderComparison.swift
//  DriveIndex
//
//  Is one folder a complete copy of another? Compares two folders on disk (full SHA-256), or from
//  the index when a drive is disconnected
//

import Foundation
import CryptoKit

/// A folder on a drive the app knows (every mounted volume is in DriveMonitor.drives)
struct FolderLocation: Hashable {
    let driveUUID: String
    let driveName: String
    let relativePath: String  // "" for the drive itself

    /// The folder at a URL, on the mounted drive whose path is its longest prefix ("/" for this Mac)
    init?(url: URL, drives: [DriveInfo]) {
        let path = url.standardizedFileURL.path
        let drive = drives
            .filter { $0.isConnected && ($0.path == "/" || path == $0.path || path.hasPrefix($0.path + "/")) }
            .max { $0.path.count < $1.path.count }
        guard let drive else { return nil }
        self.init(driveUUID: drive.id, driveName: drive.name,
                  relativePath: String(path.dropFirst(drive.path.count).drop { $0 == "/" }))
    }

    init(driveUUID: String, driveName: String, relativePath: String) {
        self.driveUUID = driveUUID
        self.driveName = driveName
        self.relativePath = relativePath
    }

    var name: String { relativePath.isEmpty ? driveName : (relativePath as NSString).lastPathComponent }

    /// Whether a path on a drive is this folder or inside it
    func contains(driveUUID: String, path: String) -> Bool {
        driveUUID == self.driveUUID && (relativePath.isEmpty || path == relativePath || path.hasPrefix(relativePath + "/"))
    }

    /// On disk, when its drive is connected
    func url(in drives: [DriveInfo]) -> URL? {
        drives.first { $0.id == driveUUID && $0.isConnected }
            .map { URL(filePath: $0.path).appending(path: relativePath) }
    }
}

struct FolderComparison {
    enum Side { case a, b }

    enum Verdict: Equatable {
        case identical
        /// This side has everything the other has; changed files, if any, are all newer here
        case complete(Side)
        case neither
    }

    struct File {
        let path: String  // relative to its folder
        let size: Int64
        let modified: Date?
        /// From the index only: HashWorker's partial hash, nil under the duplicate size setting
        var hash: String? = nil
        /// A copy outside both folders, found in the index
        var elsewhere: DuplicateFile? = nil
    }

    struct Changed {
        let path: String
        let sizeA: Int64
        let sizeB: Int64
        let newer: Side?  // nil: same modified date
        var modifiedA: Date? = nil
        var modifiedB: Date? = nil
    }

    /// Content one side has at a path the other side has it at a different path
    struct Moved {
        let side: Side
        let path: String
        let otherPath: String
        let size: Int64
    }

    var both: [File] = []   // same path, same content
    var onlyA: [File] = []  // content B has nowhere
    var onlyB: [File] = []
    var changed: [Changed] = []
    var moved: [Moved] = []
    /// On disk: each hashed file's SHA-256, keyed by its path, size and modified date
    var hashes: [String: String] = [:]

    /// Where to list each file only one side has: under the highest folder the other side doesn't
    /// have at all, else under its own folder ("" at the top level). Keyed by path.
    func listingFolders() -> (a: [String: String], b: [String: String]) {
        func parent(_ path: String) -> String { (path as NSString).deletingLastPathComponent }
        func folders(_ side: Side) -> Set<String> {
            let only = side == .a ? onlyA : onlyB
            let paths = both.map(\.path) + changed.map(\.path) + only.map(\.path)
                + moved.map { $0.side == side ? $0.path : $0.otherPath }
            var folders: Set<String> = []
            for path in paths {
                var folder = parent(path)
                while !folder.isEmpty, folders.insert(folder).inserted { folder = parent(folder) }
            }
            return folders
        }
        func listing(_ files: [File], otherFolders: Set<String>) -> [String: String] {
            Dictionary(files.map { file in
                var folder = ""
                for name in parent(file.path).split(separator: "/") {
                    folder = folder.isEmpty ? String(name) : "\(folder)/\(name)"
                    if !otherFolders.contains(folder) { break }
                }
                return (file.path, folder)
            }) { first, _ in first }
        }
        return (listing(onlyA, otherFolders: folders(.b)), listing(onlyB, otherFolders: folders(.a)))
    }

    /// For two copies of a Capture One session (each with a "<name>.cosessiondb" at its top): the
    /// latest modified date on each side among the files that differ. The session database and
    /// CaptureOne/Cache are left out, since just opening a session touches them. nil when either
    /// folder isn't a session.
    func sessionEdits() -> (a: Date?, b: Date?)? {
        func isSessionPath(_ path: String) -> Bool { !path.contains("/") && path.hasSuffix(".cosessiondb") }
        let shared = both.map(\.path) + changed.map(\.path)
        guard (shared + onlyA.map(\.path)).contains(where: isSessionPath),
              (shared + onlyB.map(\.path)).contains(where: isSessionPath) else { return nil }

        func counts(_ path: String) -> Bool { !path.contains(".cosessiondb") && !path.contains("CaptureOne/Cache/") }
        func latest(_ dates: [Date?]) -> Date? { dates.compactMap { $0 }.max() }
        let edited = changed.filter { counts($0.path) }
        return (latest(edited.map(\.modifiedA) + onlyA.filter { counts($0.path) }.map(\.modified)),
                latest(edited.map(\.modifiedB) + onlyB.filter { counts($0.path) }.map(\.modified)))
    }

    var verdict: Verdict {
        let aHasAll = onlyB.isEmpty && changed.allSatisfy { $0.newer == .a }
        let bHasAll = onlyA.isEmpty && changed.allSatisfy { $0.newer == .b }
        switch (aHasAll, bHasAll) {
        case (true, true): return .identical  // nothing changed
        case (true, false): return .complete(.a)
        case (false, true): return .complete(.b)
        case (false, false): return .neither
        }
    }
}

extension FolderComparison {
    /// - Parameter content: equal for files with the same content; only asked of files whose sizes match
    static func compare(_ a: [String: File], _ b: [String: File], content: (Side, File) throws -> String) throws -> FolderComparison {
        func isJunk(_ path: String) -> Bool {
            let name = (path as NSString).lastPathComponent
            return name == ".DS_Store" || name == "Icon\r" || name.hasPrefix("._")
        }
        let a = a.filter { !isJunk($0.key) }, b = b.filter { !isJunk($0.key) }
        var result = FolderComparison()

        for path in Set(a.keys).intersection(b.keys).sorted() {
            try Task.checkCancellation()
            let (fileA, fileB) = (a[path]!, b[path]!)
            if fileA.size == fileB.size, try content(.a, fileA) == content(.b, fileB) {
                result.both.append(fileA)
            } else {
                let newer: Side? = switch (fileA.modified, fileB.modified) {
                case let (ma?, mb?) where ma > mb: .a
                case let (ma?, mb?) where mb > ma: .b
                default: nil
                }
                result.changed.append(Changed(path: path, sizeA: fileA.size, sizeB: fileB.size, newer: newer,
                                              modifiedA: fileA.modified, modifiedB: fileB.modified))
            }
        }

        for (side, x, y) in [(Side.a, a, b), (Side.b, b, a)] {
            let other: Side = side == .a ? .b : .a
            let bySize = Dictionary(grouping: y.values, by: \.size)
            for path in Set(x.keys).subtracting(y.keys).sorted() {
                try Task.checkCancellation()
                let file = x[path]!
                var match: File?
                if let candidates = bySize[file.size] {
                    let key = try content(side, file)
                    match = try candidates.first { try content(other, $0) == key }
                }
                if let match {
                    // A rename shows up from both sides; list it once
                    if !result.moved.contains(where: { $0.path == match.path && $0.otherPath == path }) {
                        result.moved.append(Moved(side: side, path: path, otherPath: match.path, size: file.size))
                    }
                } else if side == .a {
                    result.onlyA.append(file)
                } else {
                    result.onlyB.append(file)
                }
            }
        }
        return result
    }

    /// On disk. Files are hashed in full, and only when another file's size matches.
    /// - Parameters:
    ///   - known: hashes from an earlier run; a file whose path, size and modified date are
    ///     unchanged isn't hashed again
    ///   - progress: files found, bytes hashed so far
    static func compare(_ a: URL, _ b: URL, reusing known: [String: String] = [:],
                        progress: @escaping @Sendable (Int, Int64) -> Void = { _, _ in }) async throws -> FolderComparison {
        let filesA = try walk(a), filesB = try walk(b)
        let count = filesA.count + filesB.count
        progress(count, 0)

        var hashes = known
        var hashed: Int64 = 0
        var result = try compare(filesA, filesB) { side, file in
            let url = (side == .a ? a : b).appending(path: file.path)
            let key = "\(url.path)\t\(file.size)\t\(file.modified?.timeIntervalSince1970 ?? 0)"
            if let hash = hashes[key] { return hash }
            let hash = try sha256(url)
            hashes[key] = hash
            hashed += file.size
            progress(count, hashed)
            return hash
        }
        result.hashes = hashes
        return result
    }

    /// From the index. Files too small to be hashed there match by name and size.
    static func compare(index a: [File], _ b: [File]) throws -> FolderComparison {
        try compare(Dictionary(a.map { ($0.path, $0) }) { first, _ in first },
                    Dictionary(b.map { ($0.path, $0) }) { first, _ in first }) { _, file in
            file.hash ?? "\((file.path as NSString).lastPathComponent)\t\(file.size)"
        }
    }

    /// Every regular file under a folder (symlinks aren't). An unreadable folder fails the walk:
    /// files skipped silently could make the other copy look safe to trash.
    static func walk(_ root: URL) throws -> [String: File] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var walkError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                              options: .producesRelativePathURLs,
                                                              errorHandler: { _, error in walkError = error; return false }) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
        }
        var files: [String: File] = [:]
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let path = url.relativePath
            files[path] = File(path: path, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate)
        }
        if let walkError { throw walkError }
        return files
    }

    /// Copies files only one side has to the other, at the same paths, keeping their dates. Never
    /// overwrites: a file that has appeared at the destination since the comparison is left alone
    /// and reported. Checks free space first; cancelling stops between files.
    /// - Parameter progress: bytes copied so far
    /// - Returns: the files that weren't copied, and why
    static func copy(_ files: [File], from source: URL, to destination: URL,
                     progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> [(path: String, error: Error)] {
        try checkSpace(for: files.reduce(0) { $0 + $1.size }, on: destination)

        var failures: [(path: String, error: Error)] = []
        var copied: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            let target = destination.appending(path: file.path)
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source.appending(path: file.path), to: target)  // fails if target exists
                copied += file.size
                progress(copied)
            } catch {
                failures.append((file.path, error))
            }
        }
        return failures
    }

    private static func checkSpace(for bytes: Int64, on destination: URL) throws {
        let values = try destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let free = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init), free < bytes {
            throw CocoaError(.fileWriteOutOfSpace, userInfo: [NSFilePathErrorKey: destination.path])
        }
    }

    /// What mirroring one side onto the other does to the destination
    struct MirrorPlan {
        var replace: [String] = []  // changed files: the destination's copy goes, the source's comes in
        var remove: [String] = []   // only on the destination, or there at a different path
        var add: [File] = []        // only on the source, or there at a different path
        var replacingNewer = 0      // changed files that are newer on the destination
    }

    func mirrorPlan(from side: Side) -> MirrorPlan {
        var plan = MirrorPlan()
        plan.replace = changed.map(\.path)
        plan.replacingNewer = changed.filter { $0.newer != nil && $0.newer != side }.count
        plan.remove = (side == .a ? onlyB : onlyA).map(\.path)
        plan.add = side == .a ? onlyA : onlyB
        for move in moved {
            let (sourcePath, destinationPath) = move.side == side ? (move.path, move.otherPath) : (move.otherPath, move.path)
            plan.remove.append(destinationPath)
            plan.add.append(File(path: sourcePath, size: move.size, modified: nil))
        }
        return plan
    }

    /// Makes the destination folder match the source, like `rsync --delete` with a backup folder:
    /// the destination's changed files and extras go to the Trash first, then the source's
    /// versions and missing files are copied in, keeping their dates. Checks free space first;
    /// cancelling stops between files.
    /// - Parameters:
    ///   - remove: how a destination file is set aside (the Trash; tests delete)
    ///   - progress: bytes copied so far
    /// - Returns: the files that weren't removed or copied, and why
    static func mirror(_ plan: MirrorPlan, from source: URL, to destination: URL,
                       remove: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                       progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> [(path: String, error: Error)] {
        let replaced = plan.replace.map { File(path: $0, size: (try? source.appending(path: $0).resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0, modified: nil) }
        let incoming = plan.add + replaced
        try checkSpace(for: incoming.reduce(0) { $0 + $1.size }, on: destination)

        var failures: [(path: String, error: Error)] = []
        var kept: Set<String> = []  // couldn't be set aside, so nothing is copied over them
        for path in plan.replace + plan.remove {
            try Task.checkCancellation()
            do {
                try remove(destination.appending(path: path))
            } catch {
                failures.append((path, error))
                kept.insert(path)
            }
        }
        failures += try await copy(incoming.filter { !kept.contains($0.path) }, from: source, to: destination, progress: progress)
        return failures
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Notes a copy elsewhere in the index for each file only one side has. The index holds
    /// HashWorker's partial hash, so files on disk are hashed the same way. Files under the
    /// duplicate size setting aren't hashed in the index, so those match by name and size, as
    /// folder duplicates do. A note only: the verdict never depends on it.
    /// - Parameter urls: the folders on disk; nil from the index
    mutating func findCopiesElsewhere(a: FolderLocation, b: FolderLocation, urls: (URL, URL)?) async throws {
        let database = DatabaseManager.shared
        let minSize = Int64(try await database.getSetting("min_duplicate_file_size") ?? "") ?? 5_242_880
        for side in [Side.a, .b] {
            var files = side == .a ? onlyA : onlyB
            let root = side == .a ? urls?.0 : urls?.1
            for i in files.indices {
                try Task.checkCancellation()
                let file = files[i]
                let copies: [DuplicateFile]
                if file.size < minSize {
                    copies = try await database.getFiles(name: (file.path as NSString).lastPathComponent, size: file.size)
                } else if let hash = try root.map({ try HashWorker.computeHashPositioned(fileURL: $0.appending(path: file.path), fileSize: file.size) }) ?? file.hash {
                    copies = try await database.getDuplicateFilesByHash(hash: hash)
                } else {
                    continue
                }
                files[i].elsewhere = copies.first { copy in
                    ![a, b].contains { $0.contains(driveUUID: copy.driveUUID, path: copy.relativePath) }
                }
            }
            if side == .a { onlyA = files } else { onlyB = files }
        }
    }
}
