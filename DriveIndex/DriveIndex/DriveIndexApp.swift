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
        .commands {
            // Replace default About menu with custom About panel
            CommandGroup(replacing: .appInfo) {
                Button("About DriveIndex") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "Fast indexing for external drives\n\nDatabase: SQLite with FTS5\nPlatform: macOS 13+\nArchitecture: Swift + SwiftUI",
                                attributes: [
                                    NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11),
                                    NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor
                                ]
                            ),
                            NSApplication.AboutPanelOptionKey.applicationName: "DriveIndex",
                            NSApplication.AboutPanelOptionKey.applicationVersion: "1.0.1",
                            NSApplication.AboutPanelOptionKey.version: "Build 1"
                        ]
                    )
                }
            }

            // Add Settings menu item with standard keyboard shortcut
            CommandGroup(after: .appInfo) {
                Button("Settings...") {
                    appDelegate.showSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()
            }
        }
    }
}
