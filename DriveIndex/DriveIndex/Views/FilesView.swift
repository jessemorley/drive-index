//
//  FilesView.swift
//  DriveIndex
//
//  View for recently indexed files with Finder-style detail view
//

import SwiftUI
import UniformTypeIdentifiers

enum FileSortColumn: String {
    case name = "Name"
    case size = "Size"
    case kind = "Kind"
    case dateAdded = "Date Added"
}

enum SortDirection {
    case ascending
    case descending

    var icon: String {
        switch self {
        case .ascending: return "chevron.up"
        case .descending: return "chevron.down"
        }
    }

    func toggled() -> SortDirection {
        switch self {
        case .ascending: return .descending
        case .descending: return .ascending
        }
    }
}

struct FileDisplayItem: Identifiable {
    let id: Int64
    let name: String
    let relativePath: String
    let size: Int64
    let driveUUID: String
    let driveName: String
    let modifiedAt: Date?
    let createdAt: Date?
    let isConnected: Bool
    let isDirectory: Bool

    var kind: String {
        // Folders are always "Folder"
        if isDirectory {
            return "Folder"
        }

        let ext = (name as NSString).pathExtension.lowercased()

        // Common file type mappings
        switch ext {
        case "pdf": return "PDF Document"
        case "doc", "docx": return "Word Document"
        case "xls", "xlsx": return "Excel Spreadsheet"
        case "ppt", "pptx": return "PowerPoint Presentation"
        case "txt": return "Plain Text"
        case "rtf": return "Rich Text Document"
        case "jpg", "jpeg": return "JPEG Image"
        case "png": return "PNG Image"
        case "gif": return "GIF Image"
        case "svg": return "SVG Image"
        case "heic", "heif": return "HEIC Image"
        case "tiff", "tif": return "TIFF Image"
        case "bmp": return "BMP Image"
        case "webp": return "WebP Image"
        // Raw image formats
        case "nef": return "Nikon RAW Image"
        case "cr2", "cr3": return "Canon RAW Image"
        case "arw": return "Sony RAW Image"
        case "dng": return "Digital Negative"
        case "raf": return "Fujifilm RAW Image"
        case "orf": return "Olympus RAW Image"
        case "rw2": return "Panasonic RAW Image"
        case "pef": return "Pentax RAW Image"
        case "srw": return "Samsung RAW Image"
        case "raw": return "RAW Image"
        case "mp4", "mov": return "Video"
        case "mp3", "m4a", "wav": return "Audio"
        case "zip", "tar", "gz": return "Archive"
        case "dmg": return "Disk Image"
        case "app": return "Application"
        case "pkg": return "Installer Package"
        case "swift": return "Swift Source"
        case "py": return "Python Script"
        case "js": return "JavaScript"
        case "html": return "HTML Document"
        case "css": return "CSS Stylesheet"
        case "json": return "JSON File"
        case "md": return "Markdown Document"
        default:
            if ext.isEmpty {
                return "Document"
            }
            return ext.uppercased() + " File"
        }
    }

