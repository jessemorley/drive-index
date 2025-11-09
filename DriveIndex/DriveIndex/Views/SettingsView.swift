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

    @State private var selectedTab: SettingsTab = .exclusions
    @State private var excludedDirectories: String = ""
    @State private var excludedExtensions: String = ""
    @State private var isLoading: Bool = true
    @State private var saveStatus: SaveStatus = .none

    enum SettingsTab: String, CaseIterable, Identifiable {
        case exclusions = "Exclusions"
        case advanced = "Advanced"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .exclusions: return "line.3.horizontal.decrease.circle"
            case .advanced: return "gearshape.2"
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
            ExclusionsSettingsView(
                excludedDirectories: $excludedDirectories,
                excludedExtensions: $excludedExtensions
            )
            .tabItem {
                Label("Exclusions", systemImage: "line.3.horizontal.decrease.circle")
            }
            .tag(SettingsTab.exclusions)

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag(SettingsTab.advanced)

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 600, height: 500)
        .toolbar {
            // Only show save/cancel for exclusions tab
            if selectedTab == .exclusions {
                ToolbarItemGroup(placement: .cancellationAction) {
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
                excludedDirectories = dirs.joined(separator: ", ")
                excludedExtensions = exts.joined(separator: ", ")
                isLoading = false
            }
        }
    }

    private func saveSettings() {
        saveStatus = .saving

        Task {
            do {
                // Parse comma-separated values
                let dirs = excludedDirectories
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                let exts = excludedExtensions
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                try await indexManager.updateExcludedDirectories(dirs)
                try await indexManager.updateExcludedExtensions(exts)

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
