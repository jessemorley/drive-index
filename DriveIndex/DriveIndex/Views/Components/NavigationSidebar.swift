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
                    NavigationSidebarRow(item: .drive(drive), onEject: drive.isConnected ? { eject(drive) } : nil)
                        .tag(NavigationItem.drive(drive))
                }
            } header: {
                Text("Drives")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("DriveIndex")
    }

    private func eject(_ drive: DriveInfo) {
        if let driveURL = driveMonitor.getDriveURL(for: drive) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: driveURL)
        }
    }
}

// MARK: - Sidebar Row

struct NavigationSidebarRow: View {
    let item: NavigationItem
    /// Shows a Finder-style eject button at the trailing edge (connected drives only)
    var onEject: (() -> Void)? = nil

    var body: some View {
        HStack {
            // Disconnected drives are greyed out; everything else keeps the sidebar default
            if isDisconnectedDrive {
                label.foregroundStyle(.secondary)
            } else {
                label
            }

            if let onEject {
                Spacer()
                EjectButton(title: item.title, action: onEject)
            }
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

/// Finder-style sidebar eject: small, secondary, brightens on hover.
private struct EjectButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button("Eject \(title)", systemImage: "eject.fill", action: action)
            .labelStyle(.iconOnly)
            .imageScale(.small)  // Finder's sidebar eject is smaller than the row icon
            .buttonStyle(.borderless)
            .foregroundStyle(isHovered ? .primary : .secondary)
            .onHover { isHovered = $0 }
            .help("Eject \"\(title)\"")
    }
}

// MARK: - Preview

#Preview {
    NavigationSidebar(selection: .constant(.drives), driveMonitor: DriveMonitor())
        .frame(width: 220)
}
