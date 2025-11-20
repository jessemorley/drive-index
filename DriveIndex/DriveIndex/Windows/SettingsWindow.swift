//
//  SettingsWindow.swift
//  DriveIndex
//
//  Settings window for DriveIndex application
//

import AppKit
import SwiftUI

/// Custom NSWindow subclass for the Settings window
class SettingsWindow: NSWindow {

    // MARK: - Initialization

    /// Initialize the settings window with standard macOS settings styling
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
        title = "Settings"
        titlebarAppearsTransparent = false

        // Enable unified toolbar style
        toolbarStyle = .unified

        // Window behavior
        isReleasedWhenClosed = false // Reuse window instance
        isMovableByWindowBackground = false

        // Set minimum size for settings window
        minSize = NSSize(width: 600, height: 500)

        // Position persistence
        setFrameAutosaveName("SettingsWindow")

        // Center on first launch if no saved position
        if frameAutosaveName.isEmpty || !setFrameUsingName("SettingsWindow") {
            center()
        }

        // Hide toolbar customization button
        toolbar?.isVisible = true
        toolbar?.showsBaselineSeparator = false
    }

    // MARK: - Public Methods

    /// Show the settings window
    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
