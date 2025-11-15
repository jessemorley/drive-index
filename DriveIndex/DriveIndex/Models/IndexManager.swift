//
//  IndexManager.swift
//  DriveIndex
//
//  Manages indexing operations and state
//

import Foundation
import AppKit
import UserNotifications

@MainActor
class IndexManager: ObservableObject {
    @Published var currentProgress: IndexProgress?
    @Published var isIndexing: Bool = false
    @Published var indexingDriveName: String = ""

    private let fileIndexer = FileIndexer()
    private var indexingTask: Task<Void, Never>?

    init() {
        setupNotifications()
    }

    private func setupNotifications() {
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
}
