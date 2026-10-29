//
//  IndexManager.swift
//  DriveIndex
//
//  Manages indexing operations and state
//

import Foundation
import AppKit
import UserNotifications

struct PendingChanges {
    let driveName: String
    let changeCount: Int
}

/// Scan work owed per drive: the folders to scan (nil = mount scan) and the cursor they reach.
/// Work stays here until its scan finishes, so a scan cancelled by a newer request (for any
/// drive) is never dropped: otherwise a later scan of that drive could save a cursor past it.
struct OwedScans {
    struct Work {
        var url: URL
        var changedPaths: Set<String>?
        var cursor: FSEventsCursor?
    }

    private(set) var work: [String: Work] = [:]

    /// Merge a request into the drive's owed work and return what its scan now covers: the
    /// union of folders, or a mount scan if either is one (an FSEvents-only scan would miss
    /// changes made while unmounted)
    mutating func add(uuid: String, url: URL, changedPaths: Set<String>?, cursor: FSEventsCursor?) -> Work {
        var new = Work(url: url, changedPaths: changedPaths, cursor: cursor)
        if let owed = work[uuid] {
            new.changedPaths = owed.changedPaths.flatMap { owed in changedPaths?.union(owed) }
            // The union covers both requests' events, so it reaches the later cursor
            if let owedCursor = owed.cursor, owedCursor.id > cursor?.id ?? 0 {
                new.cursor = owedCursor
            }
        }
        // A mount scan reads its own cursor when it starts
        if new.changedPaths == nil { new.cursor = nil }
        work[uuid] = new
        return new
    }

    mutating func remove(uuid: String) {
        work[uuid] = nil
    }
}

@MainActor
class IndexManager: ObservableObject {
    @Published var currentProgress: IndexProgress?
    @Published var isIndexing: Bool = false
    @Published var indexingDriveName: String = ""
    @Published var pendingChanges: PendingChanges?
    @Published var hashProgress: HashProgress?
    @Published var isHashing: Bool = false

    private let fileIndexer = FileIndexer()
    private let hashWorker = HashWorker()
    private var indexingTask: Task<Void, Never>?
    private var hashingTask: Task<Void, Never>?

    // Work of the running scan and of scans it replaced, until each finishes
    private var owedScans = OwedScans()

    // Cumulative changes since last PRAGMA optimize
    private var changesSinceLastOptimize: Int = 0
    private let optimizeThreshold = 50

    init() {
        setupNotifications()
    }

    private func setupNotifications() {
        // Handle changes detected notification (shows pending state)
        NotificationCenter.default.addObserver(
            forName: .changesDetected,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let driveURL = userInfo["driveURL"] as? URL,
                  let changeCount = userInfo["changeCount"] as? Int else {
                print("⚠️ IndexManager: changesDetected notification received but missing required data")
                return
            }

            // We're already on main queue, so we can directly access main actor properties
            do {
                let values = try driveURL.resourceValues(forKeys: [.volumeNameKey])
                let driveName = values.volumeName ?? "Unknown"
                print("✅ IndexManager: Setting pendingChanges for \(driveName) (\(changeCount) changes)")

                // Use MainActor.assumeIsolated since we're on main queue
                MainActor.assumeIsolated {
                    self.pendingChanges = PendingChanges(driveName: driveName, changeCount: changeCount)
                }
            } catch {
                print("Error getting drive name for pending changes: \(error)")
            }
        }

        // Handle should index drive notification (starts actual indexing)
        NotificationCenter.default.addObserver(
            forName: .shouldIndexDrive,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let driveURL = userInfo["driveURL"] as? URL,
                  let driveUUID = userInfo["driveUUID"] as? String else {
                return
            }

            // Extract changed paths from FSEvents if available, and the cursor they reach
            let changedPaths = userInfo["changedPaths"] as? [String]
            var cursor: FSEventsCursor?
            if let id = userInfo["eventId"] as? UInt64, let storeUUID = userInfo["storeUUID"] as? String {
                cursor = (id, storeUUID)
            }

            Task {
                await self.indexDrive(url: driveURL, uuid: driveUUID, changedPaths: changedPaths, cursor: cursor)
            }
        }
    }

