//
//  FileTreeRow.swift
//  DriveIndex
//
//  Row component for hierarchical file browser
//

import SwiftUI

struct FileTreeRow: View {
    let item: FileBrowserItem
    let depth: Int
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            // Indentation for nesting depth
            if depth > 0 {
                Color.clear
                    .frame(width: CGFloat(depth) * 20)
            }

            // Disclosure triangle for directories
            if item.isDirectory {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            } else {
                // Spacer for non-directories to align with folders
                Color.clear
                    .frame(width: 12)
            }

            // File icon
            Image(systemName: item.fileIcon)
                .font(.system(size: 16))
                .foregroundColor(item.isDirectory ? .blue : .secondary)
                .frame(width: 20)

            // File/folder name
            Text(item.name)
                .font(DesignSystem.Typography.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // File size
            Text(item.formattedSize)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 80, alignment: .trailing)

            // Modified date
            Text(item.formattedDate)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? DesignSystem.Colors.cardBackgroundHover : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
