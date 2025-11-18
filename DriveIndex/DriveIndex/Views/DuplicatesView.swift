//
//  DuplicatesView.swift
//  DriveIndex
//
//  Displays duplicate files grouped by name and size
//

import SwiftUI

struct DuplicatesView: View {
    @State private var duplicateGroups: [DuplicateGroup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text("Duplicates")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Files with the same name and size across multiple drives")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.large)

            Divider()

            // Content
            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if duplicateGroups.isEmpty {
                emptyStateView
            } else {
                duplicatesList
            }
        }
        .task {
            await loadDuplicates()
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.medium) {
            ProgressView()
            Text("Loading duplicates...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Error loading duplicates")
                .font(.callout)
                .fontWeight(.medium)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.large)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("No duplicates found")
                .font(.callout)
                .fontWeight(.medium)
            Text("All your files are unique")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var duplicatesList: some View {
        ScrollView {
            VStack(spacing: Spacing.medium) {
                ForEach(duplicateGroups) { group in
                    DuplicateGroupRow(
                        group: group,
                        isExpanded: expandedGroups.contains(group.id)
                    ) {
                        toggleGroup(group)
                    }
                }
            }
            .padding(Spacing.large)
        }
    }

    private func toggleGroup(_ group: DuplicateGroup) {
        if expandedGroups.contains(group.id) {
            expandedGroups.remove(group.id)
        } else {
            expandedGroups.insert(group.id)
        }
    }

    private func loadDuplicates() async {
        isLoading = true
        errorMessage = nil

        do {
            let groups = try await DatabaseManager.shared.getDuplicateGroups()
            duplicateGroups = groups
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header (clickable)
            Button(action: onToggle) {
                HStack(spacing: Spacing.medium) {
                    // Expand/collapse icon
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    // File icon
                    Image(systemName: "doc.on.doc.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 24)

                    // File info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        HStack(spacing: Spacing.small) {
                            Text("\(group.count) copies")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Text(ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.tertiary)

                            Text("Total: \(ByteCountFormatter.string(fromByteCount: group.size * Int64(group.count), countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Duplicate count badge
                    HStack(spacing: Spacing.xSmall) {
                        Text("\(group.count)×")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.xSmall)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }
                .padding(Spacing.medium)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded file list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.files, id: \.id) { file in
                        DuplicateFileRow(file: file)

                        if file.id != group.files.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.top, Spacing.small)
                .padding(.leading, 40)
            }
        }
    }
}

struct DuplicateFileRow: View {
    let file: DuplicateFile

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            // File location icon
            Image(systemName: "location")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 12)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.relativePath)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: Spacing.small) {
                    Text(file.driveName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let modifiedAt = file.modifiedAt {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Text(formatDate(modifiedAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Reveal in Finder button
            Button(action: { revealInFinder(file) }) {
                Image(systemName: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, Spacing.small)
        .padding(.horizontal, Spacing.medium)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func revealInFinder(_ file: DuplicateFile) {
        let volumePath = "/Volumes/\(file.driveName)"
        let fullPath = volumePath + "/" + file.relativePath

        let url = URL(fileURLWithPath: fullPath)

        if FileManager.default.fileExists(atPath: fullPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSSound.beep()
        }
    }
}

#Preview {
    DuplicatesView()
        .frame(width: 600, height: 500)
}
