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
                    .font(.system(size: 11))
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            // Drives section (dynamic)
            Section {
                ForEach(driveMonitor.drives.filter { $0.isIndexed }) { drive in
                    NavigationSidebarRow(item: .drive(drive))
                        .tag(NavigationItem.drive(drive))
                }
            } header: {
                Text("Drives")
                    .font(.system(size: 11))
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
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
        HStack(spacing: 8) {
            Label {
                Text(item.title)
            } icon: {
                Image(systemName: item.icon)
                    .symbolRenderingMode(.hierarchical)
            }

            // Show connection status badge for drive items
            if case .drive(let driveInfo) = item {
                Spacer()
                Circle()
                    .fill(driveInfo.isConnected ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationSidebar(selection: .constant(.drives), driveMonitor: DriveMonitor())
        .frame(width: 220)
}
