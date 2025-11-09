//
//  SearchBar.swift
//  DriveIndex
//
//  Search bar component with integrated settings button
//

import SwiftUI

struct SearchBar: View {
    @Binding var searchText: String
    let driveCount: Int
    let onSettingsClick: () -> Void

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.body)

            TextField(
                "",
                text: $searchText,
                prompt: Text(placeholderText)
                    .foregroundStyle(.tertiary)
            )
            .textFieldStyle(.plain)
            .focused($isSearchFocused)
            .font(.body)

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    isSearchFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.borderless)
            }

            Button(action: onSettingsClick) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.medium)
    }

    private var placeholderText: String {
        let driveWord = driveCount == 1 ? "drive" : "drives"
        return "Search \(driveCount) \(driveWord)..."
    }
}

#Preview {
    VStack {
        SearchBar(
            searchText: .constant(""),
            driveCount: 2,
            onSettingsClick: {}
        )

        SearchBar(
            searchText: .constant("test file"),
            driveCount: 5,
            onSettingsClick: {}
        )
    }
    .frame(width: 400)
}
