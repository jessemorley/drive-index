//
//  DuplicateFoldersTests.swift
//  DriveIndexTests
//
//  Which folders pair up as copies of each other, and each folder's verdict
//

import Foundation
import Testing
import SQLite3
@testable import DriveIndex

/// Hashed by file name unless a hash is given (nil: not hashed yet)
private func file(_ drive: String, _ path: String, size: Int64 = 10, hash: String?? = .none) -> FolderScanRow {
    FolderScanRow(id: 0, driveUUID: drive, driveName: drive, relativePath: path, size: size,
                  hash: hash ?? String(path.split(separator: "/").last!), isDirectory: false, modifiedAt: nil)
}

/// The files plus a row for every folder above them, as the index has
private func overview(_ files: [FolderScanRow]) -> DuplicateOverview {
    var folders: Set<[String]> = []
    for f in files {
        var path = (f.relativePath as NSString).deletingLastPathComponent
        while !path.isEmpty {
            folders.insert([f.driveUUID, path])
            path = (path as NSString).deletingLastPathComponent
        }
    }
    let rows = folders.map { FolderScanRow(id: 0, driveUUID: $0[0], driveName: $0[0], relativePath: $0[1], size: 0,
                                           hash: nil, isDirectory: true, modifiedAt: nil) }
    return DuplicateOverview(rows: rows + files)
}

private func files(_ drive: String, _ folder: String, _ names: [String]) -> [FolderScanRow] {
    names.map { file(drive, "\(folder)/\($0)") }
}

private extension DuplicateOverview {
    var paths: Set<Set<String>> { Set(sets.map { Set($0.members.map { "\($0.folder.driveUUID):\($0.folder.relativePath)" }) }) }
    func member(_ drive: String, _ path: String) -> FolderSet.Member? {
        sets.lazy.flatMap(\.members).first { $0.folder.driveUUID == drive && $0.folder.relativePath == path }
    }
}

private let five = ["1", "2", "3", "4", "5"]

struct FolderOverlapTests {
    /// An early backup with 6 of a working copy's 10 files: the backup can go, the working copy can't
    @Test func backupInsideGrownWorkingCopy() throws {
        let six = ["1", "2", "3", "4", "5", "6"].map { "\($0).NEF" }
        let o = overview(files("T72", "Weddings/Lisa Backup", six)
                         + files("T73", "Lisa", six + ["7.NEF", "8.NEF", "9.NEF", "10.NEF"])
                         + files("T72", "Weddings/Other Wedding", ["a", "b", "c", "d"]))
        #expect(o.paths == [["T72:Weddings/Lisa Backup", "T73:Lisa"]])
        let backup = try #require(o.member("T72", "Weddings/Lisa Backup"))
        let working = try #require(o.member("T73", "Lisa"))
        #expect(backup.isSafeToRemove && backup.shared == 6)
        #expect(!working.isSafeToRemove && working.shared == 6 && working.onlyHere == 4)
        #expect(o.sets[0].wastedBytes == 60)
        #expect(o.loose.isEmpty)
    }

    @Test func renamedIsSharedEditedIsChanged() throws {
        let o = overview([
            file("A", "Shoot/d.jpg", hash: "6"), file("A", "Shoot/e.jpg", hash: "7"),
            file("B", "Shoot/d.jpg", hash: "6"), file("B", "Shoot/e.jpg", hash: "7"),
            file("A", "Shoot/a.jpg", hash: "1"), file("A", "Shoot/b.jpg", hash: "2"), file("A", "Shoot/c.jpg", hash: "3"),
            file("A", "Shoot/notes.txt", hash: "4"), file("A", "Shoot/new.txt", hash: .some(nil)),
            file("B", "Shoot/renamed.jpg", hash: "1"), file("B", "Shoot/b.jpg", hash: "2"), file("B", "Shoot/c.jpg", hash: "3"),
            file("B", "Shoot/notes.txt", hash: "5"),
        ])
        let a = try #require(o.member("A", "Shoot"))
        #expect([a.files, a.shared, a.changed, a.onlyHere, a.unchecked] == [7, 5, 1, 0, 1] as [Int])
        #expect(!a.isSafeToRemove)
    }

