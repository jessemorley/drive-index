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
        VStack(spacing: 0) {
            // Header
            VStack(spacing: Spacing.small) {
                HStack {
                    Text("Settings")
                        .font(AppTypography.sectionHeader)

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }
                .padding(Spacing.Container.headerPadding)

                // Tab selector
                Picker("Settings", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.Container.horizontalPadding)
                .padding(.bottom, Spacing.medium)
            }

            Divider()

            // Content area with smooth transition
            Group {
                switch selectedTab {
                case .exclusions:
                    ExclusionsSettingsView(
                        excludedDirectories: $excludedDirectories,
                        excludedExtensions: $excludedExtensions
                    )
                    .transition(.opacity)

                case .advanced:
                    AdvancedSettingsView()
                        .transition(.opacity)

                case .about:
                    AboutView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)

            // Footer (only show for exclusions tab)
            if selectedTab == .exclusions {
                Divider()

                HStack(spacing: Spacing.medium) {
                    // Status message
                    SaveStatusIndicator

                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Save") {
                        saveSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
                .padding(Spacing.Container.headerPadding)
            }
        }
        .frame(width: 600, height: 550)
        .interactiveDismissDisabled()
        .onAppear {
            loadSettings()
        }
    }

    private var SaveStatusIndicator: some View {
        Group {
            switch saveStatus {
            case .none:
                EmptyView()
            case .saving:
                HStack(spacing: Spacing.small) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .saved:
                HStack(spacing: Spacing.small) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .transition(.scale.combined(with: .opacity))
            case .error(let message):
                HStack(spacing: Spacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: saveStatus)
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
}
