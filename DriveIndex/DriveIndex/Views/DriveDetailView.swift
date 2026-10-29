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
    @State private var isPointerInWindow = false

    var body: some View {
        Form {
            Section {
                infoRows
                    .textSelection(.enabled)
            } header: {
                hero
            }

            // Storage and files work for offline drives via the database
            if drive.fileCount > 0 {
                Section("Storage") {
                    StorageVisualizationView(drive: drive)
                        .id(drive.id)
                }

                Section("Files") {
                    FileBrowserView(drive: drive)
                        .id(drive.id)  // Force new view instance for each drive
                }
            }

            if drive.isConnected {
                Section {
                    HStack {
                        Spacer()
                        Button(drive.lastScanDate == nil ? "Scan" : "Rescan", action: rescanDrive)
                            .disabled(indexManager.isIndexing)
                        Button("Show in Finder", action: revealInFinder)
                        Button("Eject", action: ejectDrive)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Covers the toolbar too, so the pointer can reach the toolbar Eject button without it vanishing
        .background {
            Color.clear
                .ignoresSafeArea()
                .onHover { isPointerInWindow = $0 }
        }
        .navigationTitle(drive.name)
        .navigationSubtitle(drive.formattedTotal)
        .toolbar {
            if drive.isConnected && isPointerInWindow {
                ToolbarItem(placement: .primaryAction) {
                    Button("Eject", systemImage: "eject", action: ejectDrive)
                        .help("Eject drive")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", systemImage: "trash") {
                    showDeleteConfirmation = true
                }
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

    // MARK: - Header

    private var hero: some View {
        VStack {
            Image(systemName: "externaldrive.fill")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)

            Text(drive.name)
                .font(.title)
                .foregroundStyle(.primary)

            Label {
                Text("\(drive.formattedTotal) · \(drive.isConnected ? "Connected" : "Disconnected")")
            } icon: {
                Image(systemName: "circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(drive.connectionStatusColor)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom)
    }

    @ViewBuilder
    private var infoRows: some View {
        LabeledContent("Files Indexed", value: drive.fileCount > 0 ? "\(drive.fileCount.formatted()) files" : "Not indexed")
        LabeledContent("Last Scanned", value: drive.formattedLastScan)
        LabeledContent("UUID", value: drive.id)
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
    .frame(width: 480, height: 1100)  // detail column at the main window's minimum width
}