    /// Two shared files out of three is a couple of files copied, not a folder
    @Test func fewSharedFilesStayLoose() {
        let o = overview(files("A", "Docs", ["a", "b", "c"]) + files("B", "Other", ["a", "b", "y"]))
        #expect(o.sets.isEmpty)
        #expect(Set(o.loose.map { $0.files.map(\.relativePath) }) == [["Docs/a", "Other/a"], ["Docs/b", "Other/b"]])
    }

    /// Wednesday and Friday camera folders roll up into the shoot, and stop there, not at the drive
    @Test func climbStopsBelowDriveRoot() {
        let o = overview(files("T72", "Shoot/Wednesday", five) + files("T72", "Shoot/Friday", ["6", "7", "8", "9", "10"])
                         + files("T73", "Shoot/Wednesday", five) + files("T73", "Shoot/Friday", ["6", "7", "8", "9", "10"]))
        #expect(o.paths == [["T72:Shoot", "T73:Shoot"]])
        #expect(o.sets[0].members.allSatisfy { $0.isSafeToRemove })
    }

    /// Backups holds nothing but S, so climbing to it adds no shared files and the card keeps the name S
    @Test func threeCopiesMakeOneCard() {
        let o = overview(files("A", "S", five) + files("B", "Backups/S", five) + files("C", "S copy", five))
        #expect(o.paths == [["A:S", "B:Backups/S", "C:S copy"]])
        #expect(o.sets[0].wastedBytes == 100)
    }

    /// 6 is in A and B only: each counts it as shared, but keeping C and trashing both would lose it
    @Test func missingFromTheKeptFolder() throws {
        let o = overview(files("A", "S", five + ["6"]) + files("B", "S", five + ["6"]) + files("C", "S", five))
        let set = try #require(o.sets.first)
        #expect(set.members.map(\.folder.driveUUID) == ["A", "B", "C"])
        #expect(set.members.allSatisfy { $0.isSafeToRemove })
        #expect(set.members.map(\.missingFrom) == [[0, 0, 1], [0, 0, 1], [0, 0, 0]])
    }

    /// Under the size limit nothing is hashed: a file with the same name and size counts as the copy
    @Test func smallFilesMatchByNameAndSize() throws {
        func small(_ drive: String, _ path: String, _ size: Int64) -> FolderScanRow {
            FolderScanRow(id: 0, driveUUID: drive, driveName: drive, relativePath: path, size: size,
                          hash: nil, isDirectory: false, modifiedAt: nil, small: true)
        }
        let o = overview(files("A", "S", five) + files("B", "S", five) + [
            small("A", "S/a.xmp", 10), small("B", "S/a.xmp", 10),
            small("A", "S/b.xmp", 10), small("B", "S/b.xmp", 12),
            small("A", "S/notes.txt", 10)])
        let a = try #require(o.member("A", "S"))
        let b = try #require(o.member("B", "S"))
        #expect([a.files, a.shared, a.changed, a.onlyHere, a.unchecked] == [8, 6, 1, 1, 0] as [Int])
        #expect([b.files, b.shared, b.changed, b.onlyHere, b.unchecked] == [7, 6, 1, 0, 0] as [Int])
        #expect(a.missingFrom == [0, 2])
        #expect(o.loose.isEmpty)
        #expect(o.sets[0].wastedBytes == 50)
    }

    /// A Capture One session's adjustments aren't indexed, so the index can't block it: the disk check judges it
    @Test func sessionsHaveNoIndexBlockers() throws {
        let o = overview(files("A", "Shoot", five + ["Shoot.cosessiondb"]) + files("B", "Shoot", five + ["Shoot.cosessiondb", "new.NEF"])
                         + files("C", "Plain", five + ["only"]) + files("D", "Plain", five))
        let a = try #require(o.member("A", "Shoot")), b = try #require(o.member("B", "Shoot"))
        let c = try #require(o.member("C", "Plain"))
        #expect(a.isSession && b.isSession && !c.isSession)
        #expect(b.onlyHere == 1 && b.blockers(keeping: 0).isEmpty)
        #expect(!c.blockers(keeping: 1).isEmpty)
    }