    func indexDrive(url: URL, uuid: String, changedPaths: [String]? = nil, cursor: FSEventsCursor? = nil) async {
        // This scan also covers any work still owed for the drive (a cancelled scan's folders)
        let work = owedScans.add(uuid: uuid, url: url, changedPaths: changedPaths.map(Set.init), cursor: cursor)
        let changedPaths = work.changedPaths
        let cursor = work.cursor

        // Cancel existing indexing if any; its work stays owed and runs after this scan
        indexingTask?.cancel()

        do {
            let values = try url.resourceValues(forKeys: [.volumeNameKey])
            let driveName = values.volumeName ?? "Unknown"

            // Clear pending changes and start indexing
            pendingChanges = nil
            isIndexing = true
            indexingDriveName = driveName
            currentProgress = nil

            print("Starting to index drive: \(driveName)")

            indexingTask = Task {
                // Finished or failed: the drive owes nothing, so run another drive's owed scan.
                // A cancelled scan leaves this to the scan that replaced it.
                defer {
                    if !Task.isCancelled {
                        owedScans.remove(uuid: uuid)
                        runNextOwedScan()
                    }
                }

                do {
                    try await fileIndexer.indexDrive(
                        driveURL: url,
                        driveUUID: uuid,
                        changedPaths: changedPaths.map(Array.init),
                        cursor: cursor
                    ) { [weak self] progress in
                        Task { @MainActor in
                            self?.currentProgress = progress

                            if progress.isComplete {
                                // Show summary for 2 seconds before clearing
                                if progress.summary != nil {
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        self?.isIndexing = false
                                        self?.currentProgress = nil
                                    }
                                } else {
                                    self?.isIndexing = false
                                    self?.currentProgress = nil
                                }

                                self?.showCompletionNotification(driveName: driveName, filesProcessed: progress.filesProcessed)

                                // Determine if database optimization is needed
                                let shouldOptimize: Bool
                                if let changeCount = progress.changesCount, let strongSelf = self {
                                    // Delta scan - accumulate changes
                                    strongSelf.changesSinceLastOptimize += changeCount
                                    let total = strongSelf.changesSinceLastOptimize
                                    print("📊 Delta scan: +\(changeCount) changes (total: \(total)/\(strongSelf.optimizeThreshold))")
                                    shouldOptimize = total >= strongSelf.optimizeThreshold
                                } else if progress.changesCount == nil {
                                    // Full scan - always optimize
                                    print("📊 Full scan: will optimize")
                                    shouldOptimize = true
                                } else {
                                    shouldOptimize = false
                                }

                                if shouldOptimize {
                                    Task { [weak self] in
                                        do {
                                            try await DatabaseManager.shared.optimize()
                                            await MainActor.run {
                                                self?.changesSinceLastOptimize = 0
                                            }
                                        } catch {
                                            print("⚠️ PRAGMA optimize failed: \(error)")
                                        }
                                    }
                                }

                                // Invalidate caches for this drive
                                await MainActor.run {
                                    StorageCache.shared.invalidate(driveUUID: uuid)
                                    FileBrowserCache.shared.invalidate(driveUUID: uuid)
                                }

                                // Start background hash computation
                                Task {
                                    await self?.startHashComputation()
                                }

                                // Notify drive monitor to reload
                                NotificationCenter.default.post(
                                    name: .driveIndexingComplete,
                                    object: nil
                                )
                            }
                        }
                    }
                } catch let error as DatabaseError {
                    print("Error indexing drive: \(error)")

                    // Attempt recovery for recoverable database errors
                    if error.isRecoverable {
                        Task { @MainActor in
                            self.showRecoveryNotification(driveName: driveName)
                        }

                        do {
                            try await DatabaseManager.shared.recoverDatabase()
                            // Retry indexing once after recovery
                            print("🔄 Retrying index after recovery...")
                            await self.indexDrive(url: url, uuid: uuid)
                            return
                        } catch {
                            print("❌ Recovery failed: \(error)")
                        }
                    }

                    Task { @MainActor in
                        self.isIndexing = false
                        self.currentProgress = nil
                        self.showErrorNotification(driveName: driveName, error: error)
                    }
                } catch is CancellationError {
                    // Superseded by a newer scan, which now owns the indexing state
                    print("⏹️ Indexing cancelled for: \(driveName)")
                } catch {
                    print("Error indexing drive: \(error)")
                    Task { @MainActor in
                        self.isIndexing = false
                        self.currentProgress = nil
                        self.showErrorNotification(driveName: driveName, error: error)
                    }
                }
            }

        } catch {
            print("Error getting drive name: \(error)")
            isIndexing = false
        }
    }

    /// Start the scan owed for another drive, if any. A drive unmounted since is dropped: its
    /// cursor never moved past the owed work, so its next mount catches up (and scanning a
    /// missing mount point would sweep its whole index).
    private func runNextOwedScan() {
        for (uuid, next) in owedScans.work {
            guard (try? next.url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString == uuid else {
                owedScans.remove(uuid: uuid)
                continue
            }
            Task {
                await indexDrive(url: next.url, uuid: uuid, changedPaths: next.changedPaths.map(Array.init), cursor: next.cursor)
            }
            return
        }
    }

    func cancelIndexing() {
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
        currentProgress = nil
    }

    func startHashComputation() async {
        // Cancel existing hashing if any
        hashingTask?.cancel()

        do {
            // Get minimum file size from settings (default 5MB)
            let minSizeStr = try await DatabaseManager.shared.getSetting("min_duplicate_file_size") ?? "5242880"
            let minSize = Int64(minSizeStr) ?? 5_242_880

            // Check if there are files to hash
            let unhashed = try await DatabaseManager.shared.getUnhashedCount(minSize: minSize)
            guard unhashed > 0 else {
                print("✅ No files need hashing")
                return
            }

            print("🔨 Starting background hash computation for \(unhashed) files")

            isHashing = true
            hashProgress = nil

            hashingTask = Task {
                do {
                    try await hashWorker.hashAllFiles(minSize: minSize) { [weak self] progress in
                        Task { @MainActor in
                            self?.hashProgress = progress

                            if progress.isComplete {
                                // Show summary for 2 seconds before clearing
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    self?.isHashing = false
                                    self?.hashProgress = nil
                                }

                                // Notify that hash computation is complete
                                NotificationCenter.default.post(
                                    name: .hashComputationComplete,
                                    object: nil
                                )
                            }
                        }
                    }
                } catch {
                    print("Error computing hashes: \(error)")
                    Task { @MainActor in
                        self.isHashing = false
                        self.hashProgress = nil
                    }
                }
            }
        } catch {
            print("Error starting hash computation: \(error)")
            isHashing = false
        }
    }

    func cancelHashing() {
        Task {
            await hashWorker.cancel()
        }
        hashingTask?.cancel()
        hashingTask = nil
        isHashing = false
        hashProgress = nil
    }

    func getExcludedDirectories() async -> [String] {
        await fileIndexer.getExcludedDirectories()
    }

    func getExcludedExtensions() async -> [String] {
        await fileIndexer.getExcludedExtensions()
    }

    func updateExcludedDirectories(_ directories: [String]) async throws {
        try await fileIndexer.updateExcludedDirectories(directories)
    }

    func updateExcludedExtensions(_ extensions: [String]) async throws {
        try await fileIndexer.updateExcludedExtensions(extensions)
    }

    private func showCompletionNotification(driveName: String, filesProcessed: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Indexing Complete"
        content.body = "Indexed \(filesProcessed) files on \(driveName)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func showErrorNotification(driveName: String, error: Error) {
        let content = UNMutableNotificationContent()
        content.title = "Indexing Failed"
        content.body = "Failed to index \(driveName): \(error.localizedDescription)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func showRecoveryNotification(driveName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Database Recovery"
        content.body = "Recovering database for \(driveName)..."
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let driveIndexingComplete = Notification.Name("driveIndexingComplete")
    static let changesDetected = Notification.Name("changesDetected")
    static let hashComputationComplete = Notification.Name("hashComputationComplete")
}