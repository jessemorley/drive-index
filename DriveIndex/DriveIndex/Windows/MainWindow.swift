//
//  MainWindow.swift
//  DriveIndex
//
//  Main window for DriveIndex application
//

import AppKit
import SwiftUI

/// Custom NSWindow subclass for the Main window
class MainWindow: NSWindow {

    // MARK: - Initialization

    /// Initialize the main window with standard macOS styling
    /// - Parameters:
    ///   - contentRect: Initial frame
    ///   - styleMask: Window style mask
    ///   - backing: Backing store type
    ///   - defer: Whether to defer window creation
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: NSWindow.BackingStoreType = .buffered,
        defer flag: Bool = false
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        configureWindow()
    }

    // MARK: - Window Configuration

    private func configureWindow() {
        // Window properties
        title = "DriveIndex"
        titlebarAppearsTransparent = true

        // Enable unified toolbar style
        toolbarStyle = .unified

        // Window behavior
        isReleasedWhenClosed = false // Reuse window instance
        isMovableByWindowBackground = false

        // Set minimum size for main window
        minSize = NSSize(width: 800, height: 500)

        // Position persistence
        setFrameAutosaveName("MainWindow")

        // Center on first launch if no saved position
        if frameAutosaveName.isEmpty || !setFrameUsingName("MainWindow") {
            center()
        }

        // Hide toolbar customization button
        toolbar?.isVisible = true
        toolbar?.showsBaselineSeparator = false
    }

    // MARK: - Public Methods

    /// Show the main window
    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