    /// The most recent copy has the newest file, ignoring the session database and Capture One's cache
    @Test func mostRecentHasTheNewestFile() throws {
        func dated(_ drive: String, _ path: String, _ day: Double) -> FolderScanRow {
            FolderScanRow(id: 0, driveUUID: drive, driveName: drive, relativePath: path, size: 10,
                          hash: String(path.split(separator: "/").last!), isDirectory: false, modifiedAt: Date(timeIntervalSince1970: day * 86_400))
        }
        let o = overview(five.map { dated("A", "S/\($0)", 1) } + [dated("A", "S/e.cos", 5)]
                         + five.map { dated("B", "S/\($0)", 1) } + [dated("B", "S/e.cos", 3), dated("B", "S/S.cosessiondb", 9),
                                                                   dated("B", "S/CaptureOne/Cache/t.jpg", 9)])
        let set = try #require(o.sets.first)
        #expect(set.members.map { $0.latest?.timeIntervalSince1970 } == [5 * 86_400, 3 * 86_400])
        #expect(set.mostRecent == 0)
    }

    /// Selects picked from several camera folders: no one folder holds enough of them, the shoot's Capture does
    @Test func selectsFromSubfoldersPairWithTheShoot() throws {
        let looks = (1...3).flatMap { look in files("T72", "Shoot/Capture/LOOK \(look)", (1...6).map { "\(look)-\($0).NEF" }) }
        let selects = files("Mac", "Selects/Capture", ["1-1", "1-2", "2-1", "2-2", "3-1", "3-2"].map { "\($0).NEF" })
        let o = overview(looks + selects)
        #expect(o.sets.count == 1)
        #expect(o.loose.isEmpty)
        let mac = try #require(o.sets.first?.members.first { $0.folder.driveUUID == "Mac" })
        #expect(mac.isSafeToRemove)
    }

    /// Test holds copies of Capture's files: Test can go, Capture can't (trashing it takes Test too)
    @Test func copiesInASubfolderPairWithTheFolderAround() throws {
        let o = overview(files("T72", "Shoot/Capture", five + ["6", "7"]) + files("T72", "Shoot/Capture/Test", five))
        #expect(o.paths == [["T72:Shoot/Capture", "T72:Shoot/Capture/Test"]])
        #expect(o.loose.isEmpty)
        let test = try #require(o.member("T72", "Shoot/Capture/Test"))
        let capture = try #require(o.member("T72", "Shoot/Capture"))
        #expect(test.isSafeToRemove)
        #expect(capture.files == 7 && capture.shared == 5 && capture.holdsAnother && !capture.isSafeToRemove)
    }

    /// A copy outside every card keeps the file card, with all its copies
    @Test func copyOutsideCardsIsLoose() {
        let o = overview(files("A", "S", five) + files("B", "S", five) + files("B", "Misc", ["1", "q", "r", "s", "t"]))
        #expect(o.paths == [["A:S", "B:S"]])
        #expect(o.loose.map { $0.files.map(\.relativePath).sorted() } == [["Misc/1", "S/1", "S/1"]])
    }
}

struct BuildOutputTests {
    /// Build and tool folders anywhere in a path are left out; folders that only share a name start aren't
    @Test func buildFoldersAreNotCompared() throws {
        var db: OpaquePointer?
        try #require(sqlite3_open(":memory:", &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let paths = [
            "app/target/debug/deps/a.o", "target/release/b.rlib", "x/DerivedData/c", "web/node_modules/d.js", "repo/.git/e",
            "Projects/Target Shoot/f.NEF", "target/notes.txt", "textures/g.png",
        ]
        let values = paths.map { "('\($0)')" }.joined(separator: ",")
        try #require(sqlite3_exec(db, "CREATE TABLE files (relative_path TEXT); INSERT INTO files VALUES \(values);", nil, nil, nil) == SQLITE_OK)

        var stmt: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "SELECT relative_path FROM files WHERE \(DatabaseManager.notBuildOutput)", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        var kept: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { kept.append(String(cString: sqlite3_column_text(stmt, 0))) }

        #expect(kept == ["Projects/Target Shoot/f.NEF", "target/notes.txt", "textures/g.png"])
    }
}
