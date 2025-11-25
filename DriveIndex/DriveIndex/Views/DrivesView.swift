//
//  DrivesView.swift
//  DriveIndex
//
//  Main drives view with toolbar for list/grid toggle, sorting, and search
//

import SwiftUI

enum DriveViewMode: String, CaseIterable {
    case list
    case grid

    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
}

enum DriveSortOption: String, CaseIterable {
    case name = "Name"
    case capacity = "Capacity"
    case lastScanned = "Last Scanned"
}

struct DrivesView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @Binding var selectedItem: NavigationItem?

    @State private var viewMode: DriveViewMode = .list
    @State private var sortOption: DriveSortOption = .name

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewMode == .list {
                    LazyVStack(spacing: DesignSystem.Spacing.small) {
                        ForEach(sortedDrives) { drive in
                            NavigationLink(value: drive) {
                                DriveDetailCard(drive: drive)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DesignSystem.Spacing.sectionPadding)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: DesignSystem.Card.gridSpacing),
                        GridItem(.flexible(), spacing: DesignSystem.Card.gridSpacing)
                    ], spacing: DesignSystem.Card.gridSpacing) {
                        ForEach(sortedDrives) { drive in
                            NavigationLink(value: drive) {
                                DriveCard(drive: drive)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DesignSystem.Spacing.sectionPadding)
                }
            }
            .navigationTitle("Drives")
            .toolbar(id: "drives-toolbar") {
                ToolbarItem(id: "view-mode", placement: .automatic) {
                    Picker("View", selection: $viewMode) {
                        ForEach(DriveViewMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue.capitalized, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Change view mode")
                }

                ToolbarItem(id: "sort", placement: .automatic) {
                    Menu {
                        ForEach(DriveSortOption.allCases, id: \.self) { option in
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
                    .help("Sort drives")
                }
            }
            .navigationDestination(for: DriveInfo.self) { drive in
                DriveDetailView(drive: drive)
                    .onAppear {
                        // Update sidebar selection when navigating to a drive
                        selectedItem = .drive(drive)
                    }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var sortedDrives: [DriveInfo] {
        var drives = driveMonitor.drives

        // Sort
        switch sortOption {
        case .name:
            drives.sort { $0.name < $1.name }
        case .capacity:
            drives.sort { $0.totalCapacity > $1.totalCapacity }
        case .lastScanned:
            drives.sort { drive1, drive2 in
                guard let date1 = drive1.lastScanDate else { return false }
                guard let date2 = drive2.lastScanDate else { return true }
                return date1 > date2
            }
        }

        return drives
    }
}

// MARK: - Drive Card (Grid View)

struct DriveCard: View {
    let drive: DriveInfo
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

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

            // Capacity bar
            if drive.totalCapacity > 0 {
                CapacityBar(
                    used: drive.usedCapacity,
                    total: drive.totalCapacity,
                    percentage: drive.usedPercentage,
                    isConnected: drive.isConnected,
                    height: 5
                )
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

            // Last scanned (underneath capacity/files info)
            Text("Last scanned: \(drive.formattedLastScan)")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Action buttons: Rescan and Reveal on left, Eject on right
            HStack(spacing: Spacing.small) {
                Button(action: {
                    scanDrive(drive)
                }) {
                    Label(drive.lastScanDate == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(indexManager.isIndexing || !drive.isConnected)

                Button(action: {
                    revealInFinder(drive)
                }) {
                    Label("Reveal", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!drive.isConnected)

                Spacer()

                Button(action: {
                    ejectDrive(drive)
                }) {
                    Label("Eject", systemImage: "eject")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!drive.isConnected)
                .help("Eject drive")
            }
        }
        .padding(Spacing.medium)
        .background(drive.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(drive.borderColor ?? Color.clear, lineWidth: 1)
        )
    }

    private func scanDrive(_ drive: DriveInfo) {
        guard let driveURL = driveMonitor.getDriveURL(for: drive) else {
            return
        }

        Task {
            await indexManager.indexDrive(url: driveURL, uuid: drive.id)
        }
    }

    private func revealInFinder(_ drive: DriveInfo) {
        guard let driveURL = driveMonitor.getDriveURL(for: drive) else {
            return
        }

        NSWorkspace.shared.open(driveURL)
    }

    private func ejectDrive(_ drive: DriveInfo) {
        guard let driveURL = driveMonitor.getDriveURL(for: drive) else {
            return
        }

        try? NSWorkspace.shared.unmountAndEjectDevice(at: driveURL)
    }
}

// MARK: - Drive Detail Card (List View)

struct DriveDetailCard: View {
    let drive: DriveInfo
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Top row: Drive name + capacity badge
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

            // Capacity bar (full width)
            if drive.totalCapacity > 0 {
                CapacityBar(
                    used: drive.usedCapacity,
                    total: drive.totalCapacity,
                    percentage: drive.usedPercentage,
                    isConnected: drive.isConnected,
                    height: 5
                )
            }

            // Info row: Capacity + file count + last scanned
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

                Text("Last scanned: \(drive.formattedLastScan)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Action buttons: Rescan and Reveal on left, Eject on right
            if drive.isConnected {
                HStack(spacing: Spacing.small) {
                    Button(action: {
                        rescanDrive()
                    }) {
                        Label(drive.lastScanDate == nil ? "Scan" : "Rescan", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(indexManager.isIndexing)

                    Button(action: {
                        revealInFinder()
                    }) {
                        Label("Reveal", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(action: {
                        ejectDrive()
                    }) {
                        Label("Eject", systemImage: "eject")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Eject drive")
                }
            }
        }
        .padding(Spacing.medium)
        .background(drive.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(drive.borderColor ?? Color.clear, lineWidth: 1)
        )
    }

    private func rescanDrive() {
        // Un-exclude drive if it was excluded
        Task {
            await driveMonitor.unexcludeDrive(drive.id)
        }

        // Trigger drive rescan
        if let driveURL = driveMonitor.getDriveURL(for: drive) {
            Task {
                await indexManager.indexDrive(url: driveURL, uuid: drive.id)
            }
        }
    }

    private func revealInFinder() {
        if let driveURL = driveMonitor.getDriveURL(for: drive) {
            NSWorkspace.shared.open(driveURL)
        }
    }

    private func ejectDrive() {
        if let driveURL = driveMonitor.getDriveURL(for: drive) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: driveURL)
        }
    }
}

// MARK: - Preview

#Preview {
    DrivesView(selectedItem: .constant(.drives))
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 800, height: 600)
}
