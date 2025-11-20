//
//  TestWindow.swift
//  DriveIndex
//
//  Test window to debug toolbar transparency
//

import AppKit
import SwiftUI

/// Custom NSWindow subclass for testing toolbar transparency
class TestWindow: NSWindow {

    // MARK: - Initialization

    /// Initialize the test window with standard macOS styling
    /// - Parameters:
    ///   - contentRect: Initial frame
    ///   - styleMask: Window style mask
    ///   - backing: Backing store type
    ///   - defer: Whether to defer window creation
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .fullSizeContentView],
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
        title = "Test Window"
        titlebarAppearsTransparent = false

        // Enable unified toolbar style
        toolbarStyle = .unified

        // Window behavior
        isReleasedWhenClosed = false // Reuse window instance
        isMovableByWindowBackground = false

        // Set minimum size
        minSize = NSSize(width: 700, height: 500)

        // Position persistence
        setFrameAutosaveName("TestWindow")

        // Center on first launch if no saved position
        if frameAutosaveName.isEmpty || !setFrameUsingName("TestWindow") {
            center()
        }

        // Hide toolbar customization button
        toolbar?.isVisible = true
        toolbar?.showsBaselineSeparator = false
    }

    // MARK: - Public Methods

    /// Show the test window
    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
