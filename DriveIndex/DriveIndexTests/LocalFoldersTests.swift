//
//  LocalFoldersTests.swift
//  DriveIndexTests
//
//  This Mac is walked only in its local folders: rows under a removed folder must be swept
//

import Foundation
import os
import Testing
@testable import DriveIndex

struct LocalFoldersTests {
    /// Walks `roots` and returns the visited paths, as the delta scan's sweep sees them
    private func visited(roots: [URL], basePath: String, cached: [String: Date?]?, existing: [String: (id: Int64, modifiedAt: Date?)]) async -> Set<String> {
        let marked = OSAllocatedUnfairLock(initialState: Set<String>())
        let stream = AsyncStream<FileEntry> { continuation in
            FileIndexer.enumerateFiles(
                at: roots, basePath: basePath, driveUUID: "Mac",
                excludedDirs: [], excludedExts: [],
                cachedDirectories: cached, existingFiles: existing, directoriesFromFSEvents: nil,
                onDirectorySkipped: nil,
                onFilesMarkedVisited: { paths in marked.withLock { $0.formUnion(paths) } },
                continuation: continuation
            )
        }
        var visited = Set<String>()
        for await entry in stream { visited.insert(entry.relativePath) }
        return visited.union(marked.withLock { $0 })
    }

    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("DriveIndexTests-\(UUID().uuidString)")
        // The walk reports /private/var paths; resolvingSymlinksInPath would give /var
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let root = URL(fileURLWithPath: String(cString: realpath(tmp.path, nil)))
        for folder in ["a", "c"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        fm.createFile(atPath: root.appendingPathComponent("a/x").path, contents: Data())
        fm.createFile(atPath: root.appendingPathComponent("c/y").path, contents: Data())
        return root
    }

    // Folder c was removed from the list, so its rows aren't visited and the sweep drops them,
    // including when nothing under the kept folder changed and the walk takes its shortcut
    @Test(arguments: [false, true])
    func removedFolderIsSwept(unchanged: Bool) async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let existing: [String: (id: Int64, modifiedAt: Date?)] = ["a/x": (1, nil), "c/y": (2, nil)]
        let seen = await visited(roots: [root.appendingPathComponent("a")], basePath: root.path,
                                 cached: unchanged ? [:] : nil, existing: existing)

        #expect(seen.contains("a/x"))
        #expect(!seen.contains("c/y"))
    }

    // The Mac's base path is "/": relative paths drop just the slash
    @Test func pathsAreRelativeToRoot() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }

        let seen = await visited(roots: [root.appendingPathComponent("a")], basePath: "/", cached: nil, existing: [:])

        #expect(seen == [String(root.path.dropFirst()) + "/a/x"])
    }
}
