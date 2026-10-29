//
//  NavigationSidebar.swift
//  DriveIndex
//
//  Sidebar navigation for main app window content sections
//

import SwiftUI

struct NavigationSidebar: View {
    @Binding var selection: NavigationItem?
    @ObservedObject var driveMonitor: DriveMonitor

    var body: some View {
        List(selection: $selection) {
            // Search (no section)
            NavigationSidebarRow(item: .search)
                .tag(NavigationItem.search)

            // Index section
            Section {
                NavigationSidebarRow(item: .drives)
                    .tag(NavigationItem.drives)
                NavigationSidebarRow(item: .duplicates)
                    .tag(NavigationItem.duplicates)
            } header: {
                Text("Index")
            }

            // Drives section (dynamic)
            Section {
                ForEach(driveMonitor.drives.filter { $0.isIndexed }) { drive in
                    NavigationSidebarRow(item: .drive(drive))
                        .tag(NavigationItem.drive(drive))
                }
            } header: {
                Text("Drives")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("DriveIndex")
    }
}

// MARK: - Sidebar Row

struct NavigationSidebarRow: View {
    let item: NavigationItem

    var body: some View {
        // Disconnected drives are greyed out; everything else keeps the sidebar default
        if isDisconnectedDrive {
            label.foregroundStyle(.secondary)
        } else {
            label
        }
    }

    private var label: some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.icon)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var isDisconnectedDrive: Bool {
        if case .drive(let driveInfo) = item { return !driveInfo.isConnected }
        return false
    }
}

// MARK: - Preview

#Preview {
    NavigationSidebar(selection: .constant(.drives), driveMonitor: DriveMonitor())
        .frame(width: 220)
}
