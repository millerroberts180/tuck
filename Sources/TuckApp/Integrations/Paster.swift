import AppKit
import Carbon.HIToolbox

/// Types ⌘V into the app in front, for a double-click that pastes what Tuck just copied. Behind a
/// protocol, as the pasteboard and the opener are, so snapshots and tests never post a keystroke.
protocol KeystrokePasting {
    /// Posts ⌘V to whatever has the keyboard; false when it couldn't, so the copy waits for the person.
    func paste() -> Bool
}

/// Never pastes: snapshots, tests and anywhere a model is made without the real keyboard.
struct NoPaster: KeystrokePasting {
    func paste() -> Bool { false }
}

/// Posts ⌘V as the keyboard would. The key is the one that types "v" with ⌘ held in the layout in use,
/// so the paste lands on Dvorak or AZERTY as on QWERTY, and on a layout that switches to QWERTY under
/// ⌘. macOS lets Tuck post keys only while Accessibility allows it.
struct SystemPaster: KeystrokePasting {
    func paste() -> Bool {
        // A field of Tuck's own still holding the keyboard would take the paste itself.
        guard AX.isTrusted, !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
        let key = Self.keyCode(for: "v")
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    /// The key that types `character` with ⌘ held: in the current layout, then in the ASCII layout macOS
    /// falls back to for shortcuts, then where it is on a US keyboard. Looked up each time, as the layout
    /// can change between pastes.
    static func keyCode(for character: Character) -> CGKeyCode {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let code = keyCode(for: character, in: source) { return code }
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let code = keyCode(for: character, in: source) { return code }
        return CGKeyCode(kVK_ANSI_V)
    }

    private static func keyCode(for character: Character, in source: TISInputSource) -> CGKeyCode? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let wanted = String(character).lowercased()
        return bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout -> CGKeyCode? in
            let command = UInt32((cmdKey >> 8) & 0xFF)
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var typed = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown), command, UInt32(LMGetKbdType()),
                                            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, typed.count, &length, &typed)
                if status == noErr, length > 0, String(utf16CodeUnits: typed, count: length).lowercased() == wanted {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}
