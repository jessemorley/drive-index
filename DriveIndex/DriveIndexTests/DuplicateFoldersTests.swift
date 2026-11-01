//
//  DuplicateFoldersTests.swift
//  DriveIndexTests
//
//  Which folders count as identical, and that only the highest identical level is shown
//

import Foundation
import Testing
@testable import DriveIndex

/// Hashed by file name unless a hash is given (nil: too small to hash)
private func file(_ drive: String, _ path: String, size: Int64 = 10, hash: String?? = .none) -> FolderScanRow {
    FolderScanRow(id: 0, driveUUID: drive, driveName: drive, relativePath: path, size: size,
                  hash: hash ?? String(path.split(separator: "/").last!), isDirectory: false, modifiedAt: nil)
}

private func folder(_ drive: String, _ path: String) -> FolderScanRow {
    FolderScanRow(id: 0, driveUUID: drive, driveName: drive, relativePath: path, size: 0,
                         hash: nil, isDirectory: true, modifiedAt: nil)
}

struct DuplicateFoldersTests {
    /// Mac's Downloads/Old and T72's TRANSFER/Downloads share Videos and Images, but T72 has an extra file
    @Test func highestIdenticalLevelOnly() {
        let rows = [
            folder("Mac", "Old"), folder("Mac", "Old/Videos"), folder("Mac", "Old/Videos/Clips"), folder("Mac", "Old/Images"),
            file("Mac", "Old/Videos/a.mp4"), file("Mac", "Old/Videos/Clips/b.mp4"), file("Mac", "Old/Images/c.jpg"),
            folder("T72", "TRANSFER"), folder("T72", "TRANSFER/Downloads"), folder("T72", "TRANSFER/Downloads/Videos"),
            folder("T72", "TRANSFER/Downloads/Videos/Clips"), folder("T72", "TRANSFER/Downloads/Images"),
            file("T72", "TRANSFER/Downloads/Videos/a.mp4"), file("T72", "TRANSFER/Downloads/Videos/Clips/b.mp4"),
            file("T72", "TRANSFER/Downloads/Images/c.jpg"), file("T72", "TRANSFER/Downloads/extra.zip"),
        ]
        let groups = DuplicateGroup.folders(from: rows, minSize: 1)
        let paths = Set(groups.map { $0.files.map(\.relativePath) })
        // Clips is inside the identical Videos folders, so it isn't listed on its own
        #expect(paths == [["Old/Images", "TRANSFER/Downloads/Images"], ["Old/Videos", "TRANSFER/Downloads/Videos"]])
        #expect(groups.first { $0.name == "Videos" }?.size == 20)
    }

    @Test func differentContentOrNamesDontMatch() {
        let rows = [
            file("A", "X/a.mp4"), file("B", "X/a.mp4", hash: "other"),  // same name and size, different hash
            file("A", "Y/b.mp4", hash: "same"), file("B", "Y/renamed.mp4", hash: "same"),  // same content, other name
            file("A", "Z/small.txt", hash: .some(nil)), file("B", "Z/small.txt", hash: .some(nil)),  // unhashed: name and size
        ]
        let groups = DuplicateGroup.folders(from: rows, minSize: 1)
        #expect(groups.map { $0.files.map(\.relativePath) } == [["Z", "Z"]])
    }
}
