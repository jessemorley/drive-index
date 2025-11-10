//
//  SearchResultsView.swift
//  DriveIndex
//
//  Displays file search results
//

import SwiftUI

struct SearchResultsView: View {
    let results: [SearchResult]
    let previousResults: [SearchResult]
    let isLoading: Bool
    var contentHeight: CGFloat = 400

    var body: some View {
        if isLoading && previousResults.isEmpty {
            loadingView
        } else if results.isEmpty && !isLoading {
            emptyStateView
        } else {
            // Show previous results while loading, or current results when done
            resultsListView(displayResults: isLoading && !previousResults.isEmpty ? previousResults : results)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.medium) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Searching...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: contentHeight)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No files found")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: contentHeight)
    }

    private func resultsListView(displayResults: [SearchResult]) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(displayResults) { result in
                    SearchResultRow(result: result)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            revealInFinder(result)
                        }

                    if result.id != displayResults.last?.id {
                        Divider()
                            .padding(.leading, Spacing.large)
                    }
                }
            }
        }
        .frame(height: contentHeight)
    }

    private func revealInFinder(_ result: SearchResult) {
        let volumePath = "/Volumes/\(result.driveName)"
        let fullPath = volumePath + "/" + result.relativePath

        let url = URL(fileURLWithPath: fullPath)

        // Check if file exists before revealing
        if FileManager.default.fileExists(atPath: fullPath) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // If file doesn't exist, show alert or just do nothing
            NSSound.beep()
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            // File icon
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 24)

            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(result.relativePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Drive badge showing connection status
            HStack(spacing: Spacing.xSmall) {
                Text(result.driveName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Circle()
                    .fill(result.isConnected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xSmall)
            .background((result.isConnected ? Color.green : Color.gray).opacity(0.1))
            .cornerRadius(4)
        }
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.medium)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

#Preview("With Results") {
    SearchResultsView(
        results: [
            SearchResult(
                id: 1,
                name: "Document.pdf",
                relativePath: "Documents/Work/Document.pdf",
                driveUUID: "123",
                driveName: "My Drive",
                isConnected: true
            ),
            SearchResult(
                id: 2,
                name: "Photo.jpg",
                relativePath: "Photos/2024/Photo.jpg",
                driveUUID: "456",
                driveName: "Backup",
                isConnected: false
            ),
        ],
        previousResults: [],
        isLoading: false
    )
    .frame(width: 400)
}

#Preview("Loading") {
    SearchResultsView(results: [], previousResults: [], isLoading: true)
        .frame(width: 400)
}

#Preview("Empty") {
    SearchResultsView(results: [], previousResults: [], isLoading: false)
        .frame(width: 400)
}
