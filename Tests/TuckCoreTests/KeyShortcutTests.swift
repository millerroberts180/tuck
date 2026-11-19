import Foundation
import Testing
@testable import TuckCore

@Suite("Keyboard shortcuts")
struct KeyShortcutTests {
    let all: KeyShortcut.Modifiers = [.control, .option, .command]

    func shortcut(_ key: String, _ code: UInt32, _ modifiers: KeyShortcut.Modifiers) -> KeyShortcut {
        KeyShortcut(keyCode: code, key: key, modifiers: modifiers)
    }

    @Test func defaultsAreDistinctUsableAndWrittenTheMacWay() {
        let set = ShortcutSet.defaults
        let shortcuts = ShortcutAction.allCases.compactMap { set.shortcut(for: $0) }
        #expect(shortcuts.count == ShortcutAction.allCases.count)
        #expect(Set(shortcuts).count == shortcuts.count)
        #expect(shortcuts.allSatisfy { $0.problem == nil })
        #expect(shortcuts.map(\.title) == ["⌃⌥⌘T", "⌃⌥⌘R", "⌃⌥⌘O"])
    }

    @Test func modifiersAreWrittenInTheSystemOrder() {
        #expect(shortcut("K", 40, [.command, .shift, .control]).title == "⌃⇧⌘K")
        #expect(shortcut("K", 40, [.option, .command]).title == "⌥⌘K")
    }

    @Test func aGlobalShortcutNeedsTwoOfControlOptionAndCommand() {
        #expect(shortcut("C", 8, [.command]).problem != nil)
        #expect(shortcut("T", 17, [.command, .shift]).problem != nil)
        #expect(shortcut("T", 17, [.control, .shift]).problem != nil)
        #expect(shortcut("T", 17, []).problem != nil)
        #expect(shortcut("T", 17, [.control, .option]).problem == nil)
        #expect(shortcut("I", 34, [.option, .command]).problem == nil)
        #expect(shortcut("T", 17, all.union(.shift)).problem == nil)
    }

    @Test func keysThatTypeNothingVisibleGetNames() {
        #expect(KeyShortcut.label(forKeyCode: 49, characters: " ") == "Space")
        #expect(KeyShortcut.label(forKeyCode: 36, characters: "\r") == "↩")
        #expect(KeyShortcut.label(forKeyCode: 123, characters: nil) == "←")
        #expect(KeyShortcut.label(forKeyCode: 96, characters: nil) == "F5")
        #expect(KeyShortcut.label(forKeyCode: 17, characters: "t") == "T")
        #expect(KeyShortcut.label(forKeyCode: 200, characters: "") == "Key 200")
    }

    @Test func theSameKeysAreTheSameShortcutWhateverTheLabel() {
        #expect(shortcut("T", 17, all) == shortcut("Z", 17, all))
        #expect(shortcut("T", 17, all) != shortcut("T", 17, [.control, .option]))
    }

    @Test func aShortcutAnotherActionUsesIsRefusedAndNothingChanges() {
        var set = ShortcutSet.defaults
        let result = set.assign(ShortcutAction.togglePanel.defaultShortcut, to: .tuckFrontWindow)
        #expect(result == .rejected("⌃⌥⌘O is already used for Open or Close Tuck."))
        #expect(set == .defaults)
    }

    @Test func anUnusableShortcutIsRefusedAndNothingChanges() {
        var set = ShortcutSet.defaults
        guard case .rejected = set.assign(shortcut("C", 8, [.command]), to: .tuckFrontWindow) else {
            Issue.record("⌘C was accepted")
            return
        }
        #expect(set == .defaults)
    }

    @Test func assigningAndClearing() {
        var set = ShortcutSet.defaults
        let new = shortcut("K", 40, [.control, .option])
        #expect(set.assign(new, to: .tuckFrontWindow) == .assigned)
        #expect(set.action(for: new) == .tuckFrontWindow)
        #expect(set.action(for: ShortcutAction.tuckFrontWindow.defaultShortcut) == nil)
        // An action keeping its own shortcut is not a clash.
        #expect(set.assign(new, to: .tuckFrontWindow) == .assigned)
        #expect(set.assign(nil, to: .restoreLastTucked) == .assigned)
        #expect(set.shortcut(for: .restoreLastTucked) == nil)
    }

    @Test func aClearedShortcutStaysClearedWhenSavedAndLoaded() throws {
        var set = ShortcutSet.defaults
        set.assign(nil, to: .togglePanel)
        set.assign(shortcut("K", 40, [.control, .option]), to: .tuckFrontWindow)
        let loaded = ShortcutSet.load(from: try JSONEncoder().encode(set))
        #expect(loaded == set)
        #expect(loaded.shortcut(for: .togglePanel) == nil)
        #expect(loaded.shortcut(for: .tuckFrontWindow)?.title == "⌃⌥K")
    }

    @Test func nothingSavedOrUnreadableMeansTheDefaults() {
        #expect(ShortcutSet.load(from: nil) == .defaults)
        #expect(ShortcutSet.load(from: Data("not json".utf8)) == .defaults)
    }

    @Test func savedShortcutsThatAreNoLongerAllowedAreDropped() throws {
        let stored = ["tuckFrontWindow": shortcut("C", 8, [.command]), "somethingRemoved": ShortcutAction.togglePanel.defaultShortcut]
        let loaded = ShortcutSet.load(from: try JSONEncoder().encode(stored))
        #expect(loaded.shortcut(for: .tuckFrontWindow) == nil)
        #expect(loaded.action(for: ShortcutAction.togglePanel.defaultShortcut) == nil)
    }
}
