import Foundation
import TuckCore

/// User preferences backed by UserDefaults. Changes are pushed to the model through `onChange`.
final class SettingsStore: ObservableObject {
    private enum Key {
        static let clipboardHistory = "clipboardHistory"
        static let clipboardRetention = "clipboardRetention"
        static let clipboardImageText = "clipboardImageText"
        static let showsCopyTimes = "showsCopyTimes"
        static let haptics = "haptics"
        static let windowDrag = "windowDrag"
        static let windowDragModifiers = "windowDragModifiers"
        static let smoothScrolling = "smoothScrolling"
        static let scrollSmoothness = "scrollSmoothness"
        static let reverseMouseWheel = "reverseMouseWheel"
        static let shortcutsEnabled = "shortcutsEnabled"
        static let shortcuts = "shortcuts"
        static let menuBarIcon = "menuBarIcon"
        static let surfaceDisplays = "surfaceDisplays"
        static let notchlessStyle = "notchlessStyle"
        static let showInFullScreen = "showInFullScreen"
        static let showInScreenshots = "showInScreenshots"
        static let dropInvitation = "dropInvitation"
        static let cardColumns = "cardColumns"
        static let cardSize = "cardSize"
    }

    private let defaults: UserDefaults
    var onChange: ((SettingsStore) -> Void)?

