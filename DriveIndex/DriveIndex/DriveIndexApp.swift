//
//  DriveIndexApp.swift
//  DriveIndex
//
//  Main application entry point for the menu bar app
//

import SwiftUI
import AppKit
import MenuBarExtraAccess

// Observable object to manage menu presentation state
@MainActor
class MenuBarState: ObservableObject {
    @Published var isPresented = false

    static let shared = MenuBarState()

    func toggle() {
        isPresented.toggle()

        // If we're showing the menu, post notification to refresh content
        if isPresented {
            NotificationCenter.default.post(name: .searchWindowDidShow, object: nil)
        }
    }
}

@main
struct DriveIndexApp: App {
    @StateObject private var driveMonitor = DriveMonitor()
    @StateObject private var indexManager = IndexManager()
    @StateObject private var menuBarState = MenuBarState.shared

    init() {
        // Setup hotkey manager - no delay needed with RegisterEventHotKey
        Task { @MainActor in
            HotkeyManager.shared.onHotkeyPressed = {
                MenuBarState.shared.toggle()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra(
            "Drive Indexer",
            systemImage: "externaldrive.fill"
        ) {
            ContentView()
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
        }
        .menuBarExtraStyle(.window)
        .menuBarExtraAccess(isPresented: $menuBarState.isPresented)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let searchWindowDidShow = Notification.Name("searchWindowDidShow")
}
