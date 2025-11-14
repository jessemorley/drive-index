//
//  AppDelegate.swift
//  DriveIndex
//
//  Manages the menu bar status item and floating panel lifecycle.
//  Handles hotkey integration and window dismissal behavior.
//

import AppKit
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // MARK: - Properties

    /// Status bar item (menu bar icon)
    private var statusItem: NSStatusItem?

    /// The floating panel window
    private var floatingPanel: FloatingPanel?

    /// Managers - create our own instances since DriveIndexApp's @StateObject can't be easily shared
    private let driveMonitor = DriveMonitor()
    private let indexManager = IndexManager()

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use regular activation policy to show dock icon and menu bar
        NSApp.setActivationPolicy(.regular)

        // Set up status bar item
        setupStatusItem()

        // Set up global hotkey
        setupHotkey()
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        // Create status item in menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else {
            print("Failed to create status item button")
            return
        }

        // Configure button appearance
        button.image = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: "DriveIndex")
        button.action = #selector(statusItemClicked)
        button.target = self
    }

    // MARK: - Hotkey Setup

    private func setupHotkey() {
        // Wire up hotkey manager to toggle panel
        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }
    }

    // MARK: - Panel Management

    /// Status item clicked - toggle panel visibility
    @objc private func statusItemClicked() {
        togglePanel()
    }

    /// Toggle the floating panel visibility
    func togglePanel() {
        if let panel = floatingPanel, panel.isVisible {
            // Panel is visible, hide it
            closePanel()
        } else {
            // Panel is hidden or doesn't exist, show it
            showPanel()
        }
    }

    /// Show the floating panel
    private func showPanel() {
        // Create panel if it doesn't exist
        if floatingPanel == nil {
            createPanel()
        }

        guard let panel = floatingPanel else {
            print("Failed to create floating panel")
            return
        }

        // Show the panel
        panel.show(centerOnFirstShow: true)

        // Post notification that search window appeared (for ContentView reset)
        NotificationCenter.default.post(name: .searchWindowDidShow, object: nil)
    }

    /// Hide/close the floating panel
    private func closePanel() {
        floatingPanel?.hide()
    }

    /// Create the floating panel with ContentView
    private func createPanel() {
        // Create panel with fixed dimensions (matches current ContentView size)
        let panelRect = NSRect(x: 0, y: 0, width: 550, height: 474)
        let panel = FloatingPanel(contentRect: panelRect)

        // Set delegate for window events
        panel.delegate = self
        panel.panelDelegate = self

        // Create ContentView with managers
        let contentView = ContentView()
            .environmentObject(driveMonitor)
            .environmentObject(indexManager)

        // Host SwiftUI view in the panel
        panel.contentView = NSHostingView(rootView: contentView)

        floatingPanel = panel
    }

    // MARK: - NSWindowDelegate

    /// Called when the window loses key focus (click outside)
    func windowDidResignKey(_ notification: Notification) {
        // Close panel when user clicks outside
        if notification.object as? FloatingPanel === floatingPanel {
            closePanel()
        }
    }

    /// Called when window will close
    func windowWillClose(_ notification: Notification) {
        // Clean up if needed
        if notification.object as? FloatingPanel === floatingPanel {
            // Panel is closing, no additional cleanup needed
        }
    }
}

// MARK: - FloatingPanelDelegate

extension AppDelegate: @MainActor FloatingPanelDelegate {
    /// Called when ESC key is pressed in the panel
    func floatingPanelShouldClose(_ panel: FloatingPanel) {
        closePanel()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the search window appears (for ContentView to reset state)
    static let searchWindowDidShow = Notification.Name("searchWindowDidShow")
}
