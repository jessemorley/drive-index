//
//  SettingsSection.swift
//  DriveIndex
//
//  Reusable settings section component
//

import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let description: String
    let symbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack(spacing: Spacing.small) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            content()
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(AppTypography.technicalData)
                .fontWeight(.semibold)
        }
    }
}

struct AboutItem: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)

            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    VStack(spacing: 20) {
        SettingsSection(
            title: "Test Section",
            description: "This is a test description",
            symbol: "gearshape"
        ) {
            Text("Content goes here")
        }

        StatRow(label: "Test Stat", value: "100")

        AboutItem(title: "Feature", description: "Description of the feature")
    }
    .padding()
}
