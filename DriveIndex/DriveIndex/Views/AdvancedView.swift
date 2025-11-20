//
//  AdvancedView.swift
//  DriveIndex
//
//  Advanced settings view
//

import SwiftUI

struct AdvancedView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @State private var showDeleteDatabaseConfirmation = false

    private let databasePath = "~/Library/Application Support/DriveIndex/"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxLarge) {
                // Database Location
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("Database Location")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        HStack {
                            Text(databasePath)
                                .font(DesignSystem.Typography.technicalData)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)

                            Spacer()

                            HStack(spacing: DesignSystem.Spacing.small) {
                                Button(action: {
                                    let path = NSString(string: databasePath).expandingTildeInPath
                                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                }) {
                                    Label("Open", systemImage: "folder")
                                        .font(DesignSystem.Typography.caption)
                                }
                                .buttonStyle(.bordered)
                                .help("Open in Finder")

                                Button(action: {
                                    showDeleteDatabaseConfirmation = true
                                }) {
                                    Label("Delete", systemImage: "trash")
                                        .font(DesignSystem.Typography.caption)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .help("Delete entire database")
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Danger Zone
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("Danger Zone")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Button(action: {
                            showDeleteDatabaseConfirmation = true
                        }) {
                            Label("Delete All Indexed Data", systemImage: "trash.fill")
                                .frame(maxWidth: .infinity)
                                .font(DesignSystem.Typography.callout)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.large)

                        Text("This will permanently delete all indexed drives and files from the database. This action cannot be undone.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                    .padding(DesignSystem.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Warning callout
                HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                    VStack(spacing: 0) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(DesignSystem.Typography.title2)
                    }
                    .frame(width: 24)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                        Text("Caution")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)

                        Text("Deleting the database will remove all indexed information. Your actual files on the drives will not be affected. You'll need to re-index your drives after deletion.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }
                .padding(DesignSystem.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignSystem.Spacing.sectionPadding)
            .padding(.vertical, DesignSystem.Spacing.large)
        }
        .navigationTitle("Advanced")
        .alert("Delete Entire Database", isPresented: $showDeleteDatabaseConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteDatabase()
            }
        } message: {
            Text("Are you sure you want to delete the entire database? This will remove all indexed drives and files. This action cannot be undone.")
        }
    }

    private func deleteDatabase() {
        Task {
            do {
                let path = NSString(string: databasePath).expandingTildeInPath
                let fileManager = FileManager.default

                if fileManager.fileExists(atPath: path) {
                    try fileManager.removeItem(atPath: path)
                    print("Database deleted successfully")

                    // Reload drives to reflect empty state
                    await driveMonitor.loadDrives()
                }
            } catch {
                print("Error deleting database: \(error)")
            }
        }
    }
}

#Preview {
    AdvancedView()
        .environmentObject(DriveMonitor())
}
