//
//  SettingsNavigationSidebar.swift
//  DriveIndex
//
//  Sidebar navigation for Settings window
//

import SwiftUI

struct SettingsNavigationSidebar: View {
    @Binding var selection: SettingsNavigationItem?

    var body: some View {
        VStack(spacing: 0) {
            // Navigation list
            List(selection: $selection) {
                ForEach(SettingsNavigationItem.allCases) { item in
                    SettingsNavigationSidebarRow(item: item)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Sidebar Row

struct SettingsNavigationSidebarRow: View {
    let item: SettingsNavigationItem

    var body: some View {
        Label {
            Text(item.title)
                .font(DesignSystem.Typography.body)
        } icon: {
            Image(systemName: item.icon)
                .font(.system(size: DesignSystem.Sidebar.iconSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsNavigationSidebar(selection: .constant(.appearance))
        .frame(width: 220)
}
