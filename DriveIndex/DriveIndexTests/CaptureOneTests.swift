//
//  CaptureOneTests.swift
//  DriveIndexTests
//
//  Which Capture One files count as removable, and the on-disk checks before anything moves
//

import Foundation
import Testing
@testable import DriveIndex

/// A scratch folder standing in for a drive, removed afterwards
private func makeDrive() throws -> URL {
    let drive = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
    return drive
}

private func write(_ files: [String], in folder: URL, modified: Date) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for file in files {
        let url = folder.appending(path: file)
        try Data(file.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
}

struct MaskBackupsTests {
    @Test func backupMapsToLiveMask() {
        let settings = "Shoot/Capture/CaptureOne/Settings1670"
        #expect(MaskBackupSet.livePath(for: "\(settings)/IMG_0914.HEIC.comask.backup") == "\(settings)/IMG_0914.HEIC.comask")
        #expect(MaskBackupSet.livePath(for: "\(settings)/IMG_0914.HEIC.comask.backup_16") == "\(settings)/IMG_0914.HEIC.comask")
        #expect(MaskBackupSet.livePath(for: "CaptureOne/Settings160/a.jpg.comask.backup_1") == "CaptureOne/Settings160/a.jpg.comask")
    }

    // Anything that isn't exactly a mask backup inside CaptureOne/Settings* is never offered
    @Test func otherPathsAreRejected() {
        #expect(MaskBackupSet.livePath(for: "Shoot/CaptureOne/Settings1670/IMG.HEIC.comask") == nil)
        #expect(MaskBackupSet.livePath(for: "Shoot/CaptureOne/Settings1670/IMG.HEIC.comask.backup_x") == nil)
        #expect(MaskBackupSet.livePath(for: "Shoot/CaptureOne/Settings1670/IMG.HEIC.comask.backup_1.zip") == nil)
        #expect(MaskBackupSet.livePath(for: "Shoot/CaptureOne/Cache/IMG.HEIC.comask.backup") == nil)
        #expect(MaskBackupSet.livePath(for: "Shoot/Backups/Settings1670/IMG.HEIC.comask.backup") == nil)
        #expect(MaskBackupSet.livePath(for: "IMG.HEIC.comask.backup") == nil)
    }

    @Test func sessionAndImageNames() {
        let set = MaskBackupSet(driveUUID: "A", livePath: "Shoot/Capture/CaptureOne/Settings1670/IMG_0914.HEIC.comask")
        #expect(set.shootPath == "Shoot/Capture")
        #expect(set.settingsPath == "Shoot/Capture/CaptureOne/Settings1670")
        #expect(set.imageName == "IMG_0914.HEIC")
    }

    // The live mask is never touched, a symlinked backup is left alone, and nothing moves once
    // the live mask is gone
    @Test func deleteChecksDiskFirst() async throws {
        let drive = try makeDrive()
        defer { try? FileManager.default.removeItem(at: drive) }
        try FileManager.default.createDirectory(at: drive.appending(path: "Shoot/CaptureOne/Settings1670"), withIntermediateDirectories: true)

        let rel = "Shoot/CaptureOne/Settings1670/a.jpg.comask"
        try Data("mask".utf8).write(to: drive.appending(path: rel))
        try Data("old".utf8).write(to: drive.appending(path: rel + ".backup"))
        try FileManager.default.createSymbolicLink(at: drive.appending(path: rel + ".backup_1"), withDestinationURL: drive.appending(path: rel))

        let set = MaskBackupSet(driveUUID: "A", livePath: rel, backupPaths: [rel + ".backup", rel + ".backup_1"])
        let result = await set.delete(on: drive)
        #expect(result.deleted == [rel + ".backup"])
        #expect(result.failed == [rel + ".backup_1"])
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: rel).path))

        try FileManager.default.removeItem(at: drive.appending(path: rel))
        try FileManager.default.removeItem(at: drive.appending(path: rel + ".backup_1"))
        try Data("old".utf8).write(to: drive.appending(path: rel + ".backup_1"))
        let orphaned = await set.delete(on: drive)
        #expect(orphaned.deleted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: rel + ".backup_1").path))
    }

    // The session file sits above "Capture/<shoot>", not next to the CaptureOne folder
    @Test func sessionIsTheNearestSessionFileAbove() {
        let files = ["A/Jobs/Session": "Jobs/Session/Session.cosessiondb", "A/Jobs": "Jobs/Outer.cosessiondb"]
        let session = CaptureOne.session(driveUUID: "A", shootPath: "Jobs/Session/Capture/Shoot", files: files)
        #expect(session.name == "Session")
        #expect(session.folder == "Jobs/Session")
        #expect(session.file == "Jobs/Session/Session.cosessiondb")

        // No session file above (a catalog, say): the shoot folder stands in
        let loose = CaptureOne.session(driveUUID: "B", shootPath: "Loose/Shoot", files: files)
        #expect(loose.name == "Shoot")
        #expect(loose.file == nil)
    }
}

