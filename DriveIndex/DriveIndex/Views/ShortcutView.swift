//
//  ShortcutView.swift
//  DriveIndex
//
//  Keyboard shortcut configuration view
//

import SwiftUI

struct ShortcutView: View {
    @State private var keyboardShortcut: KeyboardShortcut?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxLarge) {
                // Keyboard Shortcut
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    Text("Global Shortcut")
                        .font(DesignSystem.Typography.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, DesignSystem.Spacing.large)

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        ShortcutRecorder(shortcut: $keyboardShortcut)
                            .onChange(of: keyboardShortcut) { _, _ in
                                saveSettings()
                            }

                        Text("Press a key combination with at least one modifier (⌘, ⌃, ⌥, or ⇧)")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                    .padding(DesignSystem.Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        Text("Quick Access")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)

                        Text("Use the keyboard shortcut from anywhere to quickly search your indexed drives.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }
                .padding(DesignSystem.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignSystem.Spacing.sectionPadding)
            .padding(.vertical, DesignSystem.Spacing.large)
        }
        .navigationTitle("Shortcut")
        .task {
            loadSettings()
        }
    }

    private func loadSettings() {
        keyboardShortcut = HotkeyManager.shared.currentShortcut
    }

    private func saveSettings() {
        if let shortcut = keyboardShortcut {
            HotkeyManager.shared.updateShortcut(shortcut)
        } else {
            HotkeyManager.shared.clearShortcut()
        }
    }
}

#Preview {
    ShortcutView()
}
