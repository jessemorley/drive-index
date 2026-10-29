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
        Form {
            Section("Database Location") {
                LabeledContent {
                    Button("Open") {
                        let path = NSString(string: databasePath).expandingTildeInPath
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .help("Open in Finder")
                } label: {
                    Text(databasePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Section {
                LabeledContent {
                    Button("Delete…", role: .destructive) {
                        showDeleteDatabaseConfirmation = true
                    }
                    .help("Delete entire database")
                } label: {
                    Text("Delete All Indexed Data")
                    Text("This will permanently delete all indexed drives and files from the database. This action cannot be undone.")
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("Deleting the database will remove all indexed information. Your actual files on the drives will not be affected. You'll need to re-index your drives after deletion.")
            }
        }
        .formStyle(.grouped)
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
