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
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("Duplicate Detection")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        HStack {
                            Text("Enable duplicate detection")
                                .font(DesignSystem.Typography.callout)

                            Spacer()

                            Toggle(isOn: $enableDuplicateDetection) {
                                EmptyView()
                            }
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        Text("Duplicate detection will be disabled. File hashes will not be computed during indexing.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DesignSystem.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // About Duplicate Detection
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("About Duplicate Detection")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                        // Performance Impact
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                            Image(systemName: "speedometer")
                                .foregroundStyle(.blue)
                                .font(DesignSystem.Typography.title2)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                                Text("Performance Impact")
                                    .font(DesignSystem.Typography.callout)
                                    .fontWeight(.semibold)

                                Text("Computing file hashes requires reading file contents, which can slow down indexing for large drives.")
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Divider()

                        // Hash Algorithm
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                            Image(systemName: "chart.bar.fill")
                                .foregroundStyle(.blue)
                                .font(DesignSystem.Typography.title2)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                                Text("Hash Algorithm")
                                    .font(DesignSystem.Typography.callout)
                                    .fontWeight(.semibold)

                                Text("Uses XXHash64 for fast, non-cryptographic hashing optimized for duplicate detection.")
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Divider()

                        // Changes Take Effect
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.blue)
                                .font(DesignSystem.Typography.title2)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                                Text("Changes Take Effect")
                                    .font(DesignSystem.Typography.callout)
                                    .fontWeight(.semibold)

                                Text("Changes will apply to new indexing operations. Existing hashes in the database are not affected.")
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
