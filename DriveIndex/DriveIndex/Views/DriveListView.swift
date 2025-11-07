//
//  DriveListView.swift
//  DriveIndexer
//
//  Displays list of drives with capacity bars
//

import SwiftUI

struct DriveListView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(driveMonitor.drives) { drive in
                    DriveRow(drive: drive)
                }
            }
            .padding()
        }
    }
}

struct DriveRow: View {
    let drive: DriveInfo
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack {
                Image(systemName: drive.isConnected ? "externaldrive.fill.badge.checkmark" : "externaldrive.fill")
                    .foregroundColor(drive.isConnected ? .green : .gray)
                    .font(.title3)

                Text(drive.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Circle()
                    .fill(drive.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }

            // Capacity bar
            if drive.isConnected {
                CapacityBar(
                    used: drive.usedCapacity,
                    total: drive.totalCapacity,
                    percentage: drive.usedPercentage
                )
            }

            // Info row
            HStack {
                if drive.isConnected {
                    Text("\(drive.formattedUsed) / \(drive.formattedTotal)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if drive.fileCount > 0 {
                    Text("\(drive.fileCount.formatted()) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Last scanned
            if let lastScan = drive.lastScanDate {
                Text("Last scanned: \(formatRelativeTime(lastScan))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if drive.isConnected {
                Text("Never scanned")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            // Actions
            HStack(spacing: 8) {
                if drive.isConnected {
                    Button(action: {
                        scanDrive(drive)
                    }) {
                        Label("Scan Now", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(indexManager.isIndexing)
                }

                Button(action: {
                    openInFinder(drive)
                }) {
                    Label("Open in Finder", systemImage: "folder")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!drive.isConnected)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private func scanDrive(_ drive: DriveInfo) {
        guard let driveURL = driveMonitor.getDriveURL(for: drive) else {
            return
        }

        Task {
            await indexManager.indexDrive(url: driveURL, uuid: drive.id)
        }
    }

    private func openInFinder(_ drive: DriveInfo) {
        guard let driveURL = driveMonitor.getDriveURL(for: drive) else {
            return
        }

        NSWorkspace.shared.open(driveURL)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct CapacityBar: View {
    let used: Int64
    let total: Int64
    let percentage: Double

    private var fillColor: Color {
        if percentage >= 90 {
            return .red
        } else if percentage >= 75 {
            return .orange
        } else if percentage >= 50 {
            return .yellow
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .cornerRadius(4)

                    // Fill
                    Rectangle()
                        .fill(fillColor)
                        .frame(width: geometry.size.width * (percentage / 100))
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)

            Text("\(Int(percentage))% full")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    DriveListView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 400, height: 500)
}
