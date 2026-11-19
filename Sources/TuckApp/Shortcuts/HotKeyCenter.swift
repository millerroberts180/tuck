import AppKit
import Carbon.HIToolbox
import TuckCore

/// Global shortcuts through the system's hot-key service (`RegisterEventHotKey`). It is public, needs
/// no permission, and tells Tuck only about the exact combinations it registered: no other keystroke
/// is ever seen. While shortcuts are off nothing is registered and no handler is installed.
final class HotKeyCenter {
    var onAction: ((ShortcutAction) -> Void)?

    private static let signature: OSType = 0x5475_636B // "Tuck"
    private var handler: EventHandlerRef?
    private var registered: [UInt32: (ref: EventHotKeyRef, action: ShortcutAction)] = [:]
    private var applied: ShortcutSet?

    /// Registers the set (or nothing, for nil) and returns the actions the system refused, because
    /// macOS or another app already has that combination.
    @discardableResult
    func apply(_ shortcuts: ShortcutSet?) -> Set<ShortcutAction> {
        if shortcuts == applied { return refused(in: shortcuts) }
        unregisterAll()
        applied = shortcuts
        guard let shortcuts else {
            removeHandler()
            return []
        }
        installHandler()
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let shortcut = shortcuts.shortcut(for: action) else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, Self.carbonModifiers(shortcut.modifiers),
                                             EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered[id] = (ref, action) }
        }
        return refused(in: shortcuts)
    }

    private func refused(in shortcuts: ShortcutSet?) -> Set<ShortcutAction> {
        guard let shortcuts else { return [] }
        let live = Set(registered.values.map(\.action))
        return Set(ShortcutAction.allCases.filter { shortcuts.shortcut(for: $0) != nil && !live.contains($0) })
    }

    private func unregisterAll() {
        registered.values.forEach { UnregisterEventHotKey($0.ref) }
        registered.removeAll()
    }

    private func installHandler() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            return center.handle(id) ? noErr : OSStatus(eventNotHandledErr)
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func removeHandler() {
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func handle(_ id: EventHotKeyID) -> Bool {
        guard id.signature == Self.signature, let action = registered[id.id]?.action else { return false }
        onAction?(action)
        return true
    }

    private static func carbonModifiers(_ modifiers: KeyShortcut.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }

    deinit {
        unregisterAll()
        removeHandler()
    }
}

extension KeyShortcut.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }
}
