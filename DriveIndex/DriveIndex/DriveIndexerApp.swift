//
//  DriveIndexerApp.swift
//  DriveIndexer
//
//  Main application entry point for the menu bar app
//

import SwiftUI

@main
struct DriveIndexerApp: App {
    @StateObject private var driveMonitor = DriveMonitor()
    @StateObject private var indexManager = IndexManager()

    var body: some Scene {
        MenuBarExtra(
            "Drive Indexer",
            systemImage: "externaldrive.fill"
        ) {
            ContentView()
                .environmentObject(driveMonitor)
                .environmentObject(indexManager)
                .frame(width: 400, height: 500)
        }
        .menuBarExtraStyle(.window)
    }
}
