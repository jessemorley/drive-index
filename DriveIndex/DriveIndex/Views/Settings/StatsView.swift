//
//  StatsView.swift
//  DriveIndex
//
//  Stats tab
//

import SwiftUI

struct StatsView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @State private var driveToDelete: DriveInfo?
    @State private var showDeleteConfirmation = false
    @State private var showDeleteDatabaseConfirmation = false

    private let databasePath = "~/Library/Application Support/DriveIndex/"

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content
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
                                Image(systemName: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .help("Open in Finder")

                            Button(action: {
                                showDeleteDatabaseConfirmation = true
                            }) {
                                Image(systemName: "trash")
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

            // Indexing progress overlay at bottom
            if indexManager.isIndexing {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    // Header with status
                    HStack(spacing: Spacing.medium) {
                        HStack(spacing: Spacing.xSmall) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)

                            Text("INDEXING")
                                .font(AppTypography.statusText)
                                .foregroundColor(.orange)
                        }

                        Text(indexManager.indexingDriveName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        Spacer()

                        Button("Cancel") {
                            indexManager.cancelIndexing()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                        .font(.caption)
                    }

                    // Progress info
                    if let progress = indexManager.currentProgress {
                        HStack(spacing: Spacing.large) {
                            HStack(spacing: Spacing.small) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)

                                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                                    Text("Files Processed")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text("\(progress.filesProcessed)")
                                        .font(AppTypography.technicalData)
                                        .fontWeight(.semibold)
                                }
                            }

                            if !progress.currentFile.isEmpty {
                                Divider()
                                    .frame(height: 24)

                                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                                    Text("Current File")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)

                                    Text(progress.currentFile)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .frame(minHeight: 44)
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                }
                .padding(Spacing.medium)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, Spacing.Container.horizontalPadding)
                .padding(.bottom, Spacing.medium)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
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
        .environmentObject(IndexManager())
        .frame(width: 600, height: 400)
}
