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
    private var streamContexts: [String: Unmanaged<StreamContext>] = [:]  // UUID → context

    // Event buffering
    private var eventBuffers: [String: Set<String>] = [:]  // UUID → set of paths
    private var bufferMaxIds: [String: FSEventStreamEventId] = [:]  // UUID → highest buffered event ID
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

    /// Start monitoring file system changes for a drive. Returns true when it is replaying the
    /// drive's FSEvents history since the last scan, which then posts the scan for those folders
    /// (or a mount scan if the history can't be trusted). False: the caller runs the mount scan.
    @discardableResult
    func startMonitoring(driveURL: URL, driveUUID: String) async throws -> Bool {
        // Skip if monitoring is disabled
        guard isMonitoringEnabled else {
            print("⏭️ FSEvents monitoring disabled globally")
            return false
        }
        print("🔍 Starting FSEvents monitoring for: \(driveURL.path) (UUID: \(driveUUID))")

        // Check if drive is excluded
        let isExcluded = try await database.isDriveExcluded(uuid: driveUUID)
        guard !isExcluded else {
            print("⏭️ Skipping FSEvents for excluded drive: \(driveUUID)")
            return false
        }

        // Event IDs are relative to the drive, so they stay valid across Macs and remounts
        var info = stat()
        guard stat(driveURL.path, &info) == 0 else {
            throw FSEventsError.streamCreationFailed
        }
        let cursor = try await database.getFSEventsCursor(for: driveUUID)
        var storeUUID = fseventsStoreUUID(device: info.st_dev)

        // Right after a mount, fseventsd can take a few seconds to open the drive's event store
        // (seen: 0.9–3.2s). Drives without .fseventsd (e.g. exFAT) have none to wait for. The mount
        // scan reads its cursor after this returns, so it waits too.
        let hasEventStore = FileManager.default.fileExists(atPath: driveURL.path + "/.fseventsd")
        for _ in 0..<33 where storeUUID == nil && hasEventStore {
            try await Task.sleep(nanoseconds: 300_000_000)
            storeUUID = fseventsStoreUUID(device: info.st_dev)
        }

        // Replay history only from a cursor saved for this same event store
        let replaying = storeUUID != nil && cursor?.storeUUID == storeUUID
        let sinceWhen = replaying ? cursor!.id : FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        print(replaying ? "📜 Replaying FSEvents history since \(sinceWhen)" : "📜 No usable FSEvents history")

        // Stop existing monitoring if any (after the last await, so a concurrent start can't leak a stream)
        stopMonitoringSync(driveUUID: driveUUID)

        // Context passed to the callback; released in stopMonitoringSync
        let context = Unmanaged.passRetained(StreamContext(
            driveUUID: driveUUID,
            mountPath: driveURL.path,
            storeUUID: storeUUID,
            history: replaying ? [] : nil
        ))
        streamContexts[driveUUID] = context

        // FSEvents callback context
        var callbackContext = FSEventStreamContext(
            version: 0,
            info: context.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // Watch the whole drive ("" = its root). Folder-level events: paths are the changed
        // folders, which is all the delta scan needs
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes)

        guard let stream = FSEventStreamCreateRelativeToDevice(
            kCFAllocatorDefault,
            fsEventsCallback,
            &callbackContext,
            info.st_dev,
            [""] as CFArray,
            sinceWhen,
            eventLatency,
            flags
        ) else {
            context.release()
            streamContexts[driveUUID] = nil
            throw FSEventsError.streamCreationFailed
        }

        // Schedule stream on dispatch queue (replaces deprecated run loop API)
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)

        // Start the stream
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            context.release()
            streamContexts[driveUUID] = nil
            throw FSEventsError.streamStartFailed
        }

        eventStreams[driveUUID] = stream
        print("✅ FSEvents monitoring started for: \(driveUUID)")
        return replaying
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
        bufferMaxIds[driveUUID] = nil

        // Stop and release FSEvents stream
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStreams[driveUUID] = nil

        // Release context (no callbacks run after FSEventStreamInvalidate)
        streamContexts[driveUUID]?.release()
        streamContexts[driveUUID] = nil

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

    /// Handle incoming live FSEvents (already filtered by exclusion patterns)
    func handleEvents(_ paths: [String], maxEventId: FSEventStreamEventId, for driveUUID: String) {
        print("📝 Buffering \(paths.count) FSEvents for drive: \(driveUUID)")

        // Cancel existing timer
        bufferTasks[driveUUID]?.cancel()

        // Add events to buffer (Set automatically deduplicates)
        if eventBuffers[driveUUID] == nil {
            eventBuffers[driveUUID] = Set()
        }
        eventBuffers[driveUUID]?.formUnion(paths)
        bufferMaxIds[driveUUID] = max(bufferMaxIds[driveUUID] ?? 0, maxEventId)

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
        let maxEventId = bufferMaxIds[driveUUID] ?? 0
        eventBuffers[driveUUID] = nil
        bufferMaxIds[driveUUID] = nil
        bufferTasks[driveUUID] = nil

        // Trigger delta indexing with the specific changed paths
        await postIndexRequest(
            driveURL: driveURL,
            driveUUID: driveUUID,
            changedPaths: bufferedPaths,
            maxEventId: maxEventId,
            source: "fsevents"
        )

        print("✅ Delta indexing triggered for drive: \(driveUUID)")
    }

    /// History replay finished (or live events were dropped): scan the changed folders, or the
    /// whole drive when `folders` is nil because the events can't be trusted
    func handleHistory(_ folders: Set<String>?, maxEventId: FSEventStreamEventId, for driveUUID: String) async {
        guard let driveURL = await getDriveURL(for: driveUUID) else { return }

        guard let folders = folders else {
            print("⚠️ FSEvents dropped or coalesced events: mount scan for drive: \(driveUUID)")
            await postIndexRequest(driveURL: driveURL, driveUUID: driveUUID, changedPaths: nil, maxEventId: 0, source: "fsevents")
            return
        }

        print("📜 FSEvents history: \(folders.count) changed folders for drive: \(driveUUID)")
        guard !folders.isEmpty else { return }

        await postIndexRequest(driveURL: driveURL, driveUUID: driveUUID, changedPaths: folders, maxEventId: maxEventId, source: "history")
    }

    /// Ask IndexManager to scan. With changed paths, the request carries the cursor to save once
    /// the scan finishes: the highest event ID among those paths and the event store it belongs to.
    private func postIndexRequest(
        driveURL: URL,
        driveUUID: String,
        changedPaths: Set<String>?,
        maxEventId: FSEventStreamEventId,
        source: String
    ) async {
        var userInfo: [String: Any] = ["driveURL": driveURL, "driveUUID": driveUUID, "source": source]
        if let changedPaths = changedPaths {
            userInfo["changedPaths"] = Array(changedPaths)
            if let storeUUID = streamContexts[driveUUID]?.takeUnretainedValue().storeUUID {
                userInfo["eventId"] = maxEventId
                userInfo["storeUUID"] = storeUUID
            }
        }

        await MainActor.run { [userInfo] in
            NotificationCenter.default.post(name: .shouldIndexDrive, object: nil, userInfo: userInfo)
        }
    }

    // MARK: - Helper Methods

    /// Check if path should be excluded based on FileIndexer patterns
    static func isPathExcluded(_ path: String) -> Bool {
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

/// Per-stream state the callback needs. Only touched on the stream's dispatch queue (main).
final class StreamContext {
    let driveUUID: String
    let mountPath: String
    let storeUUID: String?

    // Folders replayed from history so far; nil once history is done (or when not replaying)
    var history: Set<String>?
    var historyMaxId: FSEventStreamEventId = 0
    var historyTrusted = true

    init(driveUUID: String, mountPath: String, storeUUID: String?, history: Set<String>?) {
        self.driveUUID = driveUUID
        self.mountPath = mountPath
        self.storeUUID = storeUUID
        self.history = history
    }
}

/// The drive's FSEvents event-store UUID, or nil when it keeps no history (e.g. FAT/exFAT, .fseventsd/no_log)
func fseventsStoreUUID(device: dev_t) -> String? {
    guard let uuid = FSEventsCopyUUIDForDevice(device) else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
}

/// An FSEvents event ID and the drive event store it belongs to
typealias FSEventsCursor = (id: UInt64, storeUUID: String)

/// The drive's FSEvents cursor right now, for a full scan to save once it finishes
func fseventsCursorNow(for mountPath: String) -> FSEventsCursor? {
    var info = stat()
    guard stat(mountPath, &info) == 0, let storeUUID = fseventsStoreUUID(device: info.st_dev) else { return nil }
    // Takes a POSIX time, despite the CFAbsoluteTime type
    return (FSEventsGetLastEventIdForDeviceBeforeTime(info.st_dev, Date().timeIntervalSince1970), storeUUID)
}

/// Events that mean changes may be missing from the paths delivered
private let untrustedEventFlags = FSEventStreamEventFlags(
    kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
    kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped |
    kFSEventStreamEventFlagRootChanged
)

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
    let context = Unmanaged<StreamContext>.fromOpaque(info).takeUnretainedValue()
    let driveUUID = context.driveUUID

    // Paths are relative to the drive root: "" is the root, folders end in "/"
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]

    var live = Set<String>()
    var liveMaxId: FSEventStreamEventId = 0
    var liveTrusted = true

    for i in 0..<numEvents {
        if eventFlags[i] & FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone) != 0 {
            // History arrives over several callbacks, so it's collected here (in order, on the
            // stream's queue) and sent to the actor once
            let folders = context.historyTrusted ? context.history : nil
            let maxId = context.historyMaxId
            context.history = nil
            Task {
                await FSEventsMonitor.shared.handleHistory(folders, maxEventId: maxId, for: driveUUID)
            }
            continue
        }

        let absolutePath = context.mountPath + "/" + paths[i]
        let trusted = eventFlags[i] & untrustedEventFlags == 0
        guard !FSEventsMonitor.isPathExcluded(absolutePath) else { continue }

        // Folder-level events name folders, but history can include files: use their folder
        let folder = paths[i].isEmpty || paths[i].hasSuffix("/")
            ? absolutePath
            : (absolutePath as NSString).deletingLastPathComponent

        if context.history != nil {
            context.history?.insert(folder)
            context.historyMaxId = max(context.historyMaxId, eventIds[i])
            context.historyTrusted = context.historyTrusted && trusted
        } else {
            live.insert(folder)
            liveMaxId = max(liveMaxId, eventIds[i])
            liveTrusted = liveTrusted && trusted
        }
    }

    // Dropped live events: only a mount scan catches up, and a narrower scan would save a
    // cursor past changes it never saw
    guard liveTrusted else {
        Task {
            await FSEventsMonitor.shared.handleHistory(nil, maxEventId: 0, for: driveUUID)
        }
        return
    }

    guard !live.isEmpty else { return }

    // Forward events to actor (async)
    Task {
        await FSEventsMonitor.shared.handleEvents(Array(live), maxEventId: liveMaxId, for: driveUUID)
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
