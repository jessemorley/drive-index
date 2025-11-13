//
//  DriveIndexApp.swift
//  DriveIndex
//
//  Main application entry point for the menu bar app
//

import SwiftUI
import AppKit

@main
struct DriveIndexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene - all UI handled by AppDelegate's floating panel
        // We need at least one scene for the app to run
        Settings {
            EmptyView()
        }
    }
}