struct OldSettingsFolderTests {
    @Test func versionOrder() throws {
        let v = { (name: String) in try #require(OldSettingsFolder.version(of: name)) }
        #expect(try v("Settings1680").lexicographicallyPrecedes(v("Settings17")))  // 16.8.0 < 17
        #expect(try v("Settings166").lexicographicallyPrecedes(v("Settings1665")))  // 16.6 < 16.6.5
        #expect(try v("Settings153").lexicographicallyPrecedes(v("Settings165")))
        #expect(OldSettingsFolder.version(of: "Settings1670 copy") == nil)
        #expect(OldSettingsFolder.version(of: "Settings") == nil)
    }

    // A lower version edited after the highest one is kept too, in case the version reading is wrong
    @Test func keepsNewestVersionAndAnythingEditedLater() {
        let now = Date()
        #expect(OldSettingsFolder.keep([("Settings1670", now), ("Settings1680", now)]) == ["Settings1680"])
        #expect(OldSettingsFolder.keep([("Settings1670", now), ("Settings1680", now - 60)]) == ["Settings1670", "Settings1680"])
    }

    @Test func safeOnlyWhenEveryFileIsCarriedForward() throws {
        let drive = try makeDrive()
        defer { try? FileManager.default.removeItem(at: drive) }
        let old = Date() - 3600
        try write(["a.jpg.cos", "a.jpg.comask", "b.jpg.comask.backup"], in: drive.appending(path: "S/CaptureOne/Settings1670"), modified: old)
        try write(["a.jpg.cos", "a.jpg.comask", "b.jpg.comask"], in: drive.appending(path: "S/CaptureOne/Settings1680"), modified: Date())
        let paths = ["S/CaptureOne/Settings1670", "S/CaptureOne/Settings1680"]

        // The backup's live mask was carried forward, so it doesn't count against the folder
        let safe = try #require(OldSettingsFolder.check(paths, driveUUID: "A", on: drive).first)
        #expect(safe.name == "Settings1670")
        #expect(safe.kept == ["Settings1680"])
        #expect(safe.status == .safe)

        // A mask the newer folder didn't carry forward, for an image it has settings for, is never read again;
        // Finder's .DS_Store isn't settings
        try write(["a.jpg"], in: drive.appending(path: "S"), modified: old)
        try FileManager.default.removeItem(at: drive.appending(path: "S/CaptureOne/Settings1680/a.jpg.comask"))
        try write([".DS_Store"], in: drive.appending(path: "S/CaptureOne/Settings1670"), modified: old)
        #expect(try #require(OldSettingsFolder.check(paths, driveUUID: "A", on: drive).first).status == .safe)

        // Settings only in the old folder for an image that's been deleted are disposable
        try write(["c.jpg.cos", "c.jpg.comask.backup"], in: drive.appending(path: "S/CaptureOne/Settings1670"), modified: old)
        #expect(try #require(OldSettingsFolder.check(paths, driveUUID: "A", on: drive).first).status == .safe)

        // With the image still there, they're edits found nowhere else
        try write(["c.jpg"], in: drive.appending(path: "S"), modified: old)
        let held = try #require(OldSettingsFolder.check(paths, driveUUID: "A", on: drive).first)
        #expect(held.status == .hold)
        #expect(held.orphans == 2)
    }

    // The delete step compares the folders again rather than trusting the list it was given
    @Test func deleteChecksAgain() async throws {
        let drive = try makeDrive()
        defer { try? FileManager.default.removeItem(at: drive) }
        let old = Date() - 3600
        try write(["a.jpg.cos"], in: drive.appending(path: "S/CaptureOne/Settings1670"), modified: old)
        try write(["a.jpg.cos"], in: drive.appending(path: "S/CaptureOne/Settings1680"), modified: Date())
        let folder = OldSettingsFolder(driveUUID: "A", path: "S/CaptureOne/Settings1670", status: .safe)

        try write(["new.jpg.cos"], in: drive.appending(path: "S/CaptureOne/Settings1670"), modified: old)
        try write(["new.jpg"], in: drive.appending(path: "S"), modified: old)
        #expect(await folder.delete(on: drive) == false)

        try FileManager.default.removeItem(at: drive.appending(path: "S/CaptureOne/Settings1670/new.jpg.cos"))
        #expect(await folder.delete(on: drive) == true)
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "S/CaptureOne/Settings1670").path))
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "S/CaptureOne/Settings1680/a.jpg.cos").path))
    }

    // Forcing deletes an old folder with unique files, but never the one being kept
    @Test func forceNeverTakesTheKeptFolder() async throws {
        let drive = try makeDrive()
        defer { try? FileManager.default.removeItem(at: drive) }
        try write(["a.jpg.cos", "unique.jpg.cos"], in: drive.appending(path: "S/CaptureOne/Settings1670"), modified: Date() - 3600)
        try write(["unique.jpg"], in: drive.appending(path: "S"), modified: Date())
        try write(["a.jpg.cos"], in: drive.appending(path: "S/CaptureOne/Settings1680"), modified: Date())

        let kept = OldSettingsFolder(driveUUID: "A", path: "S/CaptureOne/Settings1680", status: .safe)
        #expect(await kept.delete(on: drive, force: true) == false)

        let old = OldSettingsFolder(driveUUID: "A", path: "S/CaptureOne/Settings1670", status: .hold)
        #expect(await old.delete(on: drive) == false)
        #expect(await old.delete(on: drive, force: true) == true)
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "S/CaptureOne/Settings1680/a.jpg.cos").path))
    }
}