    @Published var clipboardHistoryEnabled: Bool {
        didSet { defaults.set(clipboardHistoryEnabled, forKey: Key.clipboardHistory); onChange?(self) }
    }
    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention); onChange?(self) }
    }
    /// Reads the words in copied images on this Mac, so search finds a screenshot by what it shows.
    @Published var clipboardReadsImageText: Bool {
        didSet { defaults.set(clipboardReadsImageText, forKey: Key.clipboardImageText); onChange?(self) }
    }
    /// Tiles wear the time each was copied or added. Off by default: a tile shows its type and size.
    @Published var showsCopyTimes: Bool {
        didSet { defaults.set(showsCopyTimes, forKey: Key.showsCopyTimes); onChange?(self) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.haptics); onChange?(self) }
    }
    /// Modifier-drag move and resize. Off by default; needs Accessibility.
    @Published var windowDragEnabled: Bool {
        didSet { defaults.set(windowDragEnabled, forKey: Key.windowDrag); onChange?(self) }
    }
    @Published var windowDragModifiers: WindowDragModifiers {
        didSet { defaults.set(windowDragModifiers.rawValue, forKey: Key.windowDragModifiers); onChange?(self) }
    }
    /// Smooth scrolling for notched mouse wheels. Off by default; needs Accessibility.
    @Published var smoothScrollingEnabled: Bool {
        didSet { defaults.set(smoothScrollingEnabled, forKey: Key.smoothScrolling); onChange?(self) }
    }
    @Published var scrollSmoothness: ScrollSmoothness {
        didSet { defaults.set(scrollSmoothness.rawValue, forKey: Key.scrollSmoothness); onChange?(self) }
    }
    /// Experimental Rest for allow-listed apps. Off by default; turning it off wakes any rested app.
    @Published var restEnabled: Bool {
        didSet { defaults.set(restEnabled, forKey: RestSwitch.key); onChange?(self) }
    }
    /// Reverses mouse-wheel direction only; trackpad scrolling keeps the system setting.
    @Published var reverseMouseWheel: Bool {
        didSet { defaults.set(reverseMouseWheel, forKey: Key.reverseMouseWheel); onChange?(self) }
    }
    /// Global keyboard shortcuts. Off by default; while off, none are registered.
    @Published var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: Key.shortcutsEnabled); onChange?(self) }
    }
    @Published private(set) var shortcuts: ShortcutSet {
        didSet { defaults.set(try? JSONEncoder().encode(shortcuts), forKey: Key.shortcuts); onChange?(self) }
    }
    /// The menu-bar item. On by default; while it's off, Settings opens from the panel's gear or by
    /// opening Tuck again.
    @Published var menuBarIconShown: Bool {
        didSet { defaults.set(menuBarIconShown, forKey: Key.menuBarIcon); onChange?(self) }
    }
    /// Which displays show the surface. All by default.
    @Published var surfaceDisplays: SurfaceDisplays {
        didSet { defaults.set(surfaceDisplays.rawValue, forKey: Key.surfaceDisplays); onChange?(self) }
    }
    /// How the surface looks on displays without a notch. A bubble by default.
    @Published var notchlessStyle: NotchlessStyle {
        didSet { defaults.set(notchlessStyle.rawValue, forKey: Key.notchlessStyle); onChange?(self) }
    }
    /// Whether the surface stays at the top of the screen beside full-screen apps. On by default.
    @Published var showInFullScreen: Bool {
        didSet { defaults.set(showInFullScreen, forKey: Key.showInFullScreen); onChange?(self) }
    }
    /// Whether the surface, and windows flying into it, appear in screenshots and recordings. On by default.
    @Published var showInScreenshots: Bool {
        didSet { defaults.set(showInScreenshots, forKey: Key.showInScreenshots); onChange?(self) }
    }
    /// The drop invitation: a drag heading for the top of the screen grows the surface into Tuck's one drop
    /// target, which says what the drag carries. On by default; while it's off, drags aren't watched at all.
    @Published var dropInvitation: Bool {
        didSet { defaults.set(dropInvitation, forKey: Key.dropInvitation); onChange?(self) }
    }
    /// How many cards sit side by side in the fold: the shallow fold's one row, and each of the full
    /// fold's. Three by default.
    @Published var cardColumns: Int {
        didSet { defaults.set(cardColumns, forKey: Key.cardColumns); onChange?(self) }
    }
    /// How big the fold's cards are. Medium by default.
    @Published var cardSize: CardSize {
        didSet { defaults.set(cardSize.rawValue, forKey: Key.cardSize); onChange?(self) }
    }
    var cardLayout: CardLayout { CardLayout(columns: cardColumns, size: cardSize) }
    /// The action whose shortcut is being typed in Settings. Shortcuts are paused meanwhile, so pressing
    /// one records it instead of running it.
    @Published var recordingShortcut: ShortcutAction? {
        didSet { if oldValue != recordingShortcut { onChange?(self) } }
    }
    /// Shortcuts the system refused because macOS or another app already uses them. Reported, not saved.
    @Published var refusedShortcuts: Set<ShortcutAction> = []

    @discardableResult
    func assign(_ shortcut: KeyShortcut?, to action: ShortcutAction) -> ShortcutSet.Assignment {
        var updated = shortcuts
        let result = updated.assign(shortcut, to: action)
        if updated != shortcuts { shortcuts = updated }
        return result
    }

    func resetShortcuts() {
        if shortcuts != .defaults { shortcuts = .defaults }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.clipboardHistory: false,
            Key.clipboardRetention: ClipboardRetention.oneDay.rawValue,
            Key.clipboardImageText: true,
            Key.showsCopyTimes: false,
            Key.haptics: true,
            Key.windowDrag: false,
            Key.windowDragModifiers: WindowDragModifiers.controlOption.rawValue,
            Key.smoothScrolling: false,
            Key.scrollSmoothness: ScrollSmoothness.balanced.rawValue,
            Key.reverseMouseWheel: false,
            Key.shortcutsEnabled: false,
            Key.menuBarIcon: true,
            Key.surfaceDisplays: SurfaceDisplays.all.rawValue,
            Key.notchlessStyle: NotchlessStyle.bubble.rawValue,
            Key.showInFullScreen: true,
            Key.showInScreenshots: true,
            Key.dropInvitation: true,
            Key.cardColumns: CardLayout.standard.columns,
            Key.cardSize: CardSize.medium.rawValue,
            RestSwitch.key: false
        ])
        restEnabled = defaults.bool(forKey: RestSwitch.key)
        clipboardHistoryEnabled = defaults.bool(forKey: Key.clipboardHistory)
        clipboardRetention = ClipboardRetention(rawValue: defaults.string(forKey: Key.clipboardRetention) ?? "") ?? .oneDay
        clipboardReadsImageText = defaults.bool(forKey: Key.clipboardImageText)
        showsCopyTimes = defaults.bool(forKey: Key.showsCopyTimes)
        hapticsEnabled = defaults.bool(forKey: Key.haptics)
        windowDragEnabled = defaults.bool(forKey: Key.windowDrag)
        windowDragModifiers = WindowDragModifiers(rawValue: defaults.string(forKey: Key.windowDragModifiers) ?? "") ?? .controlOption
        smoothScrollingEnabled = defaults.bool(forKey: Key.smoothScrolling)
        scrollSmoothness = ScrollSmoothness(rawValue: defaults.string(forKey: Key.scrollSmoothness) ?? "") ?? .balanced
        reverseMouseWheel = defaults.bool(forKey: Key.reverseMouseWheel)
        shortcutsEnabled = defaults.bool(forKey: Key.shortcutsEnabled)
        shortcuts = ShortcutSet.load(from: defaults.data(forKey: Key.shortcuts))
        menuBarIconShown = defaults.bool(forKey: Key.menuBarIcon)
        surfaceDisplays = SurfaceDisplays(rawValue: defaults.string(forKey: Key.surfaceDisplays) ?? "") ?? .all
        notchlessStyle = NotchlessStyle(rawValue: defaults.string(forKey: Key.notchlessStyle) ?? "") ?? .bubble
        showInFullScreen = defaults.bool(forKey: Key.showInFullScreen)
        showInScreenshots = defaults.bool(forKey: Key.showInScreenshots)
        dropInvitation = defaults.bool(forKey: Key.dropInvitation)
        cardColumns = CardLayout(columns: defaults.integer(forKey: Key.cardColumns)).columns
        cardSize = CardSize(rawValue: defaults.string(forKey: Key.cardSize) ?? "") ?? .medium
    }
}
