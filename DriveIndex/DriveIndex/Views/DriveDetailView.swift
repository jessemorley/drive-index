//
//  DriveDetailView.swift
//  DriveIndex
//
//  Detail view for a single drive, showing storage visualization and actions
//

import SwiftUI

struct DriveDetailView: View {
    let drive: DriveInfo
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xLarge) {
                // Drive header section
                driveHeaderSection

                // Capacity section
                capacitySection

                // Storage visualization
                if drive.fileCount > 0 && drive.isConnected {
                    storageVisualizationSection
                }

                // Drive information section
                driveInfoSection

                // Action buttons section
                if drive.isConnected {
                    actionButtonsSection
                }
            }
            .padding(DesignSystem.Spacing.sectionPadding)
        }
        .navigationTitle(drive.name)
        .navigationSubtitle(drive.formattedTotal)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Label("Delete", systemImage: "trash")
                        .font(DesignSystem.Typography.caption)
                }
                .buttonStyle(.bordered)
                .help("Remove drive from database")
            }
        }
        .confirmationDialog(
            "Are you sure you want to remove \"\(drive.name)\" from the database?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await driveMonitor.deleteDrive(drive.id)
                    } catch {
                        print("Error deleting drive: \(error)")
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All indexed files for this drive will be permanently deleted.")
        }
    }

    // MARK: - Header Section

    private var driveHeaderSection: some View {
        HStack(spacing: DesignSystem.Spacing.large) {
            DesignSystem.icon("externaldrive.fill", size: 64)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Circle()
                        .fill(drive.isConnected ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)

                    Text(drive.name)
                        .font(DesignSystem.Typography.title)
                }

                Text(drive.isConnected ? "Connected" : "Disconnected")
                    .secondaryText()
                    .font(DesignSystem.Typography.callout)
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(drive.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card)
                .strokeBorder(drive.borderColor ?? Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Capacity Section

    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Capacity")
                .sectionHeader()

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                if drive.totalCapacity > 0 {
                    CapacityBar(
                        used: drive.usedCapacity,
                        total: drive.totalCapacity,
                        percentage: drive.usedPercentage,
                        isConnected: drive.isConnected,
                        height: 8
                    )

                    HStack {
                        Text("\(drive.formattedUsed) used")
                            .secondaryText()

                        Spacer()

                        Text("\(drive.formattedAvailable) available")
                            .secondaryText()
                    }
                    .font(DesignSystem.Typography.callout)
                }
            }
            .padding(DesignSystem.Spacing.cardPadding)
            .card()
        }
    }

    // MARK: - Storage Visualization Section

    private var storageVisualizationSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Storage Breakdown")
                .sectionHeader()

            StorageVisualizationView(drive: drive)
        }
    }

    // MARK: - Drive Info Section

    private var driveInfoSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Information")
                .sectionHeader()

            VStack(spacing: 0) {
                infoRow(label: "Files Indexed", value: drive.fileCount > 0 ? "\(drive.fileCount.formatted()) files" : "Not indexed")

                DesignSystem.divider()

                infoRow(label: "Last Scanned", value: drive.formattedLastScan)

                DesignSystem.divider()

                infoRow(label: "Path", value: drive.path)

                DesignSystem.divider()

                infoRow(label: "UUID", value: drive.id)
            }
            .padding(DesignSystem.Spacing.cardPadding)
            .card()
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
            Text(label)
                .font(DesignSystem.Typography.callout)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(DesignSystem.Typography.callout)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, DesignSystem.Spacing.medium)
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Actions")
                .sectionHeader()

            HStack(spacing: DesignSystem.Spacing.medium) {
                Button(action: {
                    rescanDrive()
                }) {
                    Label("Rescan Drive", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(indexManager.isIndexing)

                Button(action: {
                    revealInFinder()
                }) {
                    Label("Reveal in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    ejectDrive()
                }) {
                    Label("Eject Drive", systemImage: "eject")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(DesignSystem.Spacing.cardPadding)
            .card()
        }
    }

    // MARK: - Actions

    private func rescanDrive() {
        // Un-exclude drive if it was excluded
        Task {
            await driveMonitor.unexcludeDrive(drive.id)
        }

        // Trigger drive rescan
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

// MARK: - Preview

#Preview {
    NavigationStack {
        DriveDetailView(drive: DriveInfo(
            id: "test-uuid",
            name: "My External Drive",
            path: "/Volumes/MyDrive",
            totalCapacity: 500_000_000_000,
            availableCapacity: 200_000_000_000,
            isConnected: true,
            lastSeen: Date(),
            lastScanDate: Date(),
            fileCount: 15432,
            isExcluded: false
        ))
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
    }
}
