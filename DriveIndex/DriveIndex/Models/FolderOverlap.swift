//
//  FolderOverlap.swift
//  DriveIndex
//
//  Duplicates grouped by folder: folders holding copies of each other's files become one card, with a
//  verdict per folder. A duplicate with a copy outside every card stays a file card.
//

import Foundation

/// Folders that hold copies of each other's files
struct FolderSet: Identifiable {
    struct Member: Identifiable {
        let folder: FolderLocation
        var files = 0
        var bytes: Int64 = 0
        /// A copy is in another folder of the card (a small file: one with its name and size)
        var shared = 0
        /// Not shared, and a file with its name in another folder has different contents
        var changed = 0
        /// In no other folder of the card
        var onlyHere = 0
        /// Not hashed yet
        var unchecked = 0
        /// Another folder of the set is inside this one: its counts leave that folder out, and trashing
        /// this one would take it too
        var holdsAnother = false
        /// By member index: hashed files with no copy in that folder. With three or more folders, `shared`
        /// can mean the only other copy is in a folder also being trashed; this says what keeping one loses
        var missingFrom: [Int] = []
        /// In a Capture One session, or holding one. The index leaves out its adjustments (.cos and
        /// the like), so only a comparison on disk can judge it
        var isSession = false
        /// Its newest file, leaving out session databases and Capture One's cache, which change
        /// whenever a session is opened (as Folder Compare's latest edit does)
        var latest: Date?

        var id: String { folder.driveUUID + ":" + folder.relativePath }
        // ponytail: every file shared; a threshold ("99% shared") if the user wants one
        var isSafeToRemove: Bool { shared == files && !holdsAnother }
    }

    /// By drive name, then path
    let members: [Member]
    /// Freed by keeping one copy of each file that's in two or more of the folders
    let wastedBytes: Int64

    var id: String { members.map(\.id).joined(separator: "|") }

    /// The folder with the newest file, when any file has a date
    var mostRecent: Int? {
        members.indices.filter { members[$0].latest != nil }.max { members[$0].latest! < members[$1].latest! }
    }

    /// The folders' names, each once
    var name: String {
        members.map(\.folder.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: " · ")
    }
}

struct DuplicateOverview {
    private(set) var sets: [FolderSet] = []
    private(set) var loose: [DuplicateGroup] = []

