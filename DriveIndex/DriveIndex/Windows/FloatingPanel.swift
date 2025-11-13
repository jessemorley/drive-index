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

    // MARK: - Properties

    private let positionKey = "FloatingPanelPosition"

    // MARK: - Initialization

    /// Initialize the floating panel with fixed dimensions
    /// - Parameters:
    ///   - contentRect: Initial frame (will be overridden by autosaved frame if available)
    ///   - styleMask: Window style mask
    ///   - backing: Backing store type
    ///   - defer: Whether to defer window creation
    override init(
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
        level = .floating // Always on top
        collectionBehavior = [.fullScreenAuxiliary] // Removed .canJoinAllSpaces - only show on current space

        // Visual appearance
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Interaction behavior
        isMovableByWindowBackground = true // Draggable anywhere
        hidesOnDeactivate = false // Don't auto-hide when losing focus

        // Position persistence - manual implementation for borderless windows
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }

        // Note: Position restoration happens in show() to prevent wobble

        // Remove titlebar buttons for clean appearance
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.toolbarButton)?.isHidden = true

        // Prevent window from being resizable
        styleMask.remove(.resizable)
    }

    // MARK: - Content View

    /// Override contentView to add rounded corners
    override var contentView: NSView? {
        didSet {
            if let view = contentView {
                view.wantsLayer = true
                view.layer?.cornerRadius = 12.0
                view.layer?.masksToBounds = true
            }
            // Invalidate shadow to match new rounded shape
            invalidateShadow()
        }
    }

    // MARK: - Window Behavior

    /// Override to allow panel to become key window despite .nonactivatingPanel style
    override var canBecomeKey: Bool {
        return true
    }

    // MARK: - Keyboard Handling

    /// Handle ESC key to close the panel
    override func cancelOperation(_ sender: Any?) {
        panelDelegate?.floatingPanelShouldClose(self)
    }

    // MARK: - Position Persistence

    /// Save the current window position to UserDefaults
    private func savePosition() {
        let frameString = NSStringFromRect(frame)
        UserDefaults.standard.set(frameString, forKey: positionKey)
    }

    // MARK: - Public Methods

    /// Show the panel and optionally center it on screen
    /// - Parameter centerOnFirstShow: Whether to center the window if no saved position exists
    func show(centerOnFirstShow: Bool = true) {
        // Restore position or center BEFORE showing to prevent wobble
        if let savedPosition = UserDefaults.standard.string(forKey: positionKey) {
            // Restore saved position
            let savedFrame = NSRectFromString(savedPosition)
            setFrame(savedFrame, display: false, animate: false)
        } else if centerOnFirstShow {
            // No saved position - center on screen
            center()
        }

        makeKeyAndOrderFront(nil)
    }

    /// Hide the panel
    func hide() {
        orderOut(nil)
    }
}
