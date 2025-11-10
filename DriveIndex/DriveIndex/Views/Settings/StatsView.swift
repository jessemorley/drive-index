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
                        .padding(Spacing.small)
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
                            Text("Delete")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.red)
                                .cornerRadius(6)
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
        HStack(alignment: .center, spacing: 12) {
            // Connection status dot + Drive name
            HStack(spacing: 6) {
                Circle()
                    .fill(drive.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(drive.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)

            // Drive capacity
            Text(drive.formattedTotal)
                .font(AppTypography.technicalData)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            // File count
            HStack(spacing: 3) {
                Image(systemName: "doc.text")
                    .font(.caption2)
                Text("\(drive.fileCount.formatted()) files")
                    .font(AppTypography.technicalData)
            }
            .foregroundColor(.secondary)
            .frame(width: 90, alignment: .leading)

            // Last indexed
            Text(drive.formattedLastScan)
                .font(AppTypography.technicalData)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Text("Remove")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help("Remove drive from database")
            .fixedSize()
        }
        .padding(.vertical, Spacing.small)
    }
}

#Preview {
    StatsView()
        .environmentObject(DriveMonitor())
        .frame(width: 600, height: 400)
}
