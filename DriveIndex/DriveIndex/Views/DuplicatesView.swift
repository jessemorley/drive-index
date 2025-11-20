//
//  DuplicatesView.swift
//  DriveIndex
//
//  Displays duplicate files grouped by name and size
//

import SwiftUI

enum DuplicateSortOption: String, CaseIterable {
    case duplicates = "Most Duplicates"
    case size = "Largest Files"
    case name = "Name"
}

struct DuplicateStats {
    let totalDuplicates: Int
    let wastedSpace: Int64
    let groupCount: Int

    var formattedWastedSpace: String {
        ByteCountFormatter.string(fromByteCount: wastedSpace, countStyle: .file)
    }
}

struct DuplicatesView: View {
    @State private var duplicateGroups: [DuplicateGroup] = []
    @State private var stats: DuplicateStats?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var expandedGroups: Set<String> = []
    @State private var sortOption: DuplicateSortOption = .duplicates

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
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
            }
            .navigationTitle("Duplicates")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(id: "duplicates-toolbar") {
                ToolbarItem(id: "sort", placement: .automatic) {
                    Menu {
                        ForEach(DuplicateSortOption.allCases, id: \.self) { option in
                            Button {
                                sortOption = option
                            } label: {
                                if option == sortOption {
                                    Label(option.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(option.rawValue)
                                }
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .help("Sort duplicate groups")
                }

                ToolbarItem(id: "refresh", placement: .automatic) {
                    Button(action: {
                        Task {
                            await loadDuplicates()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh duplicate detection")
                }
            }
        }
        .task {
            await loadDuplicates()
        }
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            ProgressView()
                .controlSize(.large)

            Text("Analysing files for duplicates...")
                .font(DesignSystem.Typography.subheadline)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.small) {
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
        .padding(DesignSystem.Spacing.large)
    }

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            VStack(spacing: DesignSystem.Spacing.medium) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56))
                    .foregroundColor(.green)
                    .opacity(0.7)

                VStack(spacing: DesignSystem.Spacing.small) {
                    Text("No Duplicates Found")
                        .font(DesignSystem.Typography.headline)

                    Text("Your indexed drives have no duplicate files")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.xxxLarge)
            .background(Color.green.opacity(0.05))
            .cornerRadius(DesignSystem.CornerRadius.card)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.sectionPadding)
    }

    private var sortedGroups: [DuplicateGroup] {
        duplicateGroups.sorted { lhs, rhs in
            switch sortOption {
            case .duplicates:
                return lhs.count > rhs.count
            case .size:
                return lhs.size > rhs.size
            case .name:
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private var duplicatesList: some View {
        ScrollView {
            LazyVStack(spacing: DesignSystem.Spacing.large) {
                ForEach(sortedGroups) { group in
                    DuplicateGroupRow(
                        group: group,
                        isExpanded: expandedGroups.contains(group.id)
                    ) {
                        toggleGroup(group)
                    }
                }
            }
            .padding(DesignSystem.Spacing.sectionPadding)
        }
    }

    // MARK: - Actions

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

            // Calculate stats
            let totalDuplicates = groups.reduce(0) { $0 + $1.count }
            let wastedSpace = groups.reduce(0) { $0 + ($1.size * Int64($1.count - 1)) }
            stats = DuplicateStats(
                totalDuplicates: totalDuplicates,
                wastedSpace: wastedSpace,
                groupCount: groups.count
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Duplicate Group Row

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header (clickable)
            Button(action: onToggle) {
                HStack(spacing: DesignSystem.Spacing.medium) {
                    // Expand/collapse icon
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .frame(width: 12)

                    // File icon (KEEP ORANGE)
                    Image(systemName: "doc.on.doc.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 24)

                    // File info
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxSmall) {
                        Text(group.name)
                            .font(DesignSystem.Typography.headline)
                            .lineLimit(1)

                        HStack(spacing: DesignSystem.Spacing.small) {
                            Text("\(group.count) copies")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)

                            Text("•")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.tertiaryText)

                            Text(ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)

                            Text("•")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.tertiaryText)

                            Text("Total: \(ByteCountFormatter.string(fromByteCount: group.size * Int64(group.count), countStyle: .file))")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                    }

                    Spacer()

                    // Duplicate count badge (KEEP ORANGE)
                    HStack(spacing: DesignSystem.Spacing.xSmall) {
                        Text("\(group.count)×")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.small)
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }
                .padding(DesignSystem.Spacing.cardPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded file list
            if isExpanded {
                Divider()

                VStack(spacing: 0) {
                    ForEach(group.files, id: \.id) { file in
                        DuplicateFileRow(file: file)

                        if file.id != group.files.last?.id {
                            Divider()
                                .padding(.leading, DesignSystem.Spacing.cardPadding)
                        }
                    }
                }
            }
        }
        .background(DesignSystem.Colors.cardBackground)
        .cornerRadius(DesignSystem.CornerRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Duplicate File Row

struct DuplicateFileRow: View {
    let file: DuplicateFile

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
            // File location icon
            Image(systemName: "location")
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.tertiaryText)
                .frame(width: 12)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.relativePath)
                    .font(DesignSystem.Typography.technicalData)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .lineLimit(1)

                HStack(spacing: DesignSystem.Spacing.small) {
                    Text(file.driveName)
                        .font(.caption2)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    if let modifiedAt = file.modifiedAt {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.tertiaryText)

                        Text(formatDate(modifiedAt))
                            .font(.caption2)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                }
            }

            Spacer()

            // Reveal in Finder button
            Button(action: { revealInFinder(file) }) {
                Image(systemName: "arrow.right.circle")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(DesignSystem.Spacing.medium)
        .background(Color.secondary.opacity(0.03))
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
