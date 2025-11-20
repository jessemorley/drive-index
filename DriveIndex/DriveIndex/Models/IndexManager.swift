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

@MainActor
class IndexManager: ObservableObject {
    @Published var currentProgress: IndexProgress?
    @Published var isIndexing: Bool = false
    @Published var indexingDriveName: String = ""
    @Published var pendingChanges: PendingChanges?
    @Published var hashProgress: HashProgress?
    @Published var isHashing: Bool = false
    @Published var thumbnailProgress: ThumbnailProgress?
    @Published var isGeneratingThumbnails: Bool = false

    private let fileIndexer = FileIndexer()
    private let hashWorker = HashWorker()
    private let thumbnailWorker = ThumbnailWorker()
    private var indexingTask: Task<Void, Never>?
    private var hashingTask: Task<Void, Never>?
    private var thumbnailTask: Task<Void, Never>?

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

            // Extract changed paths from FSEvents if available
            let changedPaths = userInfo["changedPaths"] as? [String]

            Task {
                await self.indexDrive(url: driveURL, uuid: driveUUID, changedPaths: changedPaths)
            }
        }
    }

    func indexDrive(url: URL, uuid: String, changedPaths: [String]? = nil) async {
        // Cancel existing indexing if any
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
                do {
                    try await fileIndexer.indexDrive(
                        driveURL: url,
                        driveUUID: uuid,
                        changedPaths: changedPaths
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

                                // Invalidate storage cache for this drive
                                Task {
                                    await StorageCache.shared.invalidate(driveUUID: uuid)
                                }

                                // Start background hash computation
                                Task {
                                    await self?.startHashComputation()
                                }

                                // Start thumbnail generation (independent of hash computation)
                                Task {
                                    await self?.startThumbnailGeneration()
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

    func cancelIndexing() {
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
        currentProgress = nil
    }

    func startHashComputation() async {
        // Check if duplicate hashing is enabled (default: true)
        let duplicateHashingEnabled = UserDefaults.standard.object(forKey: "duplicateHashingEnabled") as? Bool ?? true
        guard duplicateHashingEnabled else {
            print("⏭️ Duplicate hashing is disabled in settings, skipping hash computation")
            return
        }

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

    func startThumbnailGeneration() async {
        // Check if thumbnail generation is enabled (default: true)
        let thumbnailGenerationEnabled = UserDefaults.standard.object(forKey: "thumbnailGenerationEnabled") as? Bool ?? true
        guard thumbnailGenerationEnabled else {
            print("⏭️ Thumbnail generation is disabled in settings, skipping")
            return
        }

        // Cancel existing thumbnail generation if any
        thumbnailTask?.cancel()

        do {
            // Check if there are media files without thumbnails
            let count = try await DatabaseManager.shared.getMediaFilesWithoutThumbnailsCount()
            guard count > 0 else {
                print("✅ No media files need thumbnails")
                return
            }

            print("🖼️ Starting background thumbnail generation for \(count) media files")

            isGeneratingThumbnails = true
            thumbnailProgress = nil

            thumbnailTask = Task {
                do {
                    try await thumbnailWorker.generateThumbnails() { [weak self] progress in
                        Task { @MainActor in
                            self?.thumbnailProgress = progress

                            if progress.isComplete {
                                // Show summary for 2 seconds before clearing
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                                    self?.isGeneratingThumbnails = false
                                    self?.thumbnailProgress = nil
                                }

                                // Notify that thumbnail generation is complete
                                NotificationCenter.default.post(
                                    name: .thumbnailGenerationComplete,
                                    object: nil
                                )
                            }
                        }
                    }
                } catch {
                    print("Error generating thumbnails: \(error)")
                    Task { @MainActor in
                        self.isGeneratingThumbnails = false
                        self.thumbnailProgress = nil
                    }
                }
            }
        } catch {
            print("Error starting thumbnail generation: \(error)")
            isGeneratingThumbnails = false
        }
    }

    func cancelThumbnailGeneration() {
        Task {
            await thumbnailWorker.cancel()
        }
        thumbnailTask?.cancel()
        thumbnailTask = nil
        isGeneratingThumbnails = false
        thumbnailProgress = nil
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
    static let thumbnailGenerationComplete = Notification.Name("thumbnailGenerationComplete")
}