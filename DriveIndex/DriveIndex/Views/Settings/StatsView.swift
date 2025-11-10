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
                        VStack(spacing: 0) {
                            ForEach(Array(driveMonitor.drives.enumerated()), id: \.element.id) { index, drive in
                                DriveStatsRow(drive: drive) {
                                    driveToDelete = drive
                                    showDeleteConfirmation = true
                                }

                                if index < driveMonitor.drives.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(Spacing.medium)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
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

                        Button(action: {
                            let path = NSString(string: databasePath).expandingTildeInPath
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .help("Open in Finder")

                        Button(action: {
                            showDeleteDatabaseConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete entire database")
                    }
                    .padding(Spacing.small)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }
            }
            .padding(Spacing.Container.horizontalPadding)
            .padding(.vertical, Spacing.large)
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Drive from Database"),
                message: Text("Are you sure you want to remove \"\(driveToDelete?.name ?? "this drive")\" from the database? All indexed files for this drive will be permanently deleted."),
                primaryButton: .destructive(Text("Delete")) {
                    if let drive = driveToDelete {
                        Task {
                            do {
                                try await driveMonitor.deleteDrive(drive.id)
                            } catch {
                                print("Error deleting drive: \(error)")
                            }
                        }
                    }
                },
                secondaryButton: .cancel()
            )
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

    var body: some View {
        HStack(spacing: Spacing.medium) {
            // Drive info
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                HStack(spacing: Spacing.small) {
                    Text(drive.name)
                        .font(.callout)
                        .fontWeight(.medium)

                    // Connection status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(drive.isConnected ? Color.green : Color.secondary)
                            .frame(width: 6, height: 6)
                        Text(drive.isConnected ? "Online" : "Offline")
                            .font(.caption2)
                            .foregroundColor(drive.isConnected ? .green : .secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(drive.isConnected ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                }

                Text("\(drive.fileCount.formatted()) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Remove drive from database")
        }
        .padding(.vertical, Spacing.xSmall)
    }
}

#Preview {
    StatsView()
        .environmentObject(DriveMonitor())
        .frame(width: 600, height: 400)
}
