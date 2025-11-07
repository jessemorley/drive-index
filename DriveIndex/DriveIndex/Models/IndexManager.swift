//
//  IndexManager.swift
//  DriveIndexer
//
//  Manages indexing operations and state
//

import Foundation
import AppKit

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

            Task {
                await self.indexDrive(url: driveURL, uuid: driveUUID)
            }
        }
    }

    func indexDrive(url: URL, uuid: String) async {
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
                        driveUUID: uuid
                    ) { [weak self] progress in
                        Task { @MainActor in
                            self?.currentProgress = progress

                            if progress.isComplete {
                                self?.isIndexing = false
                                self?.currentProgress = nil
                                self?.showCompletionNotification(driveName: driveName, filesProcessed: progress.filesProcessed)

                                // Notify drive monitor to reload
                                NotificationCenter.default.post(
                                    name: .driveIndexingComplete,
                                    object: nil
                                )
                            }
                        }
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
        let notification = NSUserNotification()
        notification.title = "Indexing Complete"
        notification.informativeText = "Indexed \(filesProcessed) files on \(driveName)"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func showErrorNotification(driveName: String, error: Error) {
        let notification = NSUserNotification()
        notification.title = "Indexing Failed"
        notification.informativeText = "Failed to index \(driveName): \(error.localizedDescription)"
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let driveIndexingComplete = Notification.Name("driveIndexingComplete")
}
