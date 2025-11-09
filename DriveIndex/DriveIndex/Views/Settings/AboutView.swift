//
//  AboutView.swift
//  DriveIndex
//
//  About tab for settings
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: Spacing.xxLarge) {
                // App icon and info
                VStack(spacing: Spacing.medium) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 56))
                        .foregroundColor(.blue)

                    VStack(spacing: Spacing.xSmall) {
                        Text("DriveIndex")
                            .font(AppTypography.sectionHeader)

                        Text("Version 1.0.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Features
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text("Features")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    AboutItem(
                        title: "Fast Offline Search",
                        description: "SQLite FTS5 full-text search for instant results"
                    )

                    AboutItem(
                        title: "Automatic Indexing",
                        description: "Scans drives automatically when connected"
                    )

                    AboutItem(
                        title: "Raycast Integration",
                        description: "Search your drives directly from Raycast"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Technical info
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text("Technical Details")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: Spacing.small) {
                        TechnicalInfoRow(label: "Database", value: "SQLite with FTS5")
                        Divider()
                        TechnicalInfoRow(label: "Platform", value: "macOS 13+")
                        Divider()
                        TechnicalInfoRow(label: "Architecture", value: "Swift + SwiftUI")
                    }
                    .padding(Spacing.medium)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.large)
        }
    }
}

struct TechnicalInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    AboutView()
        .frame(width: 600, height: 400)
}
