//
//  DuplicatesView.swift
//  DriveIndex
//
//  Displays files that exist across multiple drives with backup/source management
//

import SwiftUI

// MARK: - Data Models

/// Represents a file that exists on one or more drives
struct MultiDriveFile: Identifiable {
    let id: String // Name + size combination
    let name: String
    let size: Int64
    let locations: [FileLocation]
    let modifiedAt: Date?

    var driveIds: [String] {
        locations.map { $0.driveId }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modifiedAt else { return "—" }

        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return "Today, " + formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday, " + formatter.string(from: date)
        } else if calendar.dateComponents([.day], from: date, to: Date()).day ?? 0 < 7 {
            formatter.dateFormat = "EEEE, h:mm a"
            return formatter.string(from: date)
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    var fileType: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "mov", "mp4", "avi", "mkv": return "video"
        case "jpg", "jpeg", "png", "gif", "heic", "dng", "cr2", "nef": return "image"
        case "mp3", "wav", "aiff", "m4a": return "audio"
        case "db", "sqlite": return "database"
        default: return "document"
        }
    }
}

struct FileLocation: Identifiable {
    let id: Int64
    let driveId: String
    let relativePath: String
}

/// Drive with backup designation
struct DriveState: Identifiable {
    let id: String
    let name: String
    let size: String
    let type: String
    let isBackup: Bool
    let isConnected: Bool
}

enum DuplicateSortOption: String, CaseIterable {
    case size = "Size"
    case name = "Name"
    case copies = "Copies"
}

// MARK: - Main View

