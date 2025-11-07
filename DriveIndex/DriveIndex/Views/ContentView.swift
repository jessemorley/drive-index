//
//  ContentView.swift
//  DriveIndexer
//
//  Main popover content view
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var driveMonitor: DriveMonitor
    @EnvironmentObject var indexManager: IndexManager
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Drive Indexer")
                    .font(.headline)

                Spacer()

                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)

                Button(action: { NSApp.terminate(nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Indexing progress indicator
            if indexManager.isIndexing {
                IndexingProgressView()
                    .padding()
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(indexManager)
        }
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
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No External Drives")
                .font(.title3)
                .fontWeight(.medium)

            Text("Connect an external drive to begin indexing")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct IndexingProgressView: View {
    @EnvironmentObject var indexManager: IndexManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Indexing \(indexManager.indexingDriveName)...")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Button("Cancel") {
                    indexManager.cancelIndexing()
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }

            if let progress = indexManager.currentProgress {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)

                    Text("\(progress.filesProcessed) files")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !progress.currentFile.isEmpty {
                        Text("• \(progress.currentFile)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } else {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    ContentView()
        .environmentObject(DriveMonitor())
        .environmentObject(IndexManager())
}
