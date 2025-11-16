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
                            NavigationSidebarRow(item: item)
                                .tag(item)
                        }
                    } header: {
                        Text(section.rawValue)
                            .font(.system(size: 11))
                            .fontWeight(.semibold)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }
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
                .fontWeight(.medium)
        } icon: {
            Image(systemName: item.icon)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationSidebar(selection: .constant(.drives))
        .frame(width: 220)
}
