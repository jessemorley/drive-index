//
//  AppDelegate.swift
//  DriveIndex
//
//  Manages the menu bar status item and app windows.
//

import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // MARK: - Properties

    /// Status bar item (menu bar icon); its menu opens on click
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    /// The main application window for browsing drives
    private var mainWindow: MainWindow?

    /// The settings window (opened via DriveIndex > Settings menu)
    private var settingsWindow: SettingsWindow?

    /// Managers - create our own instances since DriveIndexApp's @StateObject can't be easily shared
    private let driveMonitor = DriveMonitor()
    private let indexManager = IndexManager()

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Starts as a menu bar app (LSUIElement); the Dock icon appears while a window is open

        // Apply saved theme preference
        applySavedTheme()

        setupStatusItem()
    }

    /// Opening the app again (Finder, Spotlight) shows the main window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            try? await DatabaseManager.shared.optimize()
        }
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

    // MARK: - Status Item

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Status row as a hosted SwiftUI view, so it gets a spinner and progress yet keeps the menu's look
        let host = NSHostingView(rootView: MenuBarStatusRow().environmentObject(indexManager))
        host.frame.size = host.fittingSize
        let statusRow = NSMenuItem()
        statusRow.view = host

        let menu = NSMenu()
        menu.addItem(statusRow)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open DriveIndex", action: #selector(handleOpenMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DriveIndex", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        self.statusItem = statusItem

        // DispatchQueue (not RunLoop.main) so the icon also updates while the menu is open; after the change, not before
        indexManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMenubarIcon() }
            .store(in: &cancellables)
        updateMenubarIcon()
    }

    @objc private func handleOpenMainWindow() {
        showMainWindow()
    }

    private func updateMenubarIcon() {
        statusItem?.button?.image = Self.createMenubarIcon(withStatusColor: Self.menubarStatusColor(for: indexManager))
    }

    // MARK: - Menu Bar Icon

    /// Status dot for the menu bar icon. Priority: indexing/scanning > hashing > pending changes > none
    private static func menubarStatusColor(for indexManager: IndexManager) -> NSColor? {
        if indexManager.isIndexing {
            // Green while the finished scan's summary shows, orange while scanning or indexing
            return indexManager.currentProgress?.isComplete == true ? .systemGreen : .systemOrange
        } else if indexManager.isHashing {
            return .systemPurple
        } else if indexManager.pendingChanges != nil {
            return .systemBlue
        }
        return nil
    }

    /// Create the menubar icon with an optional status indicator dot
    private static func createMenubarIcon(withStatusColor statusColor: NSColor?) -> NSImage? {
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
        NSApp.setActivationPolicy(.regular)
        window.show()
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
        NSApp.setActivationPolicy(.regular)
        window.show()
    }

    /// Create the main window with MainWindowView
    private func createMainWindow() {
        // Create window with appropriate size for content browser
        let windowRect = NSRect(x: 0, y: 0, width: 900, height: 600)
        let window = MainWindow(contentRect: windowRect)

        // Set delegate
        window.delegate = self

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

        // Set delegate
        window.delegate = self

        // Create SettingsWindowView with managers
        let settingsView = SettingsWindowView()
            .environmentObject(driveMonitor)
            .environmentObject(indexManager)

        // Host SwiftUI view in the window
        window.contentView = NSHostingView(rootView: settingsView)

        settingsWindow = window
    }

    // MARK: - NSWindowDelegate

    /// Allow windows to close normally
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // All windows can close normally
        return true
    }

    /// Release closed windows (and their SwiftUI view trees) so the app idles light
    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === mainWindow { mainWindow = nil }
        if window === settingsWindow { settingsWindow = nil }

        // Keep caches and the Dock icon while another window is open
        guard mainWindow == nil, settingsWindow == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        StorageCache.shared.invalidateAll()
        FileBrowserCache.shared.invalidateAll()
    }
}
