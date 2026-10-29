//
//  CodeReviewFindingsTests.swift
//  DriveIndexTests
//
//  Tests for the /code-review findings on gg/fix-visited-race. Findings 3, 4, 7, 8 and 10
//  depend on a real drive or a race, so they are tested by hand (see the findings doc).
//

import Foundation
import os
import Testing
@testable import DriveIndex

private let driveA = URL(fileURLWithPath: "/Volumes/A")
private let driveB = URL(fileURLWithPath: "/Volumes/B")

struct OwedScansTests {
    // Finding 1: a request for drive B cancels drive A's history scan. A's folders must still
    // be owed, so A's next scan covers them before it saves a later cursor.
    @Test func otherDriveRequestKeepsCancelledWork() {
        var owed = OwedScans()
        _ = owed.add(uuid: "A", url: driveA, changedPaths: ["H"], cursor: (10, "store"))
        _ = owed.add(uuid: "B", url: driveB, changedPaths: ["x"], cursor: (5, "storeB"))

        let next = owed.add(uuid: "A", url: driveA, changedPaths: ["L"], cursor: (20, "store"))
        #expect(next.changedPaths == ["H", "L"])
        #expect(next.cursor?.id == 20)
    }

    // Finding 2: at launch each drive's catch-up request cancels the previous one. Every drive
    // stays owed until its own scan finishes.
    @Test func launchCatchUpKeepsEveryDrive() {
        var owed = OwedScans()
        _ = owed.add(uuid: "A", url: driveA, changedPaths: nil, cursor: nil)
        _ = owed.add(uuid: "B", url: driveB, changedPaths: ["x"], cursor: (5, "storeB"))

        owed.remove(uuid: "B")
        #expect(owed.work.keys.sorted() == ["A"])
        #expect(owed.work["A"]?.changedPaths == nil)
    }

    // The merged scan reaches the later of both cursors, whichever request carried it
    @Test func mergeKeepsLaterCursor() {
        var owed = OwedScans()
        _ = owed.add(uuid: "A", url: driveA, changedPaths: ["H"], cursor: (30, "store"))
        let next = owed.add(uuid: "A", url: driveA, changedPaths: ["L"], cursor: (20, "store"))
        #expect(next.cursor?.id == 30)
    }

    // Finding 6 (not a bug): owed mount-scan work turns a later folder request into a mount
    // scan. Narrowing it would save a cursor past changes made while unmounted.
    @Test func owedMountScanStaysMountScan() {
        var owed = OwedScans()
        _ = owed.add(uuid: "A", url: driveA, changedPaths: nil, cursor: nil)
        let next = owed.add(uuid: "A", url: driveA, changedPaths: ["x"], cursor: (5, "store"))
        #expect(next.changedPaths == nil)
        #expect(next.cursor == nil)
    }
}

struct ExclusionTests {
    // Finding 9: a file-level path for .DS_Store is filtered, but folder-level events only
    // name the folder, which passes the filter, so a .DS_Store write still triggers a scan
    @Test func folderEventForDSStoreWritePassesFilter() {
        #expect(FSEventsMonitor.isPathExcluded("/Volumes/A/a/.DS_Store"))
        #expect(!FSEventsMonitor.isPathExcluded("/Volumes/A/a/"))
    }
}

struct SweepTests {
    // Finding 5: what the walk can't read must not be swept. Folder a can't be listed, so a/x
    // isn't reached; it must still count as visited, while a row for a removed file doesn't.
    @Test func unreadableFolderIsNotSwept() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("DriveIndexTests-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        // The walk reports /private/var paths; resolvingSymlinksInPath would give /var
        let root = URL(fileURLWithPath: String(cString: realpath(tmp.path, nil)))
        let a = root.appendingPathComponent("a")
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        fm.createFile(atPath: a.appendingPathComponent("x").path, contents: Data())
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: a.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: a.path)
            try? fm.removeItem(at: root)
        }

        let existing: [String: (id: Int64, modifiedAt: Date?)] = [
            "a": (1, nil), "a/x": (2, nil), "gone": (3, nil)
        ]
        let marked = OSAllocatedUnfairLock(initialState: Set<String>())
        let stream = AsyncStream<FileEntry> { continuation in
            FileIndexer.enumerateFiles(
                at: [root], basePath: root.path, driveUUID: "A",
                excludedDirs: [], excludedExts: [],
                cachedDirectories: nil, existingFiles: existing, directoriesFromFSEvents: nil,
                onDirectorySkipped: nil,
                onFilesMarkedVisited: { paths in marked.withLock { $0.formUnion(paths) } },
                continuation: continuation
            )
        }
        var visited = Set<String>()
        for await entry in stream { visited.insert(entry.relativePath) }
        visited.formUnion(marked.withLock { $0 })

        #expect(visited.contains("a"))
        #expect(visited.contains("a/x"))
        #expect(!visited.contains("gone"))
    }
}
