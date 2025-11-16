//
//  NavigationSidebar.swift
//  DriveIndex
//
//  macOS System Settings-style sidebar with collapsible sections
//

import SwiftUI

struct NavigationSidebar: View {
    @Binding var selection: NavigationItem?
    @State private var expandedSections: Set<NavigationSection> = [.index] // Index expanded by default

    var body: some View {
        List(selection: $selection) {
            ForEach(NavigationSection.allCases) { section in
                Section(isExpanded: Binding(
                    get: { expandedSections.contains(section) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedSections.insert(section)
                        } else {
                            expandedSections.remove(section)
                        }
                    }
                )) {
                    ForEach(section.items) { item in
                        NavigationSidebarRow(item: item, isSelected: selection == item)
                            .tag(item)
                    }
                } header: {
                    Text(section.rawValue)
                        .font(DesignSystem.Typography.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .textCase(.uppercase)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("DriveIndex")
    }
}

// MARK: - Sidebar Row

struct NavigationSidebarRow: View {
    let item: NavigationItem
    let isSelected: Bool

    var body: some View {
        Label {
            Text(item.title)
                .font(DesignSystem.Typography.body)
        } icon: {
            DesignSystem.icon(item.icon, size: DesignSystem.Sidebar.iconSize)
                .foregroundStyle(isSelected ? .white : DesignSystem.Colors.primaryText)
        }
        .padding(.vertical, DesignSystem.Spacing.xSmall)
    }
}

// MARK: - Preview

#Preview {
    NavigationSidebar(selection: .constant(.drives))
        .frame(width: 220)
}
