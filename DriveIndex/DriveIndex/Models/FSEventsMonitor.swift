//
//  FSEventsMonitor.swift
//  DriveIndex
//
//  Monitors file system changes using FSEvents for automatic delta indexing
//

import Foundation
import CoreServices

actor FSEventsMonitor {
    // Dependencies
    private let database = DatabaseManager.shared

    // FSEvents state
    private var eventStreams: [String: FSEventStreamRef] = [:]  // UUID → stream
    private var streamContexts: [String: UnsafeMutablePointer<String>] = [:]  // UUID → context

    // Event buffering
    private var eventBuffers: [String: Set<String>] = [:]  // UUID → set of paths
    private var bufferTasks: [String: Task<Void, Never>] = [:]  // UUID → debounce task

    // Configuration (stored in database)
    private var isMonitoringEnabled: Bool = true
    private var eventBufferDelay: TimeInterval = 10.0
    private let eventLatency: CFTimeInterval = 1.0  // 1 second FSEvents latency

    // Settings keys
    private let fsEventsEnabledKey = "fsevents_enabled"
    private let fsEventsBufferDelayKey = "fsevents_buffer_delay"

    // MARK: - Initialization

    init() {
        // Load settings from database
        Task {
            await loadSettings()
        }
    }

    private func loadSettings() async {
        do {
            // Load enabled state (default: true)
            if let enabledStr = try await database.getSetting(fsEventsEnabledKey) {
                isMonitoringEnabled = enabledStr == "true"
            }

            // Load buffer delay (default: 10.0)
            if let delayStr = try await database.getSetting(fsEventsBufferDelayKey),
               let delay = Double(delayStr) {
                eventBufferDelay = delay
            }
        } catch {
            print("⚠️ Error loading FSEvents settings: \(error)")
            // Use defaults
        }
    }

    // MARK: - Settings Access

    func isEnabled() -> Bool {
        return isMonitoringEnabled
    }

    func getBufferDelay() -> Double {
        return eventBufferDelay
    }

    func setEnabled(_ enabled: Bool) async {
        isMonitoringEnabled = enabled

        do {
            try await database.setSetting(fsEventsEnabledKey, value: enabled ? "true" : "false")
            print("✅ FSEvents enabled: \(enabled)")

            // Stop all monitoring if disabled
            if !enabled {
                let driveUUIDs = Array(eventStreams.keys)
                for uuid in driveUUIDs {
                    stopMonitoringSync(driveUUID: uuid)
                }
            }
        } catch {
            print("❌ Error saving FSEvents enabled setting: \(error)")
        }
    }

    func setBufferDelay(_ delay: Double) async {
        eventBufferDelay = delay

        do {
            try await database.setSetting(fsEventsBufferDelayKey, value: String(delay))
            print("✅ FSEvents buffer delay: \(delay)s")
        } catch {
            print("❌ Error saving FSEvents buffer delay: \(error)")
        }
    }

    // MARK: - Lifecycle

    /// Start monitoring file system changes for a drive
    func startMonitoring(driveURL: URL, driveUUID: String) async throws {
        // Skip if monitoring is disabled
        guard isMonitoringEnabled else {
            print("⏭️ FSEvents monitoring disabled globally")
            return
        }
        print("🔍 Starting FSEvents monitoring for: \(driveURL.path) (UUID: \(driveUUID))")

        // Stop existing monitoring if any
        stopMonitoringSync(driveUUID: driveUUID)

        // Check if drive is excluded
        let isExcluded = try await database.isDriveExcluded(uuid: driveUUID)
        guard !isExcluded else {
            print("⏭️ Skipping FSEvents for excluded drive: \(driveUUID)")
            return
        }

        // Create context to pass drive UUID to callback
        let context = UnsafeMutablePointer<String>.allocate(capacity: 1)
        context.initialize(to: driveUUID)
        streamContexts[driveUUID] = context

        // FSEvents callback context
        var callbackContext = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(context),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Create FSEvents stream
        let pathsToWatch = [driveURL.path] as CFArray
        // Folder-level events: paths are the changed folders, which is all the delta scan needs
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventsCallback,
            &callbackContext,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            eventLatency,
            flags
        ) else {
            context.deallocate()
            streamContexts[driveUUID] = nil
            throw FSEventsError.streamCreationFailed
        }

        // Schedule stream on dispatch queue (replaces deprecated run loop API)
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

        // Start the stream
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            context.deallocate()
            streamContexts[driveUUID] = nil
            throw FSEventsError.streamStartFailed
        }

        eventStreams[driveUUID] = stream
        print("✅ FSEvents monitoring started for: \(driveUUID)")
    }

    /// Stop monitoring file system changes for a drive
    func stopMonitoring(driveUUID: String) {
        stopMonitoringSync(driveUUID: driveUUID)
    }

    private func stopMonitoringSync(driveUUID: String) {
        guard let stream = eventStreams[driveUUID] else { return }

        print("⏹️ Stopping FSEvents monitoring for: \(driveUUID)")

        // Cancel pending buffer flush
        bufferTasks[driveUUID]?.cancel()
        bufferTasks[driveUUID] = nil

        // Clear buffer
        eventBuffers[driveUUID] = nil

        // Stop and release FSEvents stream
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStreams[driveUUID] = nil

        // Deallocate context
        if let context = streamContexts[driveUUID] {
            context.deinitialize(count: 1)
            context.deallocate()
            streamContexts[driveUUID] = nil
        }

        print("✅ FSEvents monitoring stopped for: \(driveUUID)")
    }

    /// Stop all monitoring (cleanup)
    func stopAllMonitoring() {
        let driveUUIDs = Array(eventStreams.keys)
        for uuid in driveUUIDs {
            stopMonitoringSync(driveUUID: uuid)
        }
    }

    // MARK: - Event Handling

    /// Handle incoming FSEvents (called from actor context)
    func handleEvents(_ paths: [String], for driveUUID: String) {
        // Filter paths by exclusion patterns
        let filteredPaths = paths.filter { path in
            !isPathExcluded(path)
        }

        guard !filteredPaths.isEmpty else {
            return
        }

        print("📝 Buffering \(filteredPaths.count) FSEvents for drive: \(driveUUID)")

        // Check if this is the first event in buffer
        _ = eventBuffers[driveUUID] == nil || eventBuffers[driveUUID]?.isEmpty == true

        // Cancel existing timer
        bufferTasks[driveUUID]?.cancel()

        // Add events to buffer (Set automatically deduplicates)
        if eventBuffers[driveUUID] == nil {
            eventBuffers[driveUUID] = Set()
        }
        eventBuffers[driveUUID]?.formUnion(filteredPaths)

        // Post changes detected notification immediately (or update if already posted)
        Task {
            await postChangesDetected(for: driveUUID)
        }

        // Start new debounce timer
        bufferTasks[driveUUID] = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(eventBufferDelay * 1_000_000_000))

                if !Task.isCancelled {
                    await flushBuffer(for: driveUUID)
                }
            } catch {
                // Task cancelled or sleep interrupted
            }
        }
    }

    /// Post or update changes detected notification
    private func postChangesDetected(for driveUUID: String) async {
        guard let bufferedPaths = eventBuffers[driveUUID], !bufferedPaths.isEmpty else {
            return
        }

        guard let driveURL = await getDriveURL(for: driveUUID) else {
            return
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .changesDetected,
                object: nil,
                userInfo: [
                    "driveURL": driveURL,
                    "driveUUID": driveUUID,
                    "changeCount": bufferedPaths.count
                ]
            )
        }
    }

    /// Flush buffered events and trigger delta indexing
    private func flushBuffer(for driveUUID: String) async {
        guard let bufferedPaths = eventBuffers[driveUUID], !bufferedPaths.isEmpty else {
            return
        }

        print("🔄 Flushing \(bufferedPaths.count) buffered events for drive: \(driveUUID)")

        // Get drive URL from mounted drives
        guard let driveURL = await getDriveURL(for: driveUUID) else {
            print("⚠️ Drive not found or unmounted: \(driveUUID)")
            return
        }

        // Clear buffer
        eventBuffers[driveUUID] = nil
        bufferTasks[driveUUID] = nil

        // Post notification to trigger delta indexing with specific changed paths
        await MainActor.run {
            NotificationCenter.default.post(
                name: .shouldIndexDrive,
                object: nil,
                userInfo: [
                    "driveURL": driveURL,
                    "driveUUID": driveUUID,
                    "source": "fsevents",
                    "changedPaths": Array(bufferedPaths)  // Pass the specific paths
                ]
            )
        }

        print("✅ Delta indexing triggered for drive: \(driveUUID)")
    }

    // MARK: - Helper Methods

    /// Check if path should be excluded based on FileIndexer patterns
    private func isPathExcluded(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension

        // Load exclusion patterns (these are cached by FileIndexer)
        // For now, use basic patterns - could optimize by caching
        let excludedDirectories = [".git", "node_modules", ".Spotlight-V100", ".Trashes",
                                   ".fseventsd", ".DocumentRevisions-V100", ".TemporaryItems"]
        let excludedExtensions = [".tmp", ".cache", ".log", ".DS_Store"]

        // Check if any path component matches excluded directories
        let pathComponents = url.pathComponents
        for component in pathComponents {
            if excludedDirectories.contains(component) {
                return true
            }
        }

        // Check if file extension matches excluded extensions
        if !fileExtension.isEmpty {
            let extWithDot = ".\(fileExtension)"
            if excludedExtensions.contains(extWithDot) || excludedExtensions.contains(fileExtension) {
                return true
            }
        }

        // Check if filename matches excluded patterns
        if excludedExtensions.contains(fileName) {
            return true
        }

        return false
    }

    /// Get mounted drive URL from DriveMonitor
    private func getDriveURL(for driveUUID: String) async -> URL? {
        let fileManager = FileManager.default
        guard let mountedURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey],
            options: .skipHiddenVolumes
        ) else {
            return nil
        }

        for url in mountedURLs {
            do {
                let values = try url.resourceValues(forKeys: [.volumeUUIDStringKey])
                if values.volumeUUIDString == driveUUID {
                    return url
                }
            } catch {
                continue
            }
        }

        return nil
    }
}

// MARK: - FSEvents Callback

/// Global callback function for FSEvents (must be non-actor context)
private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }

    // Extract drive UUID from context
    let driveUUID = info.assumingMemoryBound(to: String.self).pointee

    // Each path is a folder whose contents changed (folder-level events carry no item flags)
    // ponytail: kFSEventStreamEventFlagMustScanSubDirs is treated as a change to that folder only;
    // its subfolders catch up on the next mount scan. Handle the flag if coalesced events miss changes.
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]

    guard !paths.isEmpty else { return }

    // Forward events to actor (async)
    Task {
        await FSEventsMonitor.shared.handleEvents(paths, for: driveUUID)
    }
}

// MARK: - Singleton Access

extension FSEventsMonitor {
    static let shared = FSEventsMonitor()
}

// MARK: - Error Types

enum FSEventsError: Error, LocalizedError {
    case streamCreationFailed
    case streamStartFailed

    var errorDescription: String? {
        switch self {
        case .streamCreationFailed:
            return "Failed to create FSEvents stream"
        case .streamStartFailed:
            return "Failed to start FSEvents stream"
        }
    }
}
