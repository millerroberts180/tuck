import AppKit
import TuckCore

/// A key the fold's tiles answer: an arrow, or Return or Space to open the tile the arrows are on.
/// Only bare keys count, so Shift-arrows still select in the search field.
enum TileKey: Equatable {
    case move(TileNavigation.Move)
    case open(isSpace: Bool)

    init?(_ event: NSEvent) {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
        switch event.keyCode {
        case 123: self = .move(.left)
        case 124: self = .move(.right)
        case 125: self = .move(.down)
        case 126: self = .move(.up)
        case 36, 76: self = .open(isSpace: false)
        case 49: self = .open(isSpace: true)
        default: return nil
        }
    }
}

/// Borderless, non-activating panel that floats above the menu bar on every Space, including beside
/// full-screen apps, without becoming the active app or appearing in Mission Control or the Cmd-Tab cycle.
/// The surface is black, closed and open, so what is drawn on it and the open panel inside it resolve in
/// the dark appearance (`Theme.notchAppearance`) whatever the Light or Dark setting.
final class OverlayPanel: NSPanel {
    /// One above the status-bar level. While the menu bar is hidden (auto-hide, or full screen), macOS 27
    /// lays an invisible window at the status-bar level across a notched display's menu-bar strip, which
    /// would take the notch's clicks; one level up still sits well under menus, alerts and system HUDs.
    static let surfaceLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    var onCancel: (() -> Void)?
    /// The arrow keys, Return and Space, offered to the tiles before the search field or anything else
    /// in the fold sees them; returns whether the tiles used the key.
    var onTileKey: ((TileKey) -> Bool)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = Self.surfaceLevel
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = nil
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        acceptsMouseMovedEvents = false
    }

    /// Settings → Notch: whether the surface stays beside full-screen apps, and whether it appears in
    /// screenshots and recordings.
    func apply(showInFullScreen: Bool, showInScreenshots: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if showInFullScreen { behavior.insert(.fullScreenAuxiliary) }
        if collectionBehavior != behavior { collectionBehavior = behavior }
        sharingType = showInScreenshots ? .readOnly : .none
    }

    // Key for the search field and the inline text editor, for Escape in a panel opened from the keyboard,
    // and for the full fold, whose list scrolls straight away; it does not activate Tuck.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let key = TileKey(event), onTileKey?(key) == true { return }
        super.sendEvent(event)
    }

    /// Tuck has no main menu, so the editing keys a menu would supply reach the search field and the
    /// text editor from here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard firstResponder is NSText else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let action: Selector? = switch (modifiers, event.charactersIgnoringModifiers ?? "") {
        case (.command, "a"): #selector(NSText.selectAll(_:))
        case (.command, "c"): #selector(NSText.copy(_:))
        case (.command, "v"): #selector(NSText.paste(_:))
        case (.command, "x"): #selector(NSText.cut(_:))
        case (.command, "z"): Selector(("undo:"))
        case ([.command, .shift], "z"), ([.command, .shift], "Z"): Selector(("redo:"))
        default: nil
        }
        guard let action else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }
}