struct SessionTrashTests {
    // Only the Trash folder directly inside a session counts, and each item is its top-level entry
    @Test func entriesComeFromSessionTrashOnly() {
        let sessions = ["A/Jobs/Session": "Jobs/Session/Session.cosessiondb"]
        #expect(SessionTrashItem.entry(driveUUID: "A", path: "Jobs/Session/Trash/IMG.jpeg", sessionFiles: sessions) == "Jobs/Session/Trash/IMG.jpeg")
        #expect(SessionTrashItem.entry(driveUUID: "A", path: "Jobs/Session/Trash/CaptureOne/Settings1680/IMG.jpeg.cos", sessionFiles: sessions) == "Jobs/Session/Trash/CaptureOne")
        #expect(SessionTrashItem.entry(driveUUID: "A", path: "Jobs/Session/Trash", sessionFiles: sessions) == nil)
        #expect(SessionTrashItem.entry(driveUUID: "A", path: "Jobs/Other/Trash/IMG.jpeg", sessionFiles: sessions) == nil)
        #expect(SessionTrashItem.entry(driveUUID: "A", path: "Jobs/Session/Capture/Trash/IMG.jpeg", sessionFiles: sessions) == nil)
        #expect(SessionTrashItem.entry(driveUUID: "B", path: "Jobs/Session/Trash/IMG.jpeg", sessionFiles: sessions) == nil)
    }

    @Test func deleteNeedsASessionFile() async throws {
        let drive = try makeDrive()
        defer { try? FileManager.default.removeItem(at: drive) }
        try write(["IMG.jpeg"], in: drive.appending(path: "Session/Trash"), modified: Date())
        let entry = SessionTrashItem(driveUUID: "A", path: "Session/Trash/IMG.jpeg", status: .safe)

        #expect(await entry.delete(on: drive) == false)

        try Data().write(to: drive.appending(path: "Session/Session.cosessiondb"))
        #expect(await entry.delete(on: drive) == true)
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "Session/Trash/IMG.jpeg").path))
    }
}

struct LooseCaptureOneFolderTests {
    // The delete step looks for a session file above on disk rather than trusting the index
    @Test func deleteRefusesInsideASession() async throws {
        let drive = try makeDrive()
        defer { try? FileManager.default.removeItem(at: drive) }
        try write(["a.jpg.cos"], in: drive.appending(path: "Jobs/Shoot/Capture/CaptureOne/Settings1680"), modified: Date())
        let folder = LooseCaptureOneFolder(driveUUID: "A", path: "Jobs/Shoot/Capture/CaptureOne", status: .safe)

        try Data().write(to: drive.appending(path: "Jobs/Shoot/Shoot.cosessiondb"))
        #expect(await folder.delete(on: drive) == false)
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: "Jobs/Shoot/Capture/CaptureOne").path))

        try FileManager.default.removeItem(at: drive.appending(path: "Jobs/Shoot/Shoot.cosessiondb"))
        #expect(await folder.delete(on: drive) == true)
        #expect(!FileManager.default.fileExists(atPath: drive.appending(path: "Jobs/Shoot/Capture/CaptureOne").path))
    }
}
