//
//  AppSearchState.swift
//  DriveIndex
//
//  Manages shared search state between main toolbar and FilesView
//

import Foundation
import SwiftUI

@Observable
class AppSearchState {
    var searchText: String = ""
    var shouldNavigateToFiles: Bool = false
    var selectedFile: FileDisplayItem? = nil
    var showInspector: Bool = false

    /// Triggers search from the main toolbar
    func performSearch(_ text: String) {
        searchText = text
        if !text.isEmpty {
            shouldNavigateToFiles = true
        }
    }

    /// Clears the search and navigation state
    func clearSearch() {
        searchText = ""
        shouldNavigateToFiles = false
    }

    /// Resets the navigation flag after navigation completes
    func resetNavigationFlag() {
        shouldNavigateToFiles = false
    }

    /// Selects a file and shows the inspector
    func selectFile(_ file: FileDisplayItem) {
        selectedFile = file
        showInspector = true
    }

    /// Deselects the file and hides the inspector
    func deselectFile() {
        selectedFile = nil
        showInspector = false
    }

    /// Toggles the inspector visibility
    func toggleInspector() {
        showInspector.toggle()
        if !showInspector {
            selectedFile = nil
        }
    }
}
