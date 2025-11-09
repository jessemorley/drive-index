//
//  StatsView.swift
//  DriveIndex
//
//  Stats tab
//

import SwiftUI

struct StatsView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor

    private let databasePath = "~/Library/Application Support/DriveIndex/"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxLarge) {
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
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(databasePath, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")

                        Button(action: {
                            let path = NSString(string: databasePath).expandingTildeInPath
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .help("Open in Finder")
                    }
                    .padding(Spacing.small)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
                }

                // Database Statistics
                SettingsSection(
                    title: "Database Statistics",
                    description: "Current indexing status",
                    symbol: "chart.bar"
                ) {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        StatRow(
                            label: "Total Files Indexed",
                            value: "\(totalFilesIndexed.formatted())"
                        )
                        Divider()
                        StatRow(
                            label: "Connected Drives",
                            value: "\(connectedDrivesCount)"
                        )
                        Divider()
                        StatRow(
                            label: "Total Drives",
                            value: "\(driveMonitor.drives.count)"
                        )
                    }
                    .padding(Spacing.medium)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding(Spacing.Container.horizontalPadding)
            .padding(.vertical, Spacing.large)
        }
    }

    private var totalFilesIndexed: Int {
        driveMonitor.drives.reduce(0) { $0 + $1.fileCount }
    }

    private var connectedDrivesCount: Int {
        driveMonitor.drives.filter { $0.isConnected }.count
    }
}

#Preview {
    StatsView()
        .environmentObject(DriveMonitor())
        .frame(width: 600, height: 400)
}
