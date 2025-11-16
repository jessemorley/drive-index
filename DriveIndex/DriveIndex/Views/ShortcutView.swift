//
//  ShortcutView.swift
//  DriveIndex
//
//  Keyboard shortcut configuration view
//

import SwiftUI

struct ShortcutView: View {
    @State private var keyboardShortcut: KeyboardShortcut?
    @State private var hasUnsavedChanges: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxLarge) {
                // Keyboard Shortcut
                SettingsSection(
                    title: "Global Shortcut",
                    description: "Keyboard shortcut to open the search window",
                    symbol: "keyboard"
                ) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        ShortcutRecorder(shortcut: $keyboardShortcut)
                            .onChange(of: keyboardShortcut) { _, _ in
                                hasUnsavedChanges = true
                            }

                        Text("Press a key combination with at least one modifier (⌘, ⌃, ⌥, or ⇧)")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                            .italic()
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
                        Text("Quick Access")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.semibold)

                        Text("Use the keyboard shortcut from anywhere to quickly search your indexed drives.")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                }
                .padding(DesignSystem.Spacing.medium)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            .padding(.horizontal, DesignSystem.Spacing.sectionPadding)
            .padding(.vertical, DesignSystem.Spacing.large)
        }
        .navigationTitle("Shortcut")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    saveSettings()
                }
                .disabled(!hasUnsavedChanges)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .task {
            loadSettings()
        }
    }

    private func loadSettings() {
        keyboardShortcut = HotkeyManager.shared.currentShortcut
        hasUnsavedChanges = false
    }

    private func saveSettings() {
        if let shortcut = keyboardShortcut {
            HotkeyManager.shared.updateShortcut(shortcut)
        } else {
            HotkeyManager.shared.clearShortcut()
        }
        hasUnsavedChanges = false
    }
}

#Preview {
    ShortcutView()
}
