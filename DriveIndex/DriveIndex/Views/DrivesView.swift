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
            Group {
                if viewMode == .list {
                    Form {
                        ForEach(sortedDrives) { drive in
                            DriveDetailCard(drive: drive)
                        }
                    }
                    .formStyle(.grouped)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                            ForEach(sortedDrives) { drive in
                                NavigationLink(value: drive) {
                                    DriveCard(drive: drive)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
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
        GroupBox {
            VStack(alignment: .leading) {
                DriveSummary(drive: drive)

                // Rescan and Reveal on left, Eject on right
                HStack {
                    Button(drive.lastScanDate == nil ? "Scan" : "Rescan") {
                        scanDrive(drive)
                    }
                    .disabled(indexManager.isIndexing || !drive.isConnected)

                    Button("Reveal in Finder") {
                        revealInFinder(drive)
                    }
                    .disabled(!drive.isConnected)

                    Spacer()

                    Button("Eject") {
                        ejectDrive(drive)
                    }
                    .disabled(!drive.isConnected)
                    .help("Eject drive")
                }
            }
        }
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
        Section {
            NavigationLink(value: drive) {
                DriveSummary(drive: drive)
            }

            if drive.isConnected {
                HStack {
                    Spacer()
                    Button(drive.lastScanDate == nil ? "Scan" : "Rescan", action: rescanDrive)
                        .disabled(indexManager.isIndexing)
                    Button("Show in Finder", action: revealInFinder)
                    Button("Eject", action: ejectDrive)
                        .help("Eject drive")
                }
            }
        }
    }

    private func rescanDrive() {
        // Un-exclude drive if it was excluded
        Task {
            await driveMonitor.unexcludeDrive(drive.id)
        }

        // Trigger drive rescan (no changed paths = full mount scan)
        // ponytail: history can miss non-Mac writes; Rescan forces a full mount scan
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

/// Name, status, capacity and scan info shared by the list rows and grid cards.
struct DriveSummary: View {
    let drive: DriveInfo

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent {
                if drive.totalCapacity > 0 {
                    Text(drive.formattedTotal)
                }
            } label: {
                HStack {
                    Text(drive.name)
                        .lineLimit(1)
                    ConnectionChip(isConnected: drive.isConnected)
                }
            }

            if drive.totalCapacity > 0 {
                ProgressView(value: drive.usedPercentage, total: 100)
                    .tint(fullnessColor)
            }

            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var details: String {
        var parts: [String] = []
        if drive.totalCapacity > 0 {
            parts.append("\(drive.formattedUsed) of \(drive.formattedTotal) used")
        }
        if drive.fileCount > 0 {
            parts.append("\(drive.fileCount.formatted()) files")
        }
        parts.append("Last scanned \(drive.formattedLastScan)")
        return parts.joined(separator: " · ")
    }

    /// Gray when disconnected, otherwise green → yellow → orange → red as the drive fills
    private var fullnessColor: Color {
        if !drive.isConnected { return .gray }
        switch drive.usedPercentage {
        case 90...: return .red
        case 75...: return .orange
        case 50...: return .yellow
        default: return .green
        }
    }
}

// MARK: - Preview

#Preview {
    let monitor = DriveMonitor()
    monitor.drives = [
        DriveInfo(id: "a", name: "Jesse T72", path: "/Volumes/Jesse T72", totalCapacity: 2_000_000_000_000, availableCapacity: 300_000_000_000,
                  isConnected: true, lastSeen: Date(), lastScanDate: Date(timeIntervalSinceNow: -7200), fileCount: 184_220, isExcluded: false),
        DriveInfo(id: "b", name: "Archive", path: "/Volumes/Archive", totalCapacity: 4_000_000_000_000, availableCapacity: 2_500_000_000_000,
                  isConnected: false, lastSeen: Date(), lastScanDate: Date(timeIntervalSinceNow: -86400 * 12), fileCount: 902_113, isExcluded: false),
    ]
    return DrivesView(selectedItem: .constant(.drives))
        .environmentObject(monitor)
        .environmentObject(IndexManager())
        .frame(width: 600, height: 600)
}
