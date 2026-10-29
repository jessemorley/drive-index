//
//  CodeReviewFindingsTests.swift
//  DriveIndexTests
//
//  Tests for the /code-review findings on gg/fix-visited-race. Findings 3, 4, 7, 8 and 10
//  depend on a real drive or a race, so they are tested by hand (see the findings doc).
//

import Foundation
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

struct DeleteFilesTests {
    // Finding 5: the walk yields a/x but fails to read folder a, so the sweep deletes a.
    // The subtree delete then removes a/x too, although this scan just visited it.
    @Test func unvisitedFolderDeleteKeepsVisitedChildren() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriveIndexTests-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let db = DatabaseManager(path: path)
        try await db.recoverDatabase()  // opens the file and creates the schema
        try await db.upsertDriveMetadata(DriveMetadata(
            uuid: "A", name: "A", lastSeen: Date(), totalCapacity: 1, usedCapacity: 0,
            lastScanDate: nil, fileCount: 0, isExcluded: false
        ))
        try await db.insertBatch([
            FileEntry(id: nil, driveUUID: "A", name: "a", relativePath: "a", size: 0,
                      createdAt: nil, modifiedAt: nil, isDirectory: true),
            FileEntry(id: nil, driveUUID: "A", name: "x", relativePath: "a/x", size: 1,
                      createdAt: nil, modifiedAt: nil, isDirectory: false)
        ])

        try await db.deleteFiles(driveUUID: "A", relativePaths: ["a"])

        let left = try await db.getExistingFiles(driveUUID: "A")
        withKnownIssue("Finding 5: deleteFiles removes the whole subtree, including visited rows") {
            #expect(left["a/x"] != nil)
        }
    }
}
