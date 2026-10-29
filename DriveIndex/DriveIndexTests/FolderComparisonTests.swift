//
//  FolderComparisonTests.swift
//  DriveIndexTests
//
//  Which folder of a pair is the complete or newer copy, compared on disk
//

import Foundation
import Testing
@testable import DriveIndex

/// Two scratch folders, A and B, under one temporary directory removed afterwards
private struct Pair {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    var a: URL { root.appending(path: "A") }
    var b: URL { root.appending(path: "B") }

    /// Writes a file whose content is its text, modified at the given date
    func write(_ folder: URL, _ path: String, _ text: String, modified: Date = .distantPast) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func compare() async throws -> FolderComparison {
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        return try await FolderComparison.compare(a, b)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

struct FolderComparisonTests {
    @Test func supersetIsComplete() async throws {
        let pair = Pair()
        defer { pair.remove() }
        try pair.write(pair.a, "Images/a.jpg", "a")
        try pair.write(pair.b, "Images/a.jpg", "a")
        try pair.write(pair.a, "Archives/extra.zip", "extra")
        try pair.write(pair.a, ".DS_Store", "junk")  // skipped

        let result = try await pair.compare()
        #expect(result.verdict == .complete(.a))
        #expect(result.both.map(\.path) == ["Images/a.jpg"])
        #expect(result.onlyA.map(\.path) == ["Archives/extra.zip"])
    }

    @Test func newerEditsMakeTheNewerCopy() async throws {
        let pair = Pair()
        defer { pair.remove() }
        try pair.write(pair.a, "doc.txt", "old", modified: Date(timeIntervalSince1970: 1_000))
        try pair.write(pair.b, "doc.txt", "new edit", modified: Date(timeIntervalSince1970: 2_000))

        let result = try await pair.compare()
        #expect(result.changed.map(\.newer) == [.b])
        #expect(result.verdict == .complete(.b))
    }

    @Test func editsNewerOnBothSidesGiveNoVerdict() async throws {
        let pair = Pair()
        defer { pair.remove() }
        let (early, late) = (Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 2_000))
        try pair.write(pair.a, "one.txt", "a1", modified: late)  // same size, different content
        try pair.write(pair.b, "one.txt", "b1", modified: early)
        try pair.write(pair.a, "two.txt", "a2", modified: early)
        try pair.write(pair.b, "two.txt", "b2", modified: late)

        let result = try await pair.compare()
        #expect(result.changed.count == 2)
        #expect(result.verdict == .neither)
    }

    @Test func renamedFileIsMoved() async throws {
        let pair = Pair()
        defer { pair.remove() }
        try pair.write(pair.a, "Photos/IMG_1.jpg", "pixels")
        try pair.write(pair.b, "Photos/renamed.jpg", "pixels")

        let result = try await pair.compare()
        #expect(result.onlyA.isEmpty && result.onlyB.isEmpty)
        #expect(result.moved.map(\.path) == ["Photos/IMG_1.jpg"])
        #expect(result.moved.map(\.otherPath) == ["Photos/renamed.jpg"])
        #expect(result.verdict == .identical)
    }

    /// Listed under the highest folder the other side lacks, else under the file's own folder
    @Test func listedUnderHighestMissingFolder() async throws {
        let pair = Pair()
        defer { pair.remove() }
        try pair.write(pair.a, "Images/shared.jpg", "shared")
        try pair.write(pair.b, "Images/shared.jpg", "shared")
        try pair.write(pair.b, "Images/Photocopy-Textures/Set 1/t1.jpg", "t1")
        try pair.write(pair.b, "Images/Photocopy-Textures/t2.jpg", "t2")
        try pair.write(pair.b, "Images/loose.jpg", "loose")
        try pair.write(pair.a, "top.zip", "top")

        let listing = try await pair.compare().listingFolders()
        #expect(listing.b == ["Images/Photocopy-Textures/Set 1/t1.jpg": "Images/Photocopy-Textures",
                              "Images/Photocopy-Textures/t2.jpg": "Images/Photocopy-Textures",
                              "Images/loose.jpg": "Images"])
        #expect(listing.a == ["top.zip": ""])
    }

    /// Copying both ways fills the gaps; nothing already at the destination is overwritten
    @Test func copyFillsGapsWithoutOverwriting() async throws {
        let pair = Pair()
        defer { pair.remove() }
        let date = Date(timeIntervalSince1970: 1_000_000)
        try pair.write(pair.a, "shared.txt", "shared")
        try pair.write(pair.b, "shared.txt", "shared")
        try pair.write(pair.a, "Archives/only-a.zip", "a", modified: date)
        try pair.write(pair.b, "Images/Textures/only-b.jpg", "b", modified: date)

        let before = try await pair.compare()
        // Appeared at the destination after the comparison: must survive
        try pair.write(pair.a, "Images/Textures/only-b.jpg", "newer, keep me")

        let toB = try await FolderComparison.copy(before.onlyA, from: pair.a, to: pair.b)
        let toA = try await FolderComparison.copy(before.onlyB, from: pair.b, to: pair.a)
        #expect(toB.isEmpty)
        #expect(toA.map(\.path) == ["Images/Textures/only-b.jpg"])
        #expect(try String(contentsOf: pair.a.appending(path: "Images/Textures/only-b.jpg"), encoding: .utf8) == "newer, keep me")

        let copied = try FileManager.default.attributesOfItem(atPath: pair.b.appending(path: "Archives/only-a.zip").path)
        #expect(copied[.modificationDate] as? Date == date)
        let after = try await pair.compare()
        #expect(after.onlyA.isEmpty && after.onlyB.isEmpty)
        #expect(after.changed.map(\.path) == ["Images/Textures/only-b.jpg"])
    }

    /// A rerun with the earlier hashes only hashes files that are new or changed
    @Test func rerunHashesOnlyNewFiles() async throws {
        let pair = Pair()
        defer { pair.remove() }
        try pair.write(pair.a, "shared.txt", "same size")
        try pair.write(pair.b, "shared.txt", "same size")
        try pair.write(pair.a, "copied.txt", "abc")
        let first = try await pair.compare()
        #expect(first.onlyA.map(\.path) == ["copied.txt"])

        try pair.write(pair.b, "copied.txt", "abc")
        final class Hashed: @unchecked Sendable { var bytes: Int64 = 0 }
        let hashed = Hashed()
        let second = try await FolderComparison.compare(pair.a, pair.b, reusing: first.hashes) { _, bytes, _ in hashed.bytes = bytes }
        #expect(second.verdict == .identical)
        #expect(hashed.bytes == 6)  // copied.txt on both sides, not shared.txt again
    }

    /// Opening a session touches its database and caches; only real edits pick the newer side
    @Test func newerSessionIgnoresDatabaseAndCache() async throws {
        let pair = Pair()
        defer { pair.remove() }
        let (early, late, latest) = (Date(timeIntervalSince1970: 1_000), Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 3_000))
        try pair.write(pair.a, "Shoot.cosessiondb", "db v1", modified: early)
        try pair.write(pair.b, "Shoot.cosessiondb", "db v2", modified: latest)  // only opened on B
        try pair.write(pair.b, "Capture/CaptureOne/Cache/Thumbnails/IMG_1.cot", "thumb", modified: latest)
        try pair.write(pair.a, "Capture/CaptureOne/Settings160/IMG_1.CR3.cos", "edit 2", modified: late)
        try pair.write(pair.b, "Capture/CaptureOne/Settings160/IMG_1.CR3.cos", "edit 1", modified: early)

        let edits = try #require(try await pair.compare().sessionEdits())
        #expect(edits.a == late && edits.b == early)
        #expect(try await Pair().compare().sessionEdits() == nil)  // not sessions
    }

    /// Mirroring makes the destination match: changed files replaced, extras removed, moves followed
    @Test func mirrorMakesDestinationIdentical() async throws {
        let pair = Pair()
        defer { pair.remove() }
        try pair.write(pair.a, "Shoot.cosessiondb", "db")
        try pair.write(pair.b, "Shoot.cosessiondb", "db")
        try pair.write(pair.a, "edit.cos", "new edit", modified: Date(timeIntervalSince1970: 2_000))
        try pair.write(pair.b, "edit.cos", "old", modified: Date(timeIntervalSince1970: 1_000))
        try pair.write(pair.a, "Capture/new.CR3", "new shot")
        try pair.write(pair.b, "Capture/CaptureOne/Cache/extra.cot", "stale cache")
        try pair.write(pair.a, "Output/renamed.jpg", "pixels")
        try pair.write(pair.b, "Output/original.jpg", "pixels")

        let before = try await pair.compare()
        let plan = before.mirrorPlan(from: .a)
        #expect(plan.replacingNewer == 0)
        var removed: [String] = []
        let failures = try await FolderComparison.mirror(plan, from: pair.a, to: pair.b) { url in
            removed.append(url.lastPathComponent)
            try FileManager.default.removeItem(at: url)
        }
        #expect(failures.isEmpty)
        #expect(Set(removed) == ["edit.cos", "extra.cot", "original.jpg"])
        #expect(try await pair.compare().verdict == .identical)
    }

    /// Identical proxies only on the source all match one file both sides have: that file stays,
    /// and nothing is removed twice
    @Test func mirrorKeepsSharedFileThatMovesPointAt() async throws {
        let pair = Pair()
        defer { pair.remove() }
        for folder in [pair.a, pair.b] {
            try pair.write(folder, "Shoot.cosessiondb", "db")
            try pair.write(folder, "Cache/Proxies/IMG_1.cof", "proxy")
        }
        try pair.write(pair.a, "Cache/Proxies/IMG_1 2.cof", "proxy")
        try pair.write(pair.a, "Cache/Proxies/IMG_1 3.cof", "proxy")
        try pair.write(pair.b, "Cache/Proxies/IMG_9.cof", "proxy")  // only on the destination

        let plan = try await pair.compare().mirrorPlan(from: .a)
        #expect(plan.remove == ["Cache/Proxies/IMG_9.cof"])
        #expect(Set(plan.add.map(\.path)) == ["Cache/Proxies/IMG_1 2.cof", "Cache/Proxies/IMG_1 3.cof"])
        let failures = try await FolderComparison.mirror(plan, from: pair.a, to: pair.b) { try FileManager.default.removeItem(at: $0) }
        #expect(failures.isEmpty)
        let after = try await pair.compare()
        #expect(after.verdict == .identical && after.moved.isEmpty)
    }

    /// The progress total counts only what can be hashed: same-size pairs, never a size with no match
    @Test func hashBudgetCountsOnlyMatchingSizes() {
        func files(_ list: [(String, Int64)]) -> [String: FolderComparison.File] {
            Dictionary(uniqueKeysWithValues: list.map { ($0.0, FolderComparison.File(path: $0.0, size: $0.1, modified: nil)) })
        }
        let a = files([("same.txt", 9), ("renamed.jpg", 3), ("grown.txt", 4), (".DS_Store", 100)])
        let b = files([("same.txt", 9), ("original.jpg", 3), ("grown.txt", 6), ("unmatched.zip", 5)])
        #expect(FolderComparison.hashBudget(a, b) == 9 + 9 + 3 + 3)
    }

    /// The index skips Capture One sidecars; on disk they count
    @Test func sidecarOnlyInBMakesAIncomplete() async throws {
        let pair = Pair()
        defer { pair.remove() }
        try pair.write(pair.a, "Shoot/IMG_1.CR3", "raw")
        try pair.write(pair.b, "Shoot/IMG_1.CR3", "raw")
        try pair.write(pair.b, "Shoot/CaptureOne/Settings160/IMG_1.CR3.cos", "adjustments")

        let result = try await pair.compare()
        #expect(result.onlyB.map(\.path) == ["Shoot/CaptureOne/Settings160/IMG_1.CR3.cos"])
        #expect(result.verdict == .complete(.b))
    }
}
