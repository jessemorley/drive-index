//
//  AboutWindow.swift
//  DriveIndex
//
//  About window for menu bar access
//

import SwiftUI

struct AboutWindow: View {
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xxLarge) {
            // App icon and info
            VStack(spacing: DesignSystem.Spacing.medium) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: DesignSystem.Spacing.xSmall) {
                    Text("DriveIndex")
                        .font(DesignSystem.Typography.title)

                    Text("Version 1.0.1")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                    Text("© 2025 Jesse Morley")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .padding(.top, DesignSystem.Spacing.xSmall)
                }
            }

            Divider()

            // Technical info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                Text("Technical Details")
                    .font(DesignSystem.Typography.headline)
                    .fontWeight(.semibold)

                VStack(spacing: DesignSystem.Spacing.xSmall) {
                    AboutInfoRow(label: "Database", value: "SQLite with FTS5")
                    Divider()
                    AboutInfoRow(label: "Platform", value: "macOS 13+")
                    Divider()
                    AboutInfoRow(label: "Architecture", value: "Swift + SwiftUI")
                }
                .padding(DesignSystem.Spacing.medium)
                .background(DesignSystem.Colors.cardBackgroundDefault)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.Spacing.xxLarge)
        .frame(width: 400)
    }
}

struct AboutInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)

            Spacer()

            Text(value)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    AboutWindow()
}
