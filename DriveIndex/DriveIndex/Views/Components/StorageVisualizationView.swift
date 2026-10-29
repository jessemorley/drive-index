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

    init(drive: DriveInfo) {
        self.drive = drive

        // Populate state synchronously BEFORE first render
        let cached = StorageCache.shared.get(
            driveUUID: drive.id,
            currentScanDate: drive.lastScanDate
        )
        _breakdown = State(initialValue: cached)
        _isLoading = State(initialValue: cached == nil)
    }

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analysing storage...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if let breakdown = breakdown {
                StorageBreakdownView(driveName: drive.name, breakdown: breakdown)
            } else {
                Text("Unable to analyze storage")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .task {
            await loadBreakdown()
        }
    }

    private func loadBreakdown() async {
        // If we already have breakdown from cache init, don't reload
        if breakdown != nil {
            return
        }

        // No cache hit during init - perform analysis
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
            StorageCache.shared.set(
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

/// Laid out like System Settings > General > Storage.
private struct StorageBreakdownView: View {
    let driveName: String
    let breakdown: StorageBreakdown

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(driveName)
                Spacer()
                Text("\(breakdown.formattedUsed) of \(breakdown.formattedTotal) used")
                    .foregroundStyle(.secondary)
            }

            StorageBar(breakdown: breakdown)

            CategoryLegend(categories: breakdown.categories)
        }
    }
}

// MARK: - Storage Bar

private struct StorageBar: View {
    let breakdown: StorageBreakdown
    // ponytail: drawn chart, no system control for it; height and radius match System Settings > Storage
    private let height: CGFloat = 22

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(breakdown.categories) { category in
                    Rectangle()
                        .fill(category.category.color)
                        .frame(width: geometry.size.width * category.percentage)
                }

                if breakdown.availablePercentage > 0 {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            // Hidden when the free segment is too narrow for its label
                            ViewThatFits {
                                Text(breakdown.formattedAvailable)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Color.clear
                            }
                        }
                        .frame(width: geometry.size.width * breakdown.availablePercentage)
                }
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 5))
        .accessibilityElement()
        .accessibilityLabel("\(breakdown.formattedUsed) of \(breakdown.formattedTotal) used, \(breakdown.formattedAvailable) available")
    }
}

// MARK: - Category Legend

private struct CategoryLegend: View {
    let categories: [StorageBreakdown.CategoryData]

    var body: some View {
        HStack {
            ForEach(categories) { category in
                Label {
                    Text(category.category.displayName)
                } icon: {
                    Image(systemName: "circle.fill")
                        .imageScale(.small)
                        .foregroundStyle(category.category.color)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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

#Preview {
    let tb: Int64 = 1_000_000_000_000
    let parts: [(StorageCategory, Double)] = [(.media, 0.30), (.documents, 0.10), (.apps, 0.05), (.system, 0.03), (.other, 0.07)]
    StorageBreakdownView(
        driveName: "Jesse T72",
        breakdown: StorageBreakdown(
            driveUUID: "preview",
            totalCapacity: 2 * tb,
            usedCapacity: Int64(2 * Double(tb) * 0.55),
            categories: parts.map { .init(category: $0.0, size: Int64(2 * Double(tb) * $0.1), fileCount: 0, percentage: $0.1) }
        )
    )
    .padding()
    .frame(width: 440)
}
