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
    @FocusState var isSearchFocused: Bool
    let onSettingsClick: () -> Void

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
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.large)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.medium)
    }

    private var placeholderText: String {
        let driveWord = driveCount == 1 ? "drive" : "drives"
        return "Search \(driveCount) \(driveWord)..."
    }
}

#Preview {
    struct PreviewWrapper: View {
        @FocusState var isFocused1: Bool
        @FocusState var isFocused2: Bool
        @State var searchText1 = ""
        @State var searchText2 = "test file"

        var body: some View {
            VStack {
                SearchBar(
                    searchText: $searchText1,
                    driveCount: 2,
                    isSearchFocused: _isFocused1,
                    onSettingsClick: {}
                )

                SearchBar(
                    searchText: $searchText2,
                    driveCount: 5,
                    isSearchFocused: _isFocused2,
                    onSettingsClick: {}
                )
            }
            .frame(width: 400)
        }
    }

    return PreviewWrapper()
}
