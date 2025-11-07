//
//  SettingsView.swift
//  DriveIndexer
//
//  Settings panel for exclusion patterns
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var indexManager: IndexManager

    @State private var excludedDirectories: String = ""
    @State private var excludedExtensions: String = ""
    @State private var isLoading: Bool = true
    @State private var saveStatus: SaveStatus = .none

    enum SaveStatus {
        case none
        case saving
        case saved
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Excluded Directories
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Excluded Directories")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Directory names to skip during indexing (comma-separated)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $excludedDirectories)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 100)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )

                        Text("Default: .git, node_modules, Library, .Trashes, etc.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    // Excluded Extensions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Excluded File Extensions")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("File extensions and names to skip (comma-separated)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $excludedExtensions)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 100)
                            .padding(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )

                        Text("Default: .tmp, .cache, .DS_Store, .localized")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    // Info
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)

                        Text("Changes will apply to the next drive scan. Existing indexed files will not be removed.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                // Status message
                switch saveStatus {
                case .none:
                    EmptyView()
                case .saving:
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Saving...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .saved:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .error(let message):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 500)
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
}
