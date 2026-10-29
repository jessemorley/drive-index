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
