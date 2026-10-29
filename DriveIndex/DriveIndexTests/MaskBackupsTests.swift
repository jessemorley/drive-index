//
//  MaskBackupsTests.swift
//  DriveIndexTests
//
//  Which paths count as Capture One mask backups, and which live mask each one shadows
//

import Foundation
import Testing
@testable import DriveIndex

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
        #expect(set.sessionPath == "Shoot/Capture")
        #expect(set.imageName == "IMG_0914.HEIC")
    }

    // The live mask is never touched, a symlinked backup is left alone, and nothing moves once
    // the live mask is gone
    @Test func moveToTrashChecksDiskFirst() async throws {
        let drive = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let settings = drive.appending(path: "Shoot/CaptureOne/Settings1670")
        try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: drive) }

        let rel = "Shoot/CaptureOne/Settings1670/a.jpg.comask"
        try Data("mask".utf8).write(to: drive.appending(path: rel))
        try Data("old".utf8).write(to: drive.appending(path: rel + ".backup"))
        try FileManager.default.createSymbolicLink(at: drive.appending(path: rel + ".backup_1"), withDestinationURL: drive.appending(path: rel))

        let set = MaskBackupSet(driveUUID: "A", livePath: rel, backupPaths: [rel + ".backup", rel + ".backup_1"])
        let result = await set.moveToTrash(on: drive)
        #expect(result.trashed == [rel + ".backup"])
        #expect(result.failed == [rel + ".backup_1"])
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: rel).path))

        try FileManager.default.removeItem(at: drive.appending(path: rel))
        try FileManager.default.removeItem(at: drive.appending(path: rel + ".backup_1"))
        try Data("old".utf8).write(to: drive.appending(path: rel + ".backup_1"))
        let orphaned = await set.moveToTrash(on: drive)
        #expect(orphaned.trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: drive.appending(path: rel + ".backup_1").path))
    }

    // The session file sits above "Capture/<shoot>", not next to the CaptureOne folder
    @Test func sessionFileIsFoundAboveTheShoot() throws {
        let drive = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: drive.appending(path: "Jobs/Session/Capture/Shoot/CaptureOne/Settings1670"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: drive) }
        let sessionFile = drive.appending(path: "Jobs/Session/Session.cosessiondb")
        try Data().write(to: sessionFile)

        let set = MaskBackupSet(driveUUID: "A", livePath: "Jobs/Session/Capture/Shoot/CaptureOne/Settings1670/a.jpg.comask")
        #expect(set.sessionFile(on: drive)?.lastPathComponent == "Session.cosessiondb")
    }
}
