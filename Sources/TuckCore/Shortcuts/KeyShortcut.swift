import Foundation

/// A global keyboard shortcut: one key plus modifiers. Framework-free; the app turns it into a system
/// hot key. `keyCode` is the hardware key code, which is what the system matches; `key` is the label
/// shown for it, taken from the keyboard layout when the shortcut was recorded.
public struct KeyShortcut: Codable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public let keyCode: UInt32
    public let key: String
    public let modifiers: Modifiers

    public init(keyCode: UInt32, key: String, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.key = key
        self.modifiers = modifiers
    }

    /// As macOS writes it: ⌃⌥⇧⌘ in that order, then the key.
    public var title: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }

    /// Why this can't be a global shortcut, or nil if it can. At least two of ⌃, ⌥ and ⌘ keeps it out of
    /// the way of apps' own shortcuts (⌘C, ⌘⇧T and the like), which it would otherwise take over.
    public var problem: String? {
        let strong = [Modifiers.control, .option, .command].filter { modifiers.contains($0) }.count
        return strong >= 2 ? nil : "Use at least two of ⌃ ⌥ ⌘, so it can't take over an app's own shortcut."
    }

    /// The label for a key: a name or symbol for keys that type nothing visible, otherwise what the key
    /// types, in capitals.
    public static func label(forKeyCode keyCode: UInt32, characters: String?) -> String {
        if let name = namedKeys[keyCode] { return name }
        let typed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return typed.isEmpty ? "Key \(keyCode)" : typed
    }

    private static let namedKeys: [UInt32: String] = [
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15"
    ]
}

/// Two shortcuts are the same when they press the same keys; the label is only how one is shown.
extension KeyShortcut: Hashable {
    public static func == (lhs: KeyShortcut, rhs: KeyShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }
}

/// What a global shortcut can do. Each acts on one thing: never more than one window at a time.
public enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case tuckFrontWindow
    case restoreLastTucked
    case togglePanel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tuckFrontWindow: "Tuck Front Window"
        case .restoreLastTucked: "Restore Last Tucked Window"
        case .togglePanel: "Open or Close Tuck"
        }
    }

    /// ⌃⌥⌘ with a letter: a combination apps and window managers rarely use.
    public var defaultShortcut: KeyShortcut {
        let all: KeyShortcut.Modifiers = [.control, .option, .command]
        switch self {
        case .tuckFrontWindow: return KeyShortcut(keyCode: 17, key: "T", modifiers: all)
        case .restoreLastTucked: return KeyShortcut(keyCode: 15, key: "R", modifiers: all)
        case .togglePanel: return KeyShortcut(keyCode: 31, key: "O", modifiers: all)
        }
    }
}

/// Which shortcut does what. An action can have none; no two actions share one.
public struct ShortcutSet: Equatable, Sendable {
    public enum Assignment: Equatable, Sendable {
        case assigned
        case rejected(String)
    }

    private var assignments: [ShortcutAction: KeyShortcut]

    public static let defaults = ShortcutSet(
        assignments: Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
    )

    private init(assignments: [ShortcutAction: KeyShortcut]) {
        self.assignments = assignments
    }

    public func shortcut(for action: ShortcutAction) -> KeyShortcut? {
        assignments[action]
    }

    public func action(for shortcut: KeyShortcut) -> ShortcutAction? {
        assignments.first { $0.value == shortcut }?.key
    }

    /// Sets or clears (nil) an action's shortcut. A shortcut that can't be global, or that another
    /// action already uses, is refused and nothing changes.
    @discardableResult
    public mutating func assign(_ shortcut: KeyShortcut?, to action: ShortcutAction) -> Assignment {
        guard let shortcut else {
            assignments[action] = nil
            return .assigned
        }
        if let problem = shortcut.problem { return .rejected(problem) }
        if let other = self.action(for: shortcut), other != action {
            return .rejected("\(shortcut.title) is already used for \(other.title).")
        }
        assignments[action] = shortcut
        return .assigned
    }
}

/// Stored as the shortcuts that are set, by action name, so a cleared shortcut stays cleared rather than
/// coming back as its default.
extension ShortcutSet: Codable {
    public init(from decoder: Decoder) throws {
        let stored = try decoder.singleValueContainer().decode([String: KeyShortcut].self)
        var set = ShortcutSet(assignments: [:])
        for (name, shortcut) in stored {
            guard let action = ShortcutAction(rawValue: name) else { continue }
            set.assign(shortcut, to: action)
        }
        self = set
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: assignments.map { ($0.key.rawValue, $0.value) }))
    }

    /// The saved set, or the defaults when nothing has been saved or it can't be read.
    public static func load(from data: Data?) -> ShortcutSet {
        guard let data, let set = try? JSONDecoder().decode(ShortcutSet.self, from: data) else { return .defaults }
        return set
    }
}
