//
//  StatsView.swift
//  DriveIndex
//
//  Stats tab
//

import SwiftUI

struct StatsView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @State private var driveToDelete: DriveInfo?
    @State private var showDeleteConfirmation = false
    @State private var showDeleteDatabaseConfirmation = false

    private let databasePath = "~/Library/Application Support/DriveIndex/"

    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxLarge) {
                // Indexed Drives
                SettingsSection(
                    title: "Indexed Drives",
                    description: "Drives stored in the database",
                    symbol: "externaldrive"
                ) {
                    if driveMonitor.drives.isEmpty {
                        Text("No drives indexed yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(Spacing.medium)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(8)
                    } else {
                        VStack(spacing: Spacing.small) {
                            ForEach(driveMonitor.drives) { drive in
                                DriveStatsRow(
                                    drive: drive,
                                    onDelete: {
                                        driveToDelete = drive
                                        showDeleteConfirmation = true
                                    },
                                    onRefresh: {
                                        // Trigger drive rescan
                                        if let driveURL = driveMonitor.getDriveURL(for: drive) {
                                            NotificationCenter.default.post(
                                                name: .shouldIndexDrive,
                                                object: nil,
                                                userInfo: [
                                                    "driveURL": driveURL,
                                                    "driveUUID": drive.id
                                                ]
                                            )
                                        }
                                    }
                                )
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }
                }

                // Database Location
                SettingsSection(
                    title: "Database Location",
                    description: "Where indexed data is stored",
                    symbol: "folder.fill.badge.gearshape"
                ) {
                    HStack {
                        Text(databasePath)
                            .font(AppTypography.technicalData)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.secondary)

                        Spacer()

                        HStack(spacing: Spacing.small) {
                            Button(action: {
                                let path = NSString(string: databasePath).expandingTildeInPath
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            }) {
                                Label("Finder", systemImage: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .help("Open in Finder")

                            Button(action: {
                                showDeleteDatabaseConfirmation = true
                            }) {
                                Label("Delete", systemImage: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .help("Delete entire database")
                        }
                    }
                    .padding(Spacing.small)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            .padding(Spacing.Container.horizontalPadding)
            .padding(.vertical, Spacing.large)
        }
        }
        .confirmationDialog(
            "Are you sure you want to remove \"\(driveToDelete?.name ?? "this drive")\" from the database?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let drive = driveToDelete {
                    Task {
                        do {
                            try await driveMonitor.deleteDrive(drive.id)
                        } catch {
                            print("Error deleting drive: \(error)")
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All indexed files for this drive will be permanently deleted.")
        }
        .alert(isPresented: $showDeleteDatabaseConfirmation) {
            Alert(
                title: Text("Delete Entire Database"),
                message: Text("Are you sure you want to delete the entire database? This will remove all indexed drives and files. This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deleteDatabase()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func deleteDatabase() {
        let path = NSString(string: databasePath).expandingTildeInPath
        let dbFile = (path as NSString).appendingPathComponent("index.db")
        let dbWalFile = "\(dbFile)-wal"
        let dbShmFile = "\(dbFile)-shm"

        let fileManager = FileManager.default

        // Delete database files
        try? fileManager.removeItem(atPath: dbFile)
        try? fileManager.removeItem(atPath: dbWalFile)
        try? fileManager.removeItem(atPath: dbShmFile)

        // Refresh drives list
        Task {
            await driveMonitor.loadDrives()
        }
    }
}

struct DriveStatsRow: View {
    let drive: DriveInfo
    let onDelete: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            // Top row: Drive name + action buttons
            HStack(spacing: Spacing.medium) {
                // Status dot + Drive name
                HStack(spacing: 6) {
                    Circle()
                        .fill(drive.isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(drive.name)
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Spacer()

                // Action buttons
                HStack(spacing: Spacing.small) {
                    // Refresh button (only when connected)
                    if drive.isConnected {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .help("Rescan drive")
                    }

                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("Remove drive from database")
                }
            }

            // Capacity bar (full width)
            if drive.totalCapacity > 0 {
                CapacityBar(
                    used: drive.usedCapacity,
                    total: drive.totalCapacity,
                    percentage: drive.usedPercentage,
                    isConnected: drive.isConnected,
                    height: 6
                )
            }

            // Info row: Capacity + file count + last scanned
            HStack(spacing: Spacing.medium) {
                if drive.totalCapacity > 0 {
                    Text("\(drive.formattedUsed) / \(drive.formattedTotal)")
                        .font(AppTypography.technicalData)
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
        }
        .padding(Spacing.medium)
    }
}

#Preview {
    StatsView()
        .environmentObject(DriveMonitor())
        .frame(width: 600, height: 400)
}