struct DuplicatesView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @Environment(AppSearchState.self) private var appSearchState

    @State private var allFiles: [MultiDriveFile] = [] // All files from database
    @State private var displayedFiles: [MultiDriveFile] = [] // Currently displayed files
    @AppStorage("duplicates.driveBackupStates") private var driveBackupStatesData: Data = Data()
    @State private var driveStates: [String: Bool] = [:] // driveId -> isBackup
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var hoveredFileId: String?
    @State private var sortOption: DuplicateSortOption = .size
    @State private var showBackedUp = true
    @State private var showDuplicates = true
    @State private var gridColumns = 2

    private let batchSize = 50
    private let loadMoreThreshold = 10

    private var searchText: String {
        appSearchState.searchText
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else {
                    contentView
                }
            }
            .navigationTitle("Duplicates")
            .toolbarTitleDisplayMode(.inline)
            .toolbar(id: "duplicates-toolbar") {
                ToolbarItem(id: "refresh", placement: .automatic) {
                    Button(action: {
                        Task {
                            await loadFiles()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh file list")
                }
            }
        }
        .task {
            loadDriveStates()
            await loadFiles()
        }
        .onChange(of: showBackedUp) { _, _ in
            resetDisplayedFiles()
        }
        .onChange(of: showDuplicates) { _, _ in
            resetDisplayedFiles()
        }
        .onChange(of: sortOption) { _, _ in
            resetDisplayedFiles()
        }
    }

    // MARK: - Drive State Persistence

    private func loadDriveStates() {
        if let decoded = try? JSONDecoder().decode([String: Bool].self, from: driveBackupStatesData) {
            driveStates = decoded
        }
    }

    private func saveDriveStates() {
        if let encoded = try? JSONEncoder().encode(driveStates) {
            driveBackupStatesData = encoded
        }
    }

    // MARK: - Content View

    private var contentView: some View {
        VStack(spacing: 0) {
            // Drive Grid Section
            driveGridSection

            Divider()

            // Toolbar
            toolbarSection

            Divider()

            // File List
            if filteredFiles.isEmpty {
                emptyStateView
            } else {
                fileListSection
            }
        }
    }

    // MARK: - Drive Grid Section

    private var driveGridSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            // Header
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Indexed Drives")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.primaryText)

                    Text("Toggle 'Backup' to configure safety logic.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }

                Spacer()

                // Legend
                HStack(spacing: DesignSystem.Spacing.large) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text("Duplicate")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Backup")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                }
            }

            // Drive Grid
            GeometryReader { geometry in
                let driveCount = driveMonitor.drives.filter { $0.isIndexed }.count
                let columns = calculateColumns(
                    availableWidth: geometry.size.width,
                    driveCount: driveCount
                )

                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DesignSystem.Card.gridSpacing), count: columns), spacing: DesignSystem.Card.gridSpacing) {
                        ForEach(driveMonitor.drives.filter { $0.isIndexed }) { drive in
                            DriveGridCard(
                                drive: drive,
                                isBackup: driveStates[drive.id] ?? false,
                                highlightStatus: getHighlightStatus(driveId: drive.id),
                                onToggleBackup: {
                                    driveStates[drive.id] = !(driveStates[drive.id] ?? false)
                                    saveDriveStates()
                                }
                            )
                        }
                    }
                }
                .onChange(of: columns) { _, newValue in
                    gridColumns = newValue
                }
                .onAppear {
                    gridColumns = columns
                }
            }
            .frame(height: calculateGridHeight(driveCount: driveMonitor.drives.filter { $0.isIndexed }.count, columns: gridColumns))
        }
        .padding(DesignSystem.Spacing.sectionPadding)
    }

    // MARK: - Toolbar Section

    private var toolbarSection: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Sort Button
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
                Label(sortOption.rawValue, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.button)
            .frame(width: 180, alignment: .leading)

            Spacer()

            // Filter Toggles
            HStack(spacing: 2) {
                filterToggle(
                    title: "Backed Up",
                    icon: "checkmark.circle",
                    isActive: showBackedUp,
                    color: .green
                ) {
                    showBackedUp.toggle()
                }

                Divider()
                    .frame(height: 20)

                filterToggle(
                    title: "Duplicates",
                    icon: "exclamationmark.triangle",
                    isActive: showDuplicates,
                    color: .orange
                ) {
                    showDuplicates.toggle()
                }
            }
            .padding(2)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(6)

            Spacer()

            // Search info
            Text("\(filteredFiles.count) file\(filteredFiles.count == 1 ? "" : "s")")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 180, alignment: .trailing)
        }
        .padding(.horizontal, DesignSystem.Spacing.sectionPadding)
        .padding(.vertical, DesignSystem.Spacing.medium)
        .background(Color.secondary.opacity(0.03))
    }

    @ViewBuilder
    private func filterToggle(
        title: String,
        icon: String,
        isActive: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isActive {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? color.opacity(0.15)
                    : Color.clear
            )
            .foregroundColor(
                isActive
                    ? color
                    : DesignSystem.Colors.secondaryText
            )
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isActive ? color.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - File List Section

    private var fileListSection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Header
                fileListHeader

                Divider()

                // File rows
                ForEach(Array(displayedFiles.enumerated()), id: \.element.id) { index, file in
                    DuplicateFileRow(
                        file: file,
                        driveStates: driveStates,
                        drives: driveMonitor.drives,
                        isHovered: hoveredFileId == file.id
                    )
                    .onHover { isHovering in
                        hoveredFileId = isHovering ? file.id : nil
                    }
                    .onTapGesture {
                        revealFirstLocation(file)
                    }
                    .onAppear {
                        // Load more when approaching the end
                        if shouldLoadMore(currentIndex: index) {
                            loadMoreFiles()
                        }
                    }

                    if file.id != displayedFiles.last?.id {
                        Divider()
                            .padding(.leading, DesignSystem.Spacing.cardPadding)
                    }
                }

                // Loading indicator at bottom
                if isLoadingMore {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading more files...")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    .padding(.vertical, DesignSystem.Spacing.large)
                }
            }
        }
    }

    private var fileListHeader: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Text("Filename")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Size")
                .frame(width: 100, alignment: .trailing)

            Text("Copies")
                .frame(width: 80, alignment: .center)

            Text("Date")
                .frame(width: 140, alignment: .trailing)
        }
        .font(DesignSystem.Typography.caption)
        .fontWeight(.semibold)
        .foregroundColor(DesignSystem.Colors.secondaryText)
        .textCase(.uppercase)
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            ProgressView()
                .controlSize(.large)

            Text("Analyzing files...")
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
            Text("Error loading files")
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
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundColor(.gray)
                    .opacity(0.7)

                VStack(spacing: DesignSystem.Spacing.small) {
                    Text("No Files Found")
                        .font(DesignSystem.Typography.headline)

                    Text("No files match your current filters")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(DesignSystem.Spacing.xxxLarge)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(DesignSystem.CornerRadius.card)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.sectionPadding)
    }

    // MARK: - Logic

    private func calculateColumns(availableWidth: CGFloat, driveCount: Int) -> Int {
        // Special case: only one drive indexed
        if driveCount == 1 {
            return 1
        }

        // Account for padding
        let effectiveWidth = availableWidth - (DesignSystem.Spacing.sectionPadding * 2)

        // Define breakpoints for column counts
        // Assuming minimum card width of ~140px plus spacing
        let minCardWidth: CGFloat = 140
        let spacing = DesignSystem.Card.gridSpacing

        // Calculate maximum columns that could fit
        let maxPossibleColumns = Int((effectiveWidth + spacing) / (minCardWidth + spacing))

        // Determine breakpoint based on available width
        let breakpoint: Int
        if maxPossibleColumns >= 6 {
            breakpoint = 6 // Max width breakpoint
        } else if maxPossibleColumns >= 4 {
            breakpoint = 4 // Mid point breakpoint
        } else {
            breakpoint = 2 // Min width breakpoint
        }

        // Return the minimum of breakpoint and actual drive count
        // This ensures drives fill the width when there are fewer than the breakpoint allows
        return min(breakpoint, driveCount)
    }

    private func calculateGridHeight(driveCount: Int, columns: Int) -> CGFloat {
        // Estimate height per card (includes padding, content, and spacing)
        let estimatedCardHeight: CGFloat = 120

        // Calculate how many rows we'll need based on actual columns
        guard columns > 0 else { return estimatedCardHeight }
        let rows = ceil(Double(driveCount) / Double(columns))

        return CGFloat(rows) * estimatedCardHeight + DesignSystem.Card.gridSpacing * CGFloat(max(0, rows - 1))
    }

    private func getHighlightStatus(driveId: String) -> DriveHighlightStatus {
        guard let fileId = hoveredFileId,
              let file = allFiles.first(where: { $0.id == fileId }) else {
            return .none
        }

        let hasFile = file.driveIds.contains(driveId)
        if !hasFile {
            return .dimmed
        }

        let isBackup = driveStates[driveId] ?? false

        // Check if this drive has multiple copies of the file
        let copiesOnThisDrive = file.driveIds.filter { $0 == driveId }.count
        if copiesOnThisDrive > 1 {
            // Multiple copies on same drive = always a duplicate (orange)
            return .warning
        }

        let sourceDrives = file.driveIds.filter { !(driveStates[$0] ?? false) }
        let backupDrives = file.driveIds.filter { driveStates[$0] ?? false }

        // Single source + backup(s) scenario
        if sourceDrives.count == 1 && backupDrives.count >= 1 {
            return isBackup ? .safe : .sourceSafe
        }

        return isBackup ? .safe : .warning
    }

    private var filteredFiles: [MultiDriveFile] {
        allFiles.filter { file in
            // Get backup and source drives for this file
            let backupDrives = file.driveIds.filter { driveStates[$0] ?? false }
            let sourceDrives = file.driveIds.filter { !(driveStates[$0] ?? false) }

            // File is only "backed up" if it exists on at least one backup drive AND at least one other drive
            let isBackedUp = !backupDrives.isEmpty && !sourceDrives.isEmpty
            let hasRedundantSource = sourceDrives.count > 1
            let hasRedundantBackup = backupDrives.count > 1
            let isUnsafe = backupDrives.isEmpty

            // Show if it matches "Backed Up" filter
            if showBackedUp && isBackedUp {
                return true
            }

            // Show if it matches "Duplicates" filter
            // Duplicates include: multiple sources, multiple backups, or no backup at all
            if showDuplicates && (hasRedundantSource || hasRedundantBackup || isUnsafe) {
                return true
            }

            return false
        }
    }

    private var sortedFiles: [MultiDriveFile] {
        filteredFiles.sorted { lhs, rhs in
            switch sortOption {
            case .size:
                return lhs.size > rhs.size
            case .name:
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            case .copies:
                return lhs.locations.count > rhs.locations.count
            }
        }
    }

    // MARK: - Lazy Loading

    private func shouldLoadMore(currentIndex: Int) -> Bool {
        guard !isLoadingMore else { return false }

        let itemsFromEnd = displayedFiles.count - currentIndex
        let hasMore = displayedFiles.count < sortedFiles.count

        return itemsFromEnd <= loadMoreThreshold && hasMore
    }

    private func loadMoreFiles() {
        guard !isLoadingMore else { return }

        isLoadingMore = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let currentCount = displayedFiles.count
            let totalCount = sortedFiles.count
            let nextBatch = min(batchSize, totalCount - currentCount)

            if nextBatch > 0 {
                let newFiles = Array(sortedFiles[currentCount..<(currentCount + nextBatch)])
                displayedFiles.append(contentsOf: newFiles)
            }

            isLoadingMore = false
        }
    }

    private func resetDisplayedFiles() {
        let initialBatch = min(batchSize, sortedFiles.count)
        displayedFiles = Array(sortedFiles.prefix(initialBatch))
    }

    // MARK: - Data Loading

    private func loadFiles() async {
        isLoading = true
        errorMessage = nil

        do {
            // Get all duplicate groups from the database
            let groups = try await DatabaseManager.shared.getDuplicateGroups()

            // Convert to MultiDriveFile format
            var multiDriveFiles: [MultiDriveFile] = []

            for group in groups {
                // Only include files that exist on 2+ drives
                guard group.files.count >= 2 else { continue }

                let locations = group.files.map { file in
                    FileLocation(
                        id: file.id,
                        driveId: file.driveUUID,
                        relativePath: file.relativePath
                    )
                }

                // Use the most recent modified date
                let mostRecentDate = group.files.compactMap { $0.modifiedAt }.max()

                multiDriveFiles.append(MultiDriveFile(
                    id: "\(group.name)-\(group.size)",
                    name: group.name,
                    size: group.size,
                    locations: locations,
                    modifiedAt: mostRecentDate
                ))
            }

            allFiles = multiDriveFiles
            resetDisplayedFiles()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func revealFirstLocation(_ file: MultiDriveFile) {
        guard let firstLocation = file.locations.first,
              let drive = driveMonitor.drives.first(where: { $0.id == firstLocation.driveId }) else {
            NSSound.beep()
            return
        }

        let volumePath = "/Volumes/\(drive.name)"
        let fullPath = volumePath + "/" + firstLocation.relativePath
        let url = URL(fileURLWithPath: fullPath)

        if FileManager.default.fileExists(atPath: fullPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSSound.beep()
        }
    }
}

// MARK: - Drive Grid Card

enum DriveHighlightStatus {
    case none
    case warning
    case safe
    case sourceSafe
    case dimmed
}

struct DriveGridCard: View {
    let drive: DriveInfo
    let isBackup: Bool
    let highlightStatus: DriveHighlightStatus
    let onToggleBackup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Top row: Status dot + Drive name + Capacity badge
            HStack(spacing: 6) {
                Circle()
                    .fill(drive.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(drive.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if drive.totalCapacity > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive")
                            .font(.caption2)
                        Text(drive.formattedTotal)
                            .font(AppTypography.capacityInfo)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .fixedSize()
                }
            }

            // Info row: Capacity + file count
            HStack(spacing: Spacing.medium) {
                if drive.totalCapacity > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "externaldrive")
                            .font(.caption2)
                        Text("\(drive.formattedUsed) / \(drive.formattedTotal)")
                            .font(AppTypography.technicalData)
                    }
                    .foregroundColor(.secondary)
                }

                if drive.fileCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text("\(drive.fileCount.formatted()) files")
                            .font(AppTypography.technicalData)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Toggle switch
            HStack {
                Spacer()

                HStack(spacing: 4) {
                    Toggle("", isOn: Binding(
                        get: { isBackup },
                        set: { _ in onToggleBackup() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Text("Backup")
                        .font(.system(size: 10))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(Spacing.medium)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: highlightStatus == .none ? 1 : 1.5)
        )
        .shadow(color: shadowColor, radius: shadowRadius)
        .opacity(highlightStatus == .dimmed ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: highlightStatus)
    }

    private var backgroundColor: Color {
        switch highlightStatus {
        case .warning: return Color.orange.opacity(0.08)
        case .safe: return Color.green.opacity(0.08)
        case .sourceSafe: return Color.secondary.opacity(0.08)
        default: return drive.backgroundColor
        }
    }

    private var borderColor: Color {
        switch highlightStatus {
        case .warning: return Color.orange.opacity(0.5)
        case .safe: return Color.green.opacity(0.5)
        case .sourceSafe: return Color.secondary.opacity(0.5)
        default: return drive.borderColor ?? Color.clear
        }
    }

    private var shadowColor: Color {
        switch highlightStatus {
        case .warning: return Color.orange.opacity(0.3)
        case .safe: return Color.green.opacity(0.3)
        case .sourceSafe: return Color.secondary.opacity(0.3)
        default: return Color.clear
        }
    }

    private var shadowRadius: CGFloat {
        highlightStatus == .none || highlightStatus == .dimmed ? 0 : 8
    }
}

// MARK: - Duplicate File Row

struct DuplicateFileRow: View {
    let file: MultiDriveFile
    let driveStates: [String: Bool]
    let drives: [DriveInfo]
    let isHovered: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // File icon and name
            HStack(spacing: DesignSystem.Spacing.medium) {
                Image(systemName: fileIcon)
                    .font(.title3)
                    .foregroundColor(fileIconColor)
                    .frame(width: 24)

                Text(file.name)
                    .font(DesignSystem.Typography.body)
                    .lineLimit(1)
                    .foregroundColor(
                        isHovered
                            ? DesignSystem.Colors.accent
                            : DesignSystem.Colors.primaryText
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Size
            Text(file.formattedSize)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 100, alignment: .trailing)

            // Copies count
            Text("\(file.locations.count)")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.primaryText)
                .frame(width: 80, alignment: .center)

            // Date
            Text(file.formattedDate)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.medium)
        .background(
            isHovered
                ? DesignSystem.Colors.cardBackgroundHover
                : Color.clear
        )
        .contentShape(Rectangle())
    }

    private var fileIcon: String {
        switch file.fileType {
        case "video": return "video.fill"
        case "image": return "photo.fill"
        case "audio": return "music.note"
        case "database": return "cylinder.fill"
        default: return "doc.fill"
        }
    }

    private var fileIconColor: Color {
        switch file.fileType {
        case "video": return .purple
        case "image": return .blue
        case "audio": return .pink
        case "database": return .gray
        default: return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    DuplicatesView()
        .environmentObject(DriveMonitor())
        .frame(width: 900, height: 700)
}
