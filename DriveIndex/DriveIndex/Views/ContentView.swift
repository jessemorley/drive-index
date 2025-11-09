//
//  ContentView.swift
//  DriveIndex
//
//  Main popover content view
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @State private var settingsWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Spacing.large) {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text("Drive Indexer")
                        .font(.title2)
                        .fontWeight(.bold)

                    if !driveMonitor.drives.isEmpty {
                        Text("\(driveMonitor.drives.count) drive\(driveMonitor.drives.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: Spacing.medium) {
                    Button(action: { openSettingsWindow() }) {
                        Image(systemName: "gearshape")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings (⌘,)")

                    Button(action: { NSApp.terminate(nil) }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("q", modifiers: .command)
                    .help("Quit (⌘Q)")
                }
            }
            .padding(Spacing.Container.headerPadding)

            Divider()

            // Indexing progress indicator
            if indexManager.isIndexing {
                IndexingProgressView()
                    .padding(.horizontal, Spacing.Container.horizontalPadding)
                    .padding(.vertical, Spacing.Container.verticalPadding)
                Divider()
            }

            // Drive list
            if driveMonitor.drives.isEmpty {
                EmptyStateView()
            } else {
                DriveListView()
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            Task {
                await driveMonitor.loadDrives()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .driveIndexingComplete)) { _ in
            Task {
                await driveMonitor.loadDrives()
            }
        }
    }

    private func openSettingsWindow() {
        // If window already exists, bring it to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false

        let settingsView = SettingsView()
            .environmentObject(indexManager)
            .environmentObject(driveMonitor)

        window.contentView = NSHostingView(rootView: settingsView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Spacing.large) {
            VStack(spacing: Spacing.medium) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary)
                    .opacity(0.5)

                VStack(spacing: Spacing.small) {
                    Text("No Drives Connected")
                        .font(AppTypography.sectionHeader)

                    Text("Connect an external drive to begin indexing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.large)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Helpful tip
            HStack(spacing: Spacing.medium) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                    .font(.caption)

                Text("Tip: DriveIndex automatically scans drives when connected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.medium)
            .background(Color.orange.opacity(0.05))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.large)
    }
}

struct IndexingProgressView: View {
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
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
            } else {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(Spacing.medium)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
}
