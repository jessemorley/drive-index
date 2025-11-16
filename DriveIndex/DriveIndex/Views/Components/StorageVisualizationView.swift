//
//  StorageVisualizationView.swift
//  DriveIndex
//
//  macOS-style storage visualization with color-coded category breakdown
//

import SwiftUI

struct StorageVisualizationView: View {
    let drive: DriveInfo

    @State private var breakdown: StorageBreakdown?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing storage...")
                        .font(AppTypography.capacityInfo)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, Spacing.medium)
            } else if let breakdown = breakdown {
                StorageBreakdownView(breakdown: breakdown)
            } else {
                Text("Unable to analyze storage")
                    .font(AppTypography.capacityInfo)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.medium)
            }
        }
        .task {
            await loadBreakdown()
        }
    }

    private func loadBreakdown() async {
        // Check cache first
        let cachedBreakdown = await StorageCache.shared.get(
            driveUUID: drive.id,
            currentScanDate: drive.lastScanDate
        )

        if let cachedBreakdown = cachedBreakdown {
            // Use cached data - instant display, no loading state
            breakdown = cachedBreakdown
            isLoading = false
            return
        }

        // Cache miss - perform analysis
        isLoading = true
        error = nil

        do {
            let newBreakdown = try await StorageBreakdown.analyze(
                driveUUID: drive.id,
                totalCapacity: drive.totalCapacity,
                usedCapacity: drive.usedCapacity,
                databaseManager: DatabaseManager.shared
            )

            breakdown = newBreakdown

            // Cache the result for future use
            await StorageCache.shared.set(
                driveUUID: drive.id,
                breakdown: newBreakdown,
                scanDate: drive.lastScanDate
            )
        } catch {
            self.error = error
            print("❌ Storage analysis error: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Storage Breakdown View

private struct StorageBreakdownView: View {
    let breakdown: StorageBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            // Header with capacity info
            HStack {
                Text(breakdown.formattedUsed)
                    .font(AppTypography.capacityInfo)
                Text("of")
                    .font(AppTypography.capacityInfo)
                    .foregroundColor(.secondary)
                Text(breakdown.formattedTotal)
                    .font(AppTypography.capacityInfo)

                Spacer()

                Text(breakdown.formattedAvailable)
                    .font(AppTypography.capacityInfo)
                Text("available")
                    .font(AppTypography.capacityInfo)
                    .foregroundColor(.secondary)
            }

            // Horizontal segmented bar
            StorageBar(breakdown: breakdown)

            // Category legend (horizontal)
            CategoryLegend(categories: breakdown.categories)
        }
        .padding(Spacing.medium)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Storage Bar

private struct StorageBar: View {
    let breakdown: StorageBreakdown
    let height: CGFloat = 20

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                // Category segments
                ForEach(breakdown.categories) { category in
                    Rectangle()
                        .fill(category.category.color)
                        .frame(width: geometry.size.width * category.percentage)
                }

                // Available space
                if breakdown.availablePercentage > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: geometry.size.width * breakdown.availablePercentage)
                }
            }
        }
        .frame(height: height)
        .cornerRadius(6)
    }
}

// MARK: - Category Legend

private struct CategoryLegend: View {
    let categories: [StorageBreakdown.CategoryData]

    var body: some View {
        HStack(spacing: Spacing.medium) {
            ForEach(categories) { category in
                HStack(spacing: 4) {
                    Circle()
                        .fill(category.category.color)
                        .frame(width: 6, height: 6)

                    Text(category.category.displayName)
                        .font(AppTypography.capacityInfo)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Formatting Helpers

extension StorageBreakdown {
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file)
    }

    var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
    }
}
