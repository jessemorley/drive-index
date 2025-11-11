//
//  SettingsView.swift
//  DriveIndex
//
//  Settings panel for exclusion patterns
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var indexManager: IndexManager
    @EnvironmentObject var driveMonitor: DriveMonitor

    @State private var selectedTab: SettingsTab = .stats
    @State private var excludedDirectories: [String] = []
    @State private var excludedExtensions: [String] = []
    @State private var keyboardShortcut: KeyboardShortcut?
    @State private var isLoading: Bool = true
    @State private var saveStatus: SaveStatus = .none

    // Default values from FileIndexer
    private let defaultExcludedDirectories = [
        ".git",
        "node_modules",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        "Library",
        "$RECYCLE.BIN",
        "System Volume Information"
    ]

    private let defaultExcludedExtensions = [
        ".tmp",
        ".cache",
        ".DS_Store",
        ".localized"
    ]

    enum SettingsTab: String, CaseIterable, Identifiable {
        case stats = "Stats"
        case config = "Config"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .stats: return "chart.bar"
            case .config: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }

    enum SaveStatus: Equatable {
        case none
        case saving
        case saved
        case error(String)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
                .tag(SettingsTab.stats)

            ConfigView(
                excludedDirectories: $excludedDirectories,
                excludedExtensions: $excludedExtensions,
                keyboardShortcut: $keyboardShortcut,
                onRestoreDirectoriesDefaults: {
                    excludedDirectories = defaultExcludedDirectories
                },
                onRestoreExtensionsDefaults: {
                    excludedExtensions = defaultExcludedExtensions
                }
            )
            .tabItem {
                Label("Config", systemImage: "gearshape")
            }
            .tag(SettingsTab.config)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 720, height: 600)
        .toolbar {
            // Only show save/cancel for config tab
            if selectedTab == .config {
                // Status indicator on the left side
                ToolbarItem(placement: .status) {
                    Group {
                        if case .saving = saveStatus {
                            HStack(spacing: Spacing.small) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .controlSize(.small)
                                Text("Saving...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if case .saved = saveStatus {
                            HStack(spacing: Spacing.small) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .imageScale(.small)
                                Text("Saved")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else if case .error(let message) = saveStatus {
                            HStack(spacing: Spacing.small) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .imageScale(.small)
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear {
            loadSettings()
        }
    }

    private func loadSettings() {
        Task {
            let dirs = await indexManager.getExcludedDirectories()
            let exts = await indexManager.getExcludedExtensions()

            await MainActor.run {
                excludedDirectories = dirs
                excludedExtensions = exts
                keyboardShortcut = HotkeyManager.shared.currentShortcut
                isLoading = false
            }
        }
    }

    private func saveSettings() {
        saveStatus = .saving

        Task {
            do {
                // Filter out empty values (already trimmed by TagInputView)
                let dirs = excludedDirectories.filter { !$0.isEmpty }
                let exts = excludedExtensions.filter { !$0.isEmpty }

                try await indexManager.updateExcludedDirectories(dirs)
                try await indexManager.updateExcludedExtensions(exts)

                // Update keyboard shortcut
                await MainActor.run {
                    if let shortcut = keyboardShortcut {
                        HotkeyManager.shared.updateShortcut(shortcut)
                    } else {
                        HotkeyManager.shared.clearShortcut()
                    }
                }

                await MainActor.run {
                    saveStatus = .saved
                }

                // Auto-dismiss after 1 second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    saveStatus = .error(error.localizedDescription)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(IndexManager())
        .environmentObject(DriveMonitor())
}
