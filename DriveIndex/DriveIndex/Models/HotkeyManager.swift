//
//  HotkeyManager.swift
//  DriveIndex
//
//  Manages global hotkey registration using Carbon RegisterEventHotKey
//

import Foundation
import AppKit
import Carbon.HIToolbox

class HotkeyManager: ObservableObject {
    @MainActor static let shared = HotkeyManager()

    @Published private(set) var currentShortcut: KeyboardShortcut?
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    var onHotkeyPressed: (() -> Void)?

    private let shortcutKey = "globalKeyboardShortcut"
    private let hotkeyID = EventHotKeyID(signature: OSType(0x44524956), id: 1) // 'DRIV' signature

    private init() {
        loadShortcut()
        if let shortcut = currentShortcut {
            registerHotkey(shortcut)
        }
    }

    func loadShortcut() {
        if let data = UserDefaults.standard.data(forKey: shortcutKey),
           let shortcut = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            currentShortcut = shortcut
        } else {
            currentShortcut = .default
            saveShortcut(.default)
        }
    }

    func saveShortcut(_ shortcut: KeyboardShortcut) {
        currentShortcut = shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: shortcutKey)
        }
    }

    func updateShortcut(_ shortcut: KeyboardShortcut) {
        unregisterHotkey()
        saveShortcut(shortcut)
        registerHotkey(shortcut)
    }

    func clearShortcut() {
        unregisterHotkey()
        currentShortcut = nil
        UserDefaults.standard.removeObject(forKey: shortcutKey)
    }

    private func registerHotkey(_ shortcut: KeyboardShortcut) {
        // Install event handler if not already installed
        if eventHandler == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

            let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotkeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

                // Verify this is our hotkey
                if hotkeyID.signature == manager.hotkeyID.signature && hotkeyID.id == manager.hotkeyID.id {
                    Task { @MainActor in
                        manager.onHotkeyPressed?()
                    }
                    return noErr
                }

                return OSStatus(eventNotHandledErr)
            }

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventSpec, selfPtr, &eventHandler)
        }

        // Register the hotkey
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr {
            print("✅ Global hotkey registered: \(shortcut.displayString)")
        } else {
            print("❌ Failed to register hotkey: \(status)")
        }
    }

    private func unregisterHotkey() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
    }

    deinit {
        unregisterHotkey()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
