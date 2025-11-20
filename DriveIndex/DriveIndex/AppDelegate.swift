//
//  AppDelegate.swift
//  DriveIndex
//
//  Manages the menu bar status item and floating panel lifecycle.
//  Handles hotkey integration and window dismissal behavior.
//

import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // MARK: - Properties

    /// Status bar item (menu bar icon)
    private var statusItem: NSStatusItem?

    /// The floating panel for quick search (Spotlight-like)
    private var floatingPanel: FloatingPanel?

    /// The main application window for browsing drives
    private var mainWindow: NSWindow?

    /// The settings window (opened via DriveIndex > Settings menu)
    private var settingsWindow: SettingsWindow?

    /// Managers - create our own instances since DriveIndexApp's @StateObject can't be easily shared
    private let driveMonitor = DriveMonitor()
    private let indexManager = IndexManager()

    /// Combine cancellables for observing IndexManager state
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep app in regular mode (always show dock icon)
        NSApp.setActivationPolicy(.regular)

        // Apply saved theme preference
        applySavedTheme()

        // Set up status bar item
        setupStatusItem()

        // Observe IndexManager state for menubar icon updates
        observeIndexManagerState()

        // Set up global hotkey
        setupHotkey()

        // Listen for main window open requests from ContentView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenMainWindow),
            name: .openMainWindow,
            object: nil
        )

        // Always show main window on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            try? await DatabaseManager.shared.optimize()
        }
    }

    @objc private func handleOpenMainWindow() {
        showMainWindow()
    }

    // MARK: - Theme Management

    private func applySavedTheme() {
        // Read saved theme preference from UserDefaults (same key as @AppStorage)
        let themeRawValue = UserDefaults.standard.string(forKey: "appTheme") ?? "Auto"
        guard let theme = AppTheme(rawValue: themeRawValue) else { return }

        // Apply appearance to the app
        let appearance: NSAppearance?
        switch theme.colorScheme {
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        case nil:
            appearance = nil  // Auto - follow system
        @unknown default:
            appearance = nil
        }

        // Set app-level appearance (will apply to all windows)
        NSApp.appearance = appearance
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

    /// Observe IndexManager state changes to update menubar icon
    private func observeIndexManagerState() {
        // Observe all relevant state changes
        Publishers.CombineLatest4(
            indexManager.$isIndexing,
            indexManager.$currentProgress,
            indexManager.$pendingChanges,
            indexManager.$isHashing
        )
        .sink { [weak self] isIndexing, currentProgress, pendingChanges, isHashing in
            self?.updateMenubarIcon(
                isIndexing: isIndexing,
                currentProgress: currentProgress,
                pendingChanges: pendingChanges,
                isHashing: isHashing
            )
        }
        .store(in: &cancellables)
    }

    /// Update the menubar icon with a status indicator dot
    private func updateMenubarIcon(
        isIndexing: Bool,
        currentProgress: IndexProgress?,
        pendingChanges: PendingChanges?,
        isHashing: Bool
    ) {
        guard let button = statusItem?.button else { return }

        // Determine the status color based on current state
        let statusColor: NSColor?

        // Priority order: indexing/scanning > hashing > pending changes > complete
        if isIndexing {
            if let progress = currentProgress {
                if progress.isComplete {
                    // Indexing complete - green (shown for 2 seconds)
                    statusColor = .systemGreen
                } else if progress.filesProcessed == 0 {
                    // Scanning - orange
                    statusColor = .systemOrange
                } else {
                    // Indexing - orange
                    statusColor = .systemOrange
                }
            } else {
                // Starting to index - orange
                statusColor = .systemOrange
            }
        } else if isHashing {
            // Analysing/hashing - purple
            statusColor = .systemPurple
        } else if pendingChanges != nil {
            // Changes detected - blue
            statusColor = .systemBlue
        } else {
            // No active status - no dot
            statusColor = nil
        }

        // Create the icon with or without status dot
        button.image = createMenubarIcon(withStatusColor: statusColor)
    }

    /// Create the menubar icon with an optional status indicator dot
    private func createMenubarIcon(withStatusColor statusColor: NSColor?) -> NSImage? {
        guard let baseSymbol = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: "DriveIndex") else {
            return nil
        }

        baseSymbol.isTemplate = true

        // If no status color, return the base image as template
        guard let statusColor = statusColor else {
            return baseSymbol
        }

        // Use standard menubar icon size
        let iconSize = NSSize(width: 18, height: 14)
        let dotRadius: CGFloat = 3.5

        // Create composite image with explicit colors (not template mode)
        let compositeImage = NSImage(size: iconSize)
        compositeImage.lockFocus()

        // Draw the base symbol in white for menubar visibility
        let symbolRect = NSRect(origin: .zero, size: iconSize)

        if let cgImage = baseSymbol.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let context = NSGraphicsContext.current?.cgContext
            context?.saveGState()

            // Use the symbol as a mask to fill with white
            context?.clip(to: symbolRect, mask: cgImage)
            NSColor.white.setFill()
            NSBezierPath(rect: symbolRect).fill()

            context?.restoreGState()
        } else {
            // Fallback: draw the symbol normally
            baseSymbol.draw(in: symbolRect)
        }

        // Draw the status indicator dot (bottom-right corner)
        let dotX = iconSize.width - dotRadius * 2 - 1.0
        let dotY: CGFloat = 1.0
        let dotRect = NSRect(
            x: dotX,
            y: dotY,
            width: dotRadius * 2,
            height: dotRadius * 2
        )

        // Draw a dark border around the dot for contrast on menubar
        let borderPath = NSBezierPath(ovalIn: dotRect.insetBy(dx: -0.5, dy: -0.5))
        borderPath.lineWidth = 1.0
        NSColor.black.withAlphaComponent(0.3).setStroke()
        borderPath.stroke()

        // Draw the colored status dot
        let dotPath = NSBezierPath(ovalIn: dotRect)
        statusColor.setFill()
        dotPath.fill()

        compositeImage.unlockFocus()

        // Do NOT use template mode - we want to preserve the colored dot
        compositeImage.isTemplate = false

        return compositeImage
    }

    // MARK: - Hotkey Setup

    private func setupHotkey() {
        // Wire up hotkey manager to toggle floating panel (quick search)
        HotkeyManager.shared.onHotkeyPressed = { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }
    }

    // MARK: - Floating Panel Management

    /// Status item clicked - show menu with options
    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Quick Search", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show Main Window", action: #selector(handleOpenMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit DriveIndex", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    /// Toggle the floating panel visibility
    @objc func togglePanel() {
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

    // MARK: - Main Window Management

    /// Open the main window (content browser)
    func showMainWindow() {
        // Create window if it doesn't exist
        if mainWindow == nil {
            createMainWindow()
        }

        guard let window = mainWindow else {
            print("Failed to create main window")
            return
        }

        // Show and activate the window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Open the settings window
    @objc func showSettingsWindow() {
        // Create window if it doesn't exist
        if settingsWindow == nil {
            createSettingsWindow()
        }

        guard let window = settingsWindow else {
            print("Failed to create settings window")
            return
        }

        // Show and activate the window
        window.show()
    }

    /// Create the main window with MainWindowView
    private func createMainWindow() {
        // Create window with appropriate size for content browser
        let windowRect = NSRect(x: 0, y: 0, width: 900, height: 600)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Configure window
        window.title = "DriveIndex"
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.delegate = self

        // Prevent the window from being released when closed
        window.isReleasedWhenClosed = false

        // Set minimum window size
        window.minSize = NSSize(width: 800, height: 500)

        // Create MainWindowView with managers
        let mainWindowView = MainWindowView()
            .environmentObject(driveMonitor)
            .environmentObject(indexManager)

        // Host SwiftUI view in the window
        window.contentView = NSHostingView(rootView: mainWindowView)

        mainWindow = window
    }

    /// Create the settings window with SettingsWindowView
    private func createSettingsWindow() {
        // Create settings window with appropriate size
        let windowRect = NSRect(x: 0, y: 0, width: 700, height: 500)
        let window = SettingsWindow(contentRect: windowRect)

        // Create SettingsWindowView with managers
        let settingsView = SettingsWindowView()
            .environmentObject(driveMonitor)
            .environmentObject(indexManager)

        // Host SwiftUI view in the window
        window.contentView = NSHostingView(rootView: settingsView)

        settingsWindow = window
    }

    // MARK: - NSWindowDelegate

    /// Called when the window loses key focus (click outside)
    func windowDidResignKey(_ notification: Notification) {
        // Close floating panel when user clicks outside
        if notification.object as? FloatingPanel === floatingPanel {
            closePanel()
        }
    }

    /// Called when window will close
    func windowWillClose(_ notification: Notification) {
        // Clean up if needed (kept minimal as windows are reusable)
        if notification.object as? FloatingPanel === floatingPanel {
            // Floating panel is closing, no additional cleanup needed
        }
    }

    /// Allow windows to close normally
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // All windows can close normally
        return true
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

    /// Posted when ContentView wants to open the main window
    static let openMainWindow = Notification.Name("openMainWindow")
}