    var formattedSize: String {
        if isDirectory {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modifiedAt ?? createdAt else {
            return "—" // Em dash for search results without dates
        }

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
}

struct FilesView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @Environment(AppSearchState.self) private var appSearchState

    @State private var files: [FileDisplayItem] = []
    @State private var searchResults: [FileDisplayItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var sortColumn: FileSortColumn = .dateAdded
    @State private var sortDirection: SortDirection = .descending
    @State private var selectedDriveFilter: String? = nil
    @State private var hoveredFileID: Int64?
    @State private var loadedCount = 0
    @State private var hasMoreFiles = true

    private let batchSize = 100
    private let loadMoreThreshold = 20 // Load more when within 20 items of the end
    private let searchManager = SearchManager()

    // Use shared search text from AppSearchState
    private var searchText: String {
        appSearchState.searchText
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main content
                Group {
                    if isLoading {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if displayedFiles.isEmpty {
                        emptyStateView
                    } else {
                        filesTableView
                    }
                }
            }
            .navigationTitle("Files")
            .navigationSubtitle(subtitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar(id: "files-toolbar") {
                ToolbarItem(id: "filter", placement: .automatic) {
                    filterMenu
                }

                ToolbarItem(id: "refresh", placement: .automatic) {
                    Button(action: {
                        Task {
                            await refreshFiles()
                        }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh file list")
                }
            }
        }
        .task {
            await loadInitialFiles()
        }
        .onChange(of: appSearchState.searchText) { oldValue, newValue in
            Task {
                await performSearch(newValue)
            }
        }
    }

    // MARK: - Computed Properties

    /// Files to display - either search results or lazy-loaded files
    private var displayedFiles: [FileDisplayItem] {
        if !searchText.isEmpty {
            return searchResults
        } else {
            return files
        }
    }

    private var subtitle: String {
        let count = filteredFiles.count
        if searchText.isEmpty {
            if hasMoreFiles && !isLoading {
                return "\(count)+ file\(count == 1 ? "" : "s")"
            }
            return "\(count) file\(count == 1 ? "" : "s")"
        } else {
            if isSearching {
                return "Searching..."
            }
            return "\(count) result\(count == 1 ? "" : "s")"
        }
    }

    // MARK: - Files Table View

    private var filesTableView: some View {
        VStack(spacing: 0) {
            // Table header
            tableHeader

            Divider()

            // File rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedFiles.enumerated()), id: \.element.id) { index, file in
                        FileRow(
                            file: file,
                            isHovered: hoveredFileID == file.id,
                            isSelected: appSearchState.selectedFile?.id == file.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Single click selects the file and shows inspector
                            appSearchState.selectFile(file)
                        }
                        .onTapGesture(count: 2) {
                            // Double click reveals in Finder
                            revealInFinder(file)
                        }
                        .onHover { isHovering in
                            hoveredFileID = isHovering ? file.id : nil
                        }
                        .contextMenu {
                            Button("Show in Finder") {
                                revealInFinder(file)
                            }
                            Button("Show Inspector") {
                                appSearchState.selectFile(file)
                            }
                        }
                        .onAppear {
                            // Load more when approaching the end
                            if shouldLoadMore(currentIndex: index) {
                                Task {
                                    await loadMoreFiles()
                                }
                            }
                        }

                        if file.id != sortedFiles.last?.id {
                            Divider()
                                .padding(.leading, DesignSystem.Spacing.cardPadding)
                        }
                    }

                    // Loading indicator at bottom (only for lazy loading, not search)
                    if isLoadingMore && searchText.isEmpty {
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Should Load More

    private func shouldLoadMore(currentIndex: Int) -> Bool {
        // Only load more if:
        // 1. Not currently loading
        // 2. We have more files to load
        // 3. We're within threshold of the end
        // 4. Search is empty (don't auto-load during search)
        guard !isLoadingMore && hasMoreFiles && searchText.isEmpty else {
            return false
        }

        let itemsFromEnd = sortedFiles.count - currentIndex
        return itemsFromEnd <= loadMoreThreshold
    }

    // MARK: - Table Header

    private var tableHeader: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Name column (flexible with minimum width)
            columnHeader(
                title: "Name",
                column: .name,
                alignment: .leading,
                width: nil
            )
            .frame(minWidth: 250)

            // Size column (fixed width)
            columnHeader(
                title: "Size",
                column: .size,
                alignment: .trailing,
                width: 80
            )

            // Kind column (fixed width)
            columnHeader(
                title: "Kind",
                column: .kind,
                alignment: .leading,
                width: 140
            )

            // Drive column (fixed width) - not sortable
            Button(action: {}) {
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    Text("Drive")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                .frame(width: 120, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(true)

            // Date Added column (fixed width)
            columnHeader(
                title: "Date Added",
                column: .dateAdded,
                alignment: .leading,
                width: 140
            )
        }
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.small)
    }

    @ViewBuilder
    private func columnHeader(
        title: String,
        column: FileSortColumn,
        alignment: Alignment,
        width: CGFloat?
    ) -> some View {
        let isActive = sortColumn == column && searchText.isEmpty

        Button(action: {
            if sortColumn == column {
                sortDirection = sortDirection.toggled()
            } else {
                sortColumn = column
                // Default direction based on column type
                sortDirection = column == .dateAdded ? .descending : .ascending
            }
        }) {
            HStack(spacing: DesignSystem.Spacing.xSmall) {
                Text(title)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isActive ? DesignSystem.Colors.primaryText : DesignSystem.Colors.secondaryText)

                if isActive {
                    Image(systemName: sortDirection.icon)
                        .font(.system(size: 10))
                        .foregroundColor(DesignSystem.Colors.primaryText)
                }
            }
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(searchText.isEmpty ? "Sort by \(title.lowercased())" : "Sorting disabled during search")
        .disabled(!searchText.isEmpty)
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            ProgressView()
                .controlSize(.large)

            Text("Loading files...")
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
                Image(systemName: "doc.text")
                    .font(.system(size: 56))
                    .foregroundColor(.gray)
                    .opacity(0.7)

                VStack(spacing: DesignSystem.Spacing.small) {
                    Text("No Files Found")
                        .font(DesignSystem.Typography.headline)

                    Text(searchText.isEmpty ? "Index a drive to see recently added files" : "No files match your search")
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

    // MARK: - Toolbar Items

    private var filterMenu: some View {
        Menu {
            Button(action: { selectedDriveFilter = nil }) {
                if selectedDriveFilter == nil {
                    Label("All Drives", systemImage: "checkmark")
                } else {
                    Text("All Drives")
                }
            }

            if !driveMonitor.drives.isEmpty {
                Divider()

                ForEach(driveMonitor.drives, id: \.id) { drive in
                    Button(action: { selectedDriveFilter = drive.id }) {
                        if selectedDriveFilter == drive.id {
                            Label(drive.name, systemImage: "checkmark")
                        } else {
                            Text(drive.name)
                        }
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter by drive")
    }

    // MARK: - Search

    private func performSearch(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        do {
            let results = try await searchManager.search(query)
            // Convert SearchResult to FileDisplayItem
            searchResults = results.map { result in
                FileDisplayItem(
                    id: result.id,
                    name: result.name,
                    relativePath: result.relativePath,
                    size: result.size,
                    driveUUID: result.driveUUID,
                    driveName: result.driveName,
                    modifiedAt: nil, // SearchResult doesn't include dates
                    createdAt: nil,
                    isConnected: result.isConnected,
                    isDirectory: result.isDirectory
                )
            }
        } catch {
            print("Search error: \(error)")
            searchResults = []
        }

        isSearching = false
    }

    // MARK: - Data Loading

    private func loadInitialFiles() async {
        isLoading = true
        errorMessage = nil
        loadedCount = 0
        hasMoreFiles = true

        do {
            // Load initial batch
            let entries = try await DatabaseManager.shared.getRecentFiles(limit: batchSize, offset: 0)

            // Convert to display items
            let displayItems = convertToDisplayItems(entries)

            files = displayItems
            loadedCount = entries.count
            hasMoreFiles = entries.count == batchSize
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadMoreFiles() async {
        guard !isLoadingMore && hasMoreFiles else { return }

        isLoadingMore = true

        do {
            // Load next batch using offset
            let entries = try await DatabaseManager.shared.getRecentFiles(limit: batchSize, offset: loadedCount)

            if !entries.isEmpty {
                let newDisplayItems = convertToDisplayItems(entries)
                files.append(contentsOf: newDisplayItems)
                loadedCount += entries.count
                hasMoreFiles = entries.count == batchSize
            } else {
                hasMoreFiles = false
            }
        } catch {
            print("Error loading more files: \(error.localizedDescription)")
            hasMoreFiles = false
        }

        isLoadingMore = false
    }

    private func refreshFiles() async {
        // Reset and reload
        files = []
        await loadInitialFiles()
    }

    private func convertToDisplayItems(_ entries: [FileEntry]) -> [FileDisplayItem] {
        var displayItems: [FileDisplayItem] = []

        for entry in entries {
            // Find the drive for this file
            let drive = driveMonitor.drives.first(where: { $0.id == entry.driveUUID })
            let driveName = drive?.name ?? "Unknown"
            let isConnected = drive?.isConnected ?? false

            displayItems.append(FileDisplayItem(
                id: entry.id ?? 0,
                name: entry.name,
                relativePath: entry.relativePath,
                size: entry.size,
                driveUUID: entry.driveUUID,
                driveName: driveName,
                modifiedAt: entry.modifiedAt,
                createdAt: entry.createdAt,
                isConnected: isConnected,
                isDirectory: entry.isDirectory
            ))
        }

        return displayItems
    }

    // MARK: - Filtering and Sorting

    private var filteredFiles: [FileDisplayItem] {
        var results = displayedFiles

        // Filter by drive if selected
        if let driveId = selectedDriveFilter {
            results = results.filter { $0.driveUUID == driveId }
        }

        return results
    }

    private var sortedFiles: [FileDisplayItem] {
        // When searching, preserve BM25 ranking order from FTS5
        guard searchText.isEmpty else {
            return filteredFiles
        }

        // Apply custom sorting when browsing
        return filteredFiles.sorted { lhs, rhs in
            let result: Bool
            switch sortColumn {
            case .dateAdded:
                // Higher ID = more recent
                result = lhs.id > rhs.id
            case .name:
                result = lhs.name.localizedCompare(rhs.name) == .orderedAscending
            case .size:
                result = lhs.size > rhs.size
            case .kind:
                let lhsKind = lhs.kind
                let rhsKind = rhs.kind
                if lhsKind == rhsKind {
                    return lhs.name.localizedCompare(rhs.name) == .orderedAscending
                }
                result = lhsKind.localizedCompare(rhsKind) == .orderedAscending
            }

            // Apply sort direction
            return sortDirection == .ascending ? result : !result
        }
    }

    // MARK: - Actions

    private func revealInFinder(_ file: FileDisplayItem) {
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

// MARK: - File Row Component

struct FileRow: View {
    let file: FileDisplayItem
    let isHovered: Bool
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // File icon and name (flexible with minimum width)
            HStack(spacing: DesignSystem.Spacing.medium) {
                fileIcon
                    .frame(width: 24)

                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    Text(file.name)
                        .font(DesignSystem.Typography.body)
                        .lineLimit(1)

                    Text("—")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)

                    Text(file.relativePath)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 250, maxWidth: .infinity, alignment: .leading)

            // Size (fixed width)
            Text(file.formattedSize)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 80, alignment: .trailing)

            // Kind (fixed width)
            Text(file.kind)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            // Drive (fixed width) with status indicator
            HStack(spacing: DesignSystem.Spacing.xSmall) {
                Circle()
                    .fill(file.isConnected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)

                Text(file.driveName)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)

            // Date Added (fixed width)
            Text(file.formattedDate)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .padding(.horizontal, DesignSystem.Spacing.cardPadding)
        .padding(.vertical, DesignSystem.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected ? Color.accentColor.opacity(0.15) :
                    isHovered ? DesignSystem.Colors.cardBackgroundHover : Color.clear
                )
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
    }

    private var fileIcon: some View {
        let iconName: String
        let iconColor: Color

        // Show folder icon for directories
        if file.isDirectory {
            iconName = "folder.fill"
            iconColor = .blue
        } else {
            let ext = (file.name as NSString).pathExtension.lowercased()

            switch ext {
            case "pdf":
                iconName = "doc.fill"
                iconColor = .red
            case "doc", "docx":
                iconName = "doc.text.fill"
                iconColor = .blue
            case "xls", "xlsx":
                iconName = "tablecells.fill"
                iconColor = .green
            case "ppt", "pptx":
                iconName = "square.fill.text.grid.1x2"
                iconColor = .orange
            case "txt", "rtf":
                iconName = "doc.plaintext.fill"
                iconColor = .gray
            case "jpg", "jpeg", "png", "gif", "svg", "heic", "heif", "tiff", "tif", "bmp", "webp",
                 "nef", "cr2", "cr3", "arw", "dng", "raf", "orf", "rw2", "pef", "srw", "raw":
                iconName = "photo.fill"
                iconColor = .purple
            case "mp4", "mov":
                iconName = "video.fill"
                iconColor = .pink
            case "mp3", "m4a", "wav":
                iconName = "music.note"
                iconColor = .orange
            case "zip", "tar", "gz":
                iconName = "doc.zipper"
                iconColor = .gray
            case "dmg":
                iconName = "externaldrive.fill"
                iconColor = .gray
            case "app":
                iconName = "app.fill"
                iconColor = .blue
            case "swift":
                iconName = "chevron.left.forwardslash.chevron.right"
                iconColor = .orange
            case "py", "js", "html", "css":
                iconName = "chevron.left.forwardslash.chevron.right"
                iconColor = .green
            default:
                iconName = "doc.fill"
                iconColor = .blue
            }
        }

        return Image(systemName: iconName)
            .foregroundColor(iconColor)
            .font(.title3)
    }
}

#Preview {
    FilesView()
        .environmentObject(DriveMonitor())
}