    /// Every indexed file and folder (folders mark where a climb may go: drive roots and the folders
    /// above a local folder have no row)
    init(rows: [FolderScanRow]) {
        struct Key: Hashable { let drive: String; let path: String }
        struct Pair: Hashable {
            let a, b: Int
            init(_ x: Int, _ y: Int) { (a, b) = (min(x, y), max(x, y)) }
        }
        /// `hash` pairs folders and finds loose duplicates; `match` (the hash, or a small file's name and
        /// size) decides each file's verdict
        struct File { let row: FolderScanRow; let folder: Int?; let hash: Int?; let match: Int? }

        // Folders as Ints; a nil parent is the drive root
        var ids: [Key: Int] = [:]
        var keys: [Key] = []
        var parent: [Int?] = []
        var hasRow: [Bool] = []
        func folder(_ drive: String, _ path: String) -> Int? {
            guard !path.isEmpty else { return nil }
            let key = Key(drive: drive, path: path)
            if let id = ids[key] { return id }
            let up = folder(drive, (path as NSString).deletingLastPathComponent)
            ids[key] = keys.count
            keys.append(key)
            parent.append(up)
            hasRow.append(false)
            return keys.count - 1
        }
        func ancestors(_ id: Int?) -> [Int] {
            var result: [Int] = []
            var next = id
            while let x = next { result.append(x); next = parent[x] }
            return result
        }

        var hashIDs: [String: Int] = [:]
        var files: [File] = []
        var driveNames: [String: String] = [:]
        for row in rows {
            driveNames[row.driveUUID] = row.driveName
            if row.isDirectory {
                if let id = folder(row.driveUUID, row.relativePath) { hasRow[id] = true }
                continue
            }
            // ponytail: small files match by name and size, no hash: a heuristic, not a content check
            let key = row.small ? "\u{1}\((row.relativePath as NSString).lastPathComponent)\u{0}\(row.size)" : row.hash
            var match: Int?
            if let key { match = hashIDs[key, default: hashIDs.count]; hashIDs[key] = match }
            files.append(File(row: row, folder: folder(row.driveUUID, (row.relativePath as NSString).deletingLastPathComponent),
                              hash: row.small ? nil : match, match: match))
        }
        // Folders a session database is directly in
        let sessionFolders = Set(files.filter { $0.row.relativePath.hasSuffix(".cosessiondb") }.compactMap(\.folder))
        var copies = [Int](repeating: 0, count: hashIDs.count)
        for f in files { if let h = f.hash { copies[h] += 1 } }

        // Per folder, its whole subtree: hashed files, and how many of each duplicated hash
        var hashed = [Int](repeating: 0, count: keys.count)
        var dup = [[Int: Int]](repeating: [:], count: keys.count)
        for f in files {
            guard let h = f.hash else { continue }
            for a in ancestors(f.folder) {
                hashed[a] += 1
                if copies[h] > 1 { dup[a][h, default: 0] += 1 }
            }
        }

        /// The inner folder, when one of the two is inside the other
        func inner(_ a: Int, _ b: Int) -> Int? {
            ancestors(parent[a]).contains(b) ? a : ancestors(parent[b]).contains(a) ? b : nil
        }
        func related(_ a: Int, _ b: Int) -> Bool { a == b || inner(a, b) != nil }
        /// Containment both ways (share of each folder's hashed files with a copy in the other), higher
        /// first, and the files matched on both sides. With one folder inside the other, the outer one
        /// counts only its files outside the inner one.
        var memo: [Pair: (hi: Double, lo: Double, shared: Int)] = [:]
        func overlap(_ a: Int, _ b: Int) -> (hi: Double, lo: Double, shared: Int) {
            if let known = memo[Pair(a, b)] { return known }
            let nested = inner(a, b)
            func count(_ x: Int, _ h: Int) -> Int { (dup[x][h] ?? 0) - (nested.map { x != $0 ? dup[$0][h] ?? 0 : 0 } ?? 0) }
            func files(_ x: Int) -> Int { hashed[x] - (nested.map { x != $0 ? hashed[$0] : 0 } ?? 0) }
            func matched(_ x: Int, in y: Int) -> Int { dup[x].keys.reduce(0) { count(y, $1) > 0 ? $0 + count(x, $1) : $0 } }
            let (ma, mb) = (matched(a, in: b), matched(b, in: a))
            let (ca, cb) = (Double(ma) / Double(max(files(a), 1)), Double(mb) / Double(max(files(b), 1)))
            let result = (hi: max(ca, cb), lo: min(ca, cb), shared: ma + mb)
            memo[Pair(a, b)] = result
            return result
        }

        // Leaf pairs: the folder a copy is directly in, and the folder or any folder above it that holds
        // another copy (selects picked from several camera folders pair with the shoot's Capture)
        // ponytail: a file in more than 16 folders (a stock icon, a licence) says nothing about which are copies
        let maxFolders = 16
        var folderSets = [[Int]](repeating: [], count: hashIDs.count)
        for f in files {
            guard let h = f.hash, copies[h] > 1, let p = f.folder, folderSets[h].count <= maxFolders, !folderSets[h].contains(p) else { continue }
            folderSets[h].append(p)
        }
        struct Seed: Hashable { let leaf, other: Int }
        var seedShared: [Seed: Int] = [:]
        for ps in folderSets where ps.count > 1 && ps.count <= maxFolders {
            var seeds: Set<Seed> = []
            for leaf in ps { for p in ps where p != leaf { for y in ancestors(p) where y == p || hasRow[y] { seeds.insert(Seed(leaf: leaf, other: y)) } } }
            for seed in seeds { seedShared[seed, default: 0] += 1 }
        }
        // ponytail: tuning knobs, from the user's index; under 5 shared files is a few files copied, not a folder
        var passing: [Int: [Int]] = [:]
        for (seed, shared) in seedShared where shared >= 5 && seed.leaf != seed.other && overlap(seed.leaf, seed.other).hi >= 0.5 {
            passing[seed.leaf, default: []].append(seed.other)
        }
        // Each leaf pairs with the deepest passing folder on each branch, not everything above it
        var leafPairs: [Pair] = []
        for (leaf, others) in passing {
            for y in others where !others.contains(where: { $0 != y && ancestors(parent[$0]).contains(y) }) {
                leafPairs.append(Pair(leaf, y))
            }
        }

        // Roll each pair up while it holds: both sides at once, then one side if that adds shared files
        var tops: Set<Pair> = []
        for pair in Set(leafPairs) {
            // ponytail: a copy inside the folder it copies stays where it is
            if inner(pair.a, pair.b) != nil { tops.insert(pair); continue }
            var (a, b) = (pair.a, pair.b)
            func holds(_ x: Int, _ y: Int, growing: Bool) -> Bool {
                guard hasRow[x], hasRow[y], !related(x, y) else { return false }
                let o = overlap(x, y)
                return o.hi >= 0.8 && o.lo >= 0.25 && (!growing || o.shared > overlap(a, b).shared)
            }
            while true {
                if let pa = parent[a], let pb = parent[b], holds(pa, pb, growing: false) { (a, b) = (pa, pb) }
                else if let pa = parent[a], holds(pa, b, growing: true) { a = pa }
                else if let pb = parent[b], holds(a, pb, growing: true) { b = pb }
                else { break }
            }
            tops.insert(Pair(a, b))
        }

        // Pairs sharing a folder, or a folder inside another's, are one card, shown by the highest folders
        // (and the inner folder of a pair with one inside the other; each file counts for its nearest)
        var root = Array(keys.indices)
        func find(_ x: Int) -> Int { var x = x; while root[x] != x { x = root[x] }; return x }
        let paired = Set(tops.flatMap { [$0.a, $0.b] })
        let inners = Set(tops.compactMap { inner($0.a, $0.b) })
        for p in tops { root[find(p.a)] = find(p.b) }
        var highest: [Int] = []
        for m in paired {
            let above = ancestors(parent[m]).filter(paired.contains)
            for x in above { root[find(m)] = find(x) }
            if above.isEmpty || inners.contains(m) { highest.append(m) }
        }
        let cards = Dictionary(grouping: highest, by: find).values.filter { $0.count > 1 }
            .map { $0.sorted { (driveNames[keys[$0].drive] ?? "", keys[$0].path) < (driveNames[keys[$1].drive] ?? "", keys[$1].path) } }
        var slotOf: [Int: (card: Int, slot: Int)] = [:]
        for (c, card) in cards.enumerated() { for (s, m) in card.enumerated() { slotOf[m] = (c, s) } }

        var cardFiles = cards.map { [[Int]](repeating: [], count: $0.count) }
        var inCard = [Bool](repeating: false, count: files.count)
        for (i, f) in files.enumerated() {
            guard let at = ancestors(f.folder).lazy.compactMap({ slotOf[$0] }).first else { continue }
            cardFiles[at.card][at.slot].append(i)
            inCard[i] = true
        }

        for (c, card) in cards.enumerated() {
            let slots = cardFiles[c]
            let hashes = slots.map { Set($0.compactMap { files[$0].match }) }
            let names = slots.map { Set($0.filter { files[$0].match != nil }.map { (files[$0].row.relativePath as NSString).lastPathComponent }) }
            var count: [Int: Int] = [:]
            var size: [Int: Int64] = [:]
            var members: [FolderSet.Member] = []
            for (s, m) in card.enumerated() {
                var member = FolderSet.Member(folder: FolderLocation(driveUUID: keys[m].drive, driveName: driveNames[keys[m].drive] ?? "",
                                                                     relativePath: keys[m].path))
                member.holdsAnother = card.contains { $0 != m && ancestors(parent[$0]).contains(m) }
                member.isSession = ancestors(m).contains(where: sessionFolders.contains)
                    || slots[s].contains { files[$0].row.relativePath.hasSuffix(".cosessiondb") }
                let others = slots.indices.filter { $0 != s }
                member.missingFrom = hashes.map { kept in slots[s].count { files[$0].match.map { !kept.contains($0) } ?? false } }
                for i in slots[s] {
                    let f = files[i]
                    if let date = f.row.modifiedAt, !f.row.relativePath.hasSuffix(".cosessiondb"), !f.row.relativePath.contains("CaptureOne/Cache/") {
                        member.latest = max(member.latest ?? date, date)
                    }
                    member.files += 1
                    member.bytes += f.row.size
                    guard let h = f.match else { member.unchecked += 1; continue }
                    if f.hash != nil {
                        count[h, default: 0] += 1
                        size[h] = f.row.size
                    }
                    if others.contains(where: { hashes[$0].contains(h) }) {
                        member.shared += 1
                    } else if others.contains(where: { names[$0].contains((f.row.relativePath as NSString).lastPathComponent) }) {
                        member.changed += 1
                    } else {
                        member.onlyHere += 1
                    }
                }
                members.append(member)
            }
            let wasted = count.reduce(Int64(0)) { sum, entry in
                hashes.count(where: { $0.contains(entry.key) }) > 1 ? sum + size[entry.key]! * Int64(entry.value - 1) : sum
            }
            sets.append(FolderSet(members: members, wastedBytes: wasted))
        }

        // Duplicates with a copy outside every card, with all their copies
        var byHash: [Int: [File]] = [:]
        var outside = [Bool](repeating: false, count: hashIDs.count)
        for (i, f) in files.enumerated() { if let h = f.hash, copies[h] > 1, !inCard[i] { outside[h] = true } }
        for f in files { if let h = f.hash, outside[h] { byHash[h, default: []].append(f) } }
        loose = byHash.values.map { group in
            let copies = group.map { f in
                DuplicateFile(id: f.row.id, driveUUID: f.row.driveUUID, driveName: f.row.driveName,
                              relativePath: f.row.relativePath, modifiedAt: f.row.modifiedAt)
            }
            .sorted { ($0.driveName, $0.relativePath) < ($1.driveName, $1.relativePath) }
            return DuplicateGroup(name: (copies[0].relativePath as NSString).lastPathComponent, size: group[0].row.size,
                                  count: copies.count, files: copies)
        }
    }
}
