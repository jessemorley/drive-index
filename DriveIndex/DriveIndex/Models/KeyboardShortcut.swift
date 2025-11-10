//
//  KeyboardShortcut.swift
//  DriveIndex
//
//  Model for keyboard shortcuts
//

import Foundation
import AppKit
import Carbon.HIToolbox

struct KeyboardShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt32

    var displayString: String {
        var parts: [String] = []

        // Add modifier symbols
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }

        // Add key character
        if let keyChar = keyCodeToString(keyCode) {
            parts.append(keyChar)
        }

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "⏎"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            // Try to get the character from the keyboard layout
            let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)

            guard layoutData != nil else { return nil }

            let layout = unsafeBitCast(layoutData, to: CFData.self)
            let layoutPtr = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)

            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var actualLength = 0

            UCKeyTranslate(
                layoutPtr,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &actualLength,
                &chars
            )

            if actualLength > 0 {
                return String(utf16CodeUnits: chars, count: actualLength).uppercased()
            }

            return nil
        }
    }

    // Convert NSEvent modifiers to Carbon modifiers
    static func carbonModifiers(from nsModifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0

        if nsModifiers.contains(.control) {
            carbonMods |= UInt32(controlKey)
        }
        if nsModifiers.contains(.option) {
            carbonMods |= UInt32(optionKey)
        }
        if nsModifiers.contains(.shift) {
            carbonMods |= UInt32(shiftKey)
        }
        if nsModifiers.contains(.command) {
            carbonMods |= UInt32(cmdKey)
        }

        return carbonMods
    }

    // Convert Carbon modifiers to CGEventFlags for event tap
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []

        if modifiers & UInt32(controlKey) != 0 {
            flags.insert(.maskControl)
        }
        if modifiers & UInt32(optionKey) != 0 {
            flags.insert(.maskAlternate)
        }
        if modifiers & UInt32(shiftKey) != 0 {
            flags.insert(.maskShift)
        }
        if modifiers & UInt32(cmdKey) != 0 {
            flags.insert(.maskCommand)
        }

        return flags
    }
}

extension KeyboardShortcut {
    // Default shortcut: Cmd+Shift+Space
    static let `default` = KeyboardShortcut(
        keyCode: UInt16(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey)
    )
}
