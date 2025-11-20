//
//  DuplicateSettingsView.swift
//  DriveIndex
//
//  Duplicate detection settings view
//

import SwiftUI

struct DuplicateSettingsView: View {
    @AppStorage("enableDuplicateDetection") private var enableDuplicateDetection: Bool = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxLarge) {
                // Duplicate Detection
                SettingsSection(
                    title: "Duplicate Detection",
                    description: "Control whether files are hashed to detect duplicates",
                    symbol: "doc.on.doc"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        Toggle(isOn: $enableDuplicateDetection) {
                            Text("Enable duplicate detection")
                                .font(DesignSystem.Typography.callout)
                        }
                        .toggleStyle(.switch)

                        Text("Calculate file hashes during indexing to detect duplicate files. Disabling this will speed up indexing but you won't be able to find duplicates.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Info callout
                HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                    VStack(spacing: 0) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                            .font(DesignSystem.Typography.title2)
                    }
                    .frame(width: 24)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                        Text("Changes take effect on next scan")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)

                        Text("Existing indexed files won't be affected. Only new scans will respect this setting.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignSystem.Spacing.sectionPadding)
            .padding(.vertical, DesignSystem.Spacing.large)
        }
        .navigationTitle("Duplicates")
    }
}

#Preview {
    DuplicateSettingsView()
}
