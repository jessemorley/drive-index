//
//  QuickLookHelper.swift
//  DriveIndex
//
//  Helper for QuickLook previews with fallback to cached thumbnails
//

import AppKit
import Quartz

@MainActor
class QuickLookHelper: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookHelper()
    
    private var previewItems: [URL] = []
    private var currentPreviewIndex: Int = 0
    
    private override init() {
        super.init()
    }
    
    /// Show QuickLook for a file, with fallback to cached thumbnail if drive is disconnected
    func showPreview(for file: FileDisplayItem) {
        // Try to construct file URL
        if file.isConnected, let fileURL = constructFileURL(for: file) {
            // Drive is connected - preview original file
            showQuickLook(for: fileURL)
            print("🔍 Showing QuickLook for original file: \(file.name)")
        } else {
            // Drive disconnected - try to show cached thumbnail
            if let thumbnailURL = getCachedThumbnailURL(for: file.id) {
                showQuickLook(for: thumbnailURL)
                print("🔍 Showing QuickLook for cached thumbnail: \(file.name)")
            } else {
                // No preview available
                showAlert(message: "Preview unavailable", info: "Drive '\(file.driveName)' is not connected and no cached thumbnail is available.")
                print("⚠️ No preview available for: \(file.name)")
            }
        }
    }
    
    /// Toggle QuickLook panel visibility
    func togglePreview(for file: FileDisplayItem) {
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            showPreview(for: file)
        }
    }
    
    // MARK: - Private Helpers
    
    private func showQuickLook(for url: URL) {
        previewItems = [url]
        currentPreviewIndex = 0

        guard let panel = QLPreviewPanel.shared() else {
            print("⚠️ Failed to get QuickLook panel")
            return
        }

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
    
    private func constructFileURL(for file: FileDisplayItem) -> URL? {
        let volumePath = "/Volumes/\(file.driveName)"
        guard FileManager.default.fileExists(atPath: volumePath) else {
            return nil
        }
        
        let fullPath = "\(volumePath)/\(file.relativePath)"
        let url = URL(fileURLWithPath: fullPath)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        return url
    }
    
    private func getCachedThumbnailURL(for fileID: Int64) -> URL? {
        // Construct thumbnail path using same logic as ThumbnailCache
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheDirectory = appSupport.appendingPathComponent("DriveIndex").appendingPathComponent("Thumbnails")
        
        let hashPrefix = String(format: "%02d", fileID % 100)
        let thumbnailPath = cacheDirectory
            .appendingPathComponent(hashPrefix)
            .appendingPathComponent("\(fileID).jpg")
        
        guard FileManager.default.fileExists(atPath: thumbnailPath.path) else {
            return nil
        }
        
        return thumbnailPath
    }
    
    private func showAlert(message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return MainActor.assumeIsolated {
            previewItems.count
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return MainActor.assumeIsolated {
            previewItems[index] as NSURL
        }
    }
    
    // MARK: - QLPreviewPanelDelegate
    
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Handle keyboard events if needed
        return false
    }
}
