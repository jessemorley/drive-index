//
//  NavigationSidebar.swift
//  DriveIndex
//
//  Sidebar navigation for main app window content sections
//

import SwiftUI

struct NavigationSidebar: View {
    @Binding var selection: NavigationItem?

    var body: some View {
        VStack(spacing: 0) {
            // DriveIndex header
            HStack(spacing: 8) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 20))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text("DriveIndex")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            // Navigation list
            List(selection: $selection) {
                // Search (no section)
                NavigationSidebarRow(item: .search)
                    .tag(NavigationItem.search)

                // Index section
                Section {
                    NavigationSidebarRow(item: .drives)
                        .tag(NavigationItem.drives)
                    NavigationSidebarRow(item: .files)
                        .tag(NavigationItem.files)
                    NavigationSidebarRow(item: .duplicates)
                        .tag(NavigationItem.duplicates)
                } header: {
                    Text("Index")
                        .font(.system(size: 11))
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }

                // Spacer to push Settings to bottom
                Spacer()
                    .listRowBackground(Color.clear)

                // Settings at bottom (no section)
                NavigationSidebarRow(item: .settings)
                    .tag(NavigationItem.settings)
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("DriveIndex")
    }
}

// MARK: - Sidebar Row

struct NavigationSidebarRow: View {
    let item: NavigationItem

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
    NavigationSidebar(selection: .constant(.drives))
        .frame(width: 220)
}
