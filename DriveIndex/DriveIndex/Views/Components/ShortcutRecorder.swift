//
//  ShortcutRecorder.swift
//  DriveIndex
//
//  Custom UI component for recording keyboard shortcuts
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

// MARK: - Custom Panel that can become key
class KeyCapturePanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}

// MARK: - NSView for capturing key events
class ShortcutRecorderNSView: NSView {
    var onShortcutRecorded: ((KeyboardShortcut) -> Void)?
    var isRecording: Bool = false {
        didSet {
            needsDisplay = true
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Require at least one modifier
        guard !modifiers.intersection([.command, .control, .option, .shift]).isEmpty else {
            NSSound.beep()
            return
        }

        let carbonModifiers = KeyboardShortcut.carbonModifiers(from: modifiers)
        let shortcut = KeyboardShortcut(
            keyCode: UInt16(event.keyCode),
            modifiers: carbonModifiers
        )

        onShortcutRecorded?(shortcut)
        isRecording = false
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't do anything on modifier-only changes
        super.flagsChanged(with: event)
    }
}

// MARK: - SwiftUI View
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyboardShortcut?
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: Spacing.small) {
            ShortcutRecorderButton(
                shortcut: shortcut,
                isRecording: isRecording,
                onShortcutRecorded: { newShortcut in
                    shortcut = newShortcut
                    isRecording = false
                },
                onStartRecording: {
                    isRecording = true
                },
                onStopRecording: {
                    isRecording = false
                }
            )
            .frame(minWidth: 150, minHeight: 32)

            if shortcut != nil {
                Button(action: {
                    shortcut = nil
                    isRecording = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
    }
}

struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: KeyboardShortcut?
    let isRecording: Bool
    let onShortcutRecorded: (KeyboardShortcut) -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .rounded
        button.target = context.coordinator
        button.action = #selector(Coordinator.buttonClicked)

        updateButton(button)

        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        updateButton(nsView)
        context.coordinator.parent = self
    }

    private func updateButton(_ button: NSButton) {
        if isRecording {
            button.title = "Press keys..."
            button.contentTintColor = .systemBlue
        } else if let shortcut = shortcut {
            button.title = shortcut.displayString
            button.contentTintColor = nil
        } else {
            button.title = "Click to record"
            button.contentTintColor = .secondaryLabelColor
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: ShortcutRecorderButton
        var recorderView: ShortcutRecorderNSView?
        var recorderWindow: NSWindow?

        init(_ parent: ShortcutRecorderButton) {
            self.parent = parent
        }

        @objc func buttonClicked() {
            if parent.isRecording {
                parent.onStopRecording()
                closeRecorder()
            } else {
                parent.onStartRecording()
                showRecorder()
            }
        }

        private func showRecorder() {
            let view = ShortcutRecorderNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
            view.isRecording = true
            view.onShortcutRecorded = { [weak self] shortcut in
                self?.parent.onShortcutRecorded(shortcut)
                self?.closeRecorder()
            }

            // Create a custom panel that CAN become key
            let panel = KeyCapturePanel(
                contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.level = .floating
            panel.contentView = view

            // Make the panel key and set first responder
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)

            self.recorderView = view
            self.recorderWindow = panel
        }

        private func closeRecorder() {
            recorderWindow?.close()
            recorderWindow = nil
            recorderView = nil
        }
    }
}

#Preview {
    @Previewable @State var shortcut: KeyboardShortcut? = .default

    VStack(spacing: 20) {
        ShortcutRecorder(shortcut: $shortcut)

        if let shortcut = shortcut {
            Text("Current: \(shortcut.displayString)")
                .font(.caption)
        }
    }
    .padding()
    .frame(width: 400)
}
