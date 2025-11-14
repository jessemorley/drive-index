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
    private var isPositioningProgrammatically = false

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
        collectionBehavior = [] // Empty - allows window to appear on current space

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
                view.layer?.cornerRadius = 25.0
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

    /// Get a unique identifier for a screen
    private func screenIdentifier(for screen: NSScreen) -> String {
        // Use screen's displayID as the identifier
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "screen_\(screenNumber.intValue)"
        }
        return "screen_unknown"
    }

    /// Save the current window position to UserDefaults for the current screen
    private func savePosition() {
        // Only save if the window is being moved by the user, not programmatically
        guard !isPositioningProgrammatically else { return }
        guard let currentScreen = screen else { return }

        let frameString = NSStringFromRect(frame)
        let screenKey = screenIdentifier(for: currentScreen)
        let fullKey = "\(positionKey)_\(screenKey)"

        UserDefaults.standard.set(frameString, forKey: fullKey)
    }

    // MARK: - Public Methods

    /// Show the panel and optionally center it on screen
    /// - Parameter centerOnFirstShow: Whether to center the window if no saved position exists
    func show(centerOnFirstShow: Bool = true) {
        // Get the screen containing the mouse cursor (where user invoked the window)
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!

        var targetFrame: NSRect

        // Try to restore position for this specific screen
        let screenKey = screenIdentifier(for: targetScreen)
        let fullKey = "\(positionKey)_\(screenKey)"

        if let savedPosition = UserDefaults.standard.string(forKey: fullKey) {
            // Restore saved position for this screen
            var restoredFrame = NSRectFromString(savedPosition)

            // Validate that the frame has reasonable dimensions
            if restoredFrame.width <= 0 || restoredFrame.height <= 0 {
                restoredFrame = NSRect(x: 0, y: 0, width: 550, height: 474)
            }

            // Verify position is still valid on this screen (in case screen resolution changed)
            if NSIntersectsRect(restoredFrame, targetScreen.visibleFrame) {
                targetFrame = restoredFrame
            } else {
                // Resolution changed, center it
                let screenFrame = targetScreen.visibleFrame
                targetFrame = NSRect(
                    x: screenFrame.origin.x + (screenFrame.width - restoredFrame.width) / 2,
                    y: screenFrame.origin.y + (screenFrame.height - restoredFrame.height) / 2,
                    width: restoredFrame.width,
                    height: restoredFrame.height
                )
            }
        } else if centerOnFirstShow {
            // No saved position - calculate centered frame on target screen
            let screenFrame = targetScreen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - frame.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - frame.height) / 2
            targetFrame = NSRect(x: x, y: y, width: frame.width, height: frame.height)
        } else {
            targetFrame = frame
        }

        // Align frame to pixel boundaries for the target screen to prevent wobble
        let alignedFrame = backingAlignedRect(targetFrame, options: .alignAllEdgesNearest)

        // Start invisible
        alphaValue = 0.0

        // Set frame without display or animation (don't trigger position save)
        isPositioningProgrammatically = true
        setFrame(alignedFrame, display: false, animate: false)
        isPositioningProgrammatically = false

        // Make window visible but transparent
        orderFront(nil)

        // Quick fade in to avoid artifacts (gives time for layout to complete)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1.0
        }

        // Make key after fade starts
        makeKey()
    }

    /// Hide the panel
    func hide() {
        // Quick fade out to avoid artifacts
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            // Reset alpha for next show
            self.alphaValue = 1.0
        })
    }
}
