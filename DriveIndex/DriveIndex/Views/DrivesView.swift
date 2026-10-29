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
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)]) {
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
            VStack(alignment: .leading, spacing: 14) {
                DriveSummary(drive: drive, stacksLastScanned: true)

                // Rescan and Show in Finder on left, Eject on right; disabled (not hidden) when
                // disconnected so every card in the grid is the same height
                HStack {
                    Button(drive.lastScanDate == nil ? "Scan" : "Rescan") {
                        scanDrive(drive)
                    }
                    .disabled(indexManager.isIndexing || !drive.isConnected)

                    Button("Show in Finder") {
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
            .padding(10)
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
            // One row, so the Form draws no separator between the summary and its buttons
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink(value: drive) {
                    DriveSummary(drive: drive)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // No chevron, so the bar and size line up with the buttons' right edge
                .navigationLinkIndicatorVisibility(.hidden)

                if drive.isConnected {
                    HStack {
                        Button(drive.lastScanDate == nil ? "Scan" : "Rescan", action: rescanDrive)
                            .disabled(indexManager.isIndexing)
                        Button("Show in Finder", action: revealInFinder)
                        Spacer()
                        Button("Eject", action: ejectDrive)
                            .help("Eject drive")
                    }
                }
            }
            .padding(.vertical, 10)
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
    /// Grid cards always put "Last scanned" on its own line; the list keeps it on the right
    var stacksLastScanned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // HStack, not LabeledContent: it only right-aligns the size inside a Form, and grid cards are GroupBoxes
            HStack {
                Image(nsImage: drive.finderIcon)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text(drive.name)
                    .lineLimit(1)
                ConnectionChip(isConnected: drive.isConnected)
                Spacer()
                if drive.totalCapacity > 0 {
                    Text(drive.formattedTotal)
                        .foregroundStyle(.secondary)
                }
            }

            if drive.totalCapacity > 0 {
                UsageBar(fraction: drive.usedPercentage / 100, color: fullnessColor)
                    .accessibilityLabel("\(drive.formattedUsed) of \(drive.formattedTotal) used")
            }

            // Last scanned moves under the details in grid cards, or when the list row is too narrow for both
            ViewThatFits(in: .horizontal) {
                if !stacksLastScanned {
                    HStack {
                        Text(details)
                        Spacer()
                        Text("Last scanned \(drive.formattedLastScan)")
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(details)
                    Text("Last scanned \(drive.formattedLastScan)")
                }
            }
            .lineLimit(1)
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

/// Thin capacity bar in the plain system color.
/// ponytail: drawn because ProgressView/Gauge wash their tint out in dark mode and can't change height
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
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
