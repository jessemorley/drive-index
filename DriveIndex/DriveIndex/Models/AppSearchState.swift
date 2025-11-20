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
}
