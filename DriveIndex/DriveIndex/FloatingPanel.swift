//
//  FloatingPanel.swift
//  DriveIndex
//
//  Spotlight-like floating panel window that appears on all Spaces,
//  is draggable anywhere, and dismisses on ESC or click-outside.
//

import AppKit
import SwiftUI

/// Protocol for FloatingPanel to communicate dismissal events
protocol FloatingPanelDelegate: AnyObject {
    func floatingPanelShouldClose(_ panel: FloatingPanel)
}

/// Custom NSPanel subclass that provides Spotlight-like floating window behavior
class FloatingPanel: NSPanel {

    weak var panelDelegate: FloatingPanelDelegate?

    // MARK: - Initialization

    /// Initialize the floating panel with fixed dimensions
    /// - Parameters:
    ///   - contentRect: Initial frame (will be overridden by autosaved frame if available)
    ///   - styleMask: Window style mask
    ///   - backing: Backing store type
    ///   - defer: Whether to defer window creation
    init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel],
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
        // Window level and behavior
        level = .floating // Always on top, works on all Spaces
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Visual appearance
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Interaction behavior
        isMovableByWindowBackground = true // Draggable anywhere
        hidesOnDeactivate = false // Don't auto-hide when losing focus

        // Position persistence
        setFrameAutosaveName("MainPopupWindow") // Remember position across launches

        // Remove titlebar buttons for clean appearance
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.toolbarButton)?.isHidden = true

        // Prevent window from being resizable
        styleMask.remove(.resizable)
    }

    // MARK: - Keyboard Handling

    /// Handle ESC key to close the panel
    override func cancelOperation(_ sender: Any?) {
        panelDelegate?.floatingPanelShouldClose(self)
    }

    // MARK: - Public Methods

    /// Show the panel and optionally center it on screen
    /// - Parameter centerOnFirstShow: Whether to center the window if no saved position exists
    func show(centerOnFirstShow: Bool = true) {
        // If no saved frame exists and centering requested, center on screen
        if centerOnFirstShow && !UserDefaults.standard.bool(forKey: "NSWindow Frame MainPopupWindow") {
            center()
        }

        makeKeyAndOrderFront(nil)
    }

    /// Hide the panel
    func hide() {
        orderOut(nil)
    }
}
