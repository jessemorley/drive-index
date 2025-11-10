//
//  DriveListView.swift
//  DriveIndex
//
//  Displays list of drives with capacity bars
//

import SwiftUI

struct DriveListView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.medium) {
                ForEach(driveMonitor.drives) { drive in
                    DriveRow(drive: drive)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
            }
            .padding(.horizontal, Spacing.Container.horizontalPadding)
            .padding(.vertical, Spacing.Container.verticalPadding)
            .animation(.easeInOut(duration: 0.3), value: driveMonitor.drives.count)
        }
    }
}

struct DriveRow: View {
    let drive: DriveInfo
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Header: Drive name + status
            HStack(spacing: Spacing.medium) {
                Circle()
                    .fill(drive.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(drive.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                if !drive.isConnected {
                    DriveStatusBadge(isConnected: false, isIndexing: false)
                }
            }

            // Capacity visualization
            CapacityBar(
                used: drive.usedCapacity,
                total: drive.totalCapacity,
                percentage: drive.usedPercentage,
                isConnected: drive.isConnected
            )

            // Info row: capacity + file count
            HStack(spacing: Spacing.large) {
                Label {
                    Text("\(drive.formattedUsed) / \(drive.formattedTotal)")
                        .font(AppTypography.technicalData)
                } icon: {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                if drive.fileCount > 0 {
                    Label {
                        Text("\(drive.fileCount.formatted()) files")
                            .font(AppTypography.technicalData)
                    } icon: {
                        Image(systemName: "doc.text")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }

            // Last scanned status
            if let lastScan = drive.lastScanDate {
                Text("Last scanned: \(formatRelativeTime(lastScan))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if drive.isConnected {
                HStack(spacing: Spacing.xSmall) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption2)
                    Text("Never scanned")
                        .font(.caption2)
                }
                .foregroundColor(.orange)
            }

            // Action buttons
            HStack(spacing: Spacing.medium) {
                if drive.isConnected {
                    Button(action: {
                        scanDrive(drive)
                    }) {
                        Label("Scan", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(indexManager.isIndexing)
                }

                Button(action: {
                    openInFinder(drive)
                }) {
                    Label("Finder", systemImage: "folder")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!drive.isConnected)
            }
        }
        .padding(Spacing.Container.headerPadding)
        .background(Color.secondary.opacity(isHovered ? 0.08 : 0.05))
        .cornerRadius(12)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
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
    let isConnected: Bool

    private var fillColor: Color {
        // Use gray for disconnected drives
        if !isConnected {
            return .gray
        }

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
    }
}

#Preview {
    DriveListView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
        .frame(width: 400, height: 500)
}
