import Foundation

/// Whether the window in front, as the Tuck button and Arrange windows name it, can still be acted on,
/// asked just before either does. Anything but `ready` means nothing is done to any window: the window
/// in front is read again and the fold says why.
public enum ShownWindowCheck: Hashable, Sendable {
    case ready
    /// The window has closed, or its app has quit.
    case closed
    /// Already put away: minimised, hidden with its app, parked by Tuck, or in an app Tuck is resting.
    case putAway
    /// Its app didn't answer in time.
    case busy
    /// The bar names a window the service no longer holds: another has been read since.
    case stale
    case needsPermission

    /// Checks a window the service still holds. The window is only asked whether it is put away once it
    /// is known to be open, so a quit or busy app is asked nothing more.
    public static func classify(appRunning: Bool, state: @autoclosure () -> WindowElementState,
                                isPutAway: @autoclosure () -> Bool) -> ShownWindowCheck {
        // A quit app cannot answer at all, so its window reads as unresponsive; quitting decides first.
        guard appRunning else { return .closed }
        switch state() {
        case .destroyed: return .closed
        case .unresponsive: return .busy
        case .alive: return isPutAway() ? .putAway : .ready
        }
    }

    /// Why an action found nothing to act on after all, when the check just before it said `ready`: the
    /// window closed, was put away or stopped answering in between. It is checked again for why. One
    /// that reads ready on the second asking only answered then, so it was busy the moment it was needed.
    public static func missed(rechecked: ShownWindowCheck) -> ShownWindowCheck {
        rechecked == .ready ? .busy : rechecked
    }
}

/// Tells a change of the window in front that Tuck's own move made from one the person made, by where
/// the front lands as well as when. Before a move that may bring something forward, Tuck says what: the
/// window or app it gives the keyboard to, or the app it hides and shows again. A change that lands
/// there within `span` is Tuck's. One that leaves the front where it was (a rename) brings nothing
/// forward. Any other is the person's, however soon after Tuck's move it comes.
public struct OwnFrontChanges: Sendable {
    /// Where the front is: an app, and its focused window when one can be read, tucked or not.
    public struct Landing: Hashable, Sendable {
        public let pid: Int32
        public let window: WindowToken?

        public init(pid: Int32, window: WindowToken? = nil) {
            self.pid = pid
            self.window = window
        }
    }

    /// How long a move's landing is waited for. The watcher reports a change 0.2 s after it, and a
    /// minimise may put its app back in front 0.1 s later still.
    public static let span: TimeInterval = 0.5

    /// Where the front was when last read.
    public private(set) var front: Landing?
    private var expected: [(landing: Landing, until: TimeInterval)] = []

    public init() {}

    /// Tuck is about to bring this forward: exactly this window, or with none named, whichever of the
    /// app's windows takes focus.
    public mutating func expect(_ landing: Landing, at now: TimeInterval) {
        expected.removeAll { $0.until <= now }
        expected.append((landing, now + Self.span))
    }

    /// The front was read for its own sake, as the panel opens or the window in front is read again.
    public mutating func read(_ landing: Landing?) {
        front = landing
    }

    /// The front was read after a change the watcher reported: whether the person brought it there.
    public mutating func changed(to landing: Landing?, at now: TimeInterval) -> Bool {
        defer { front = landing }
        expected.removeAll { $0.until <= now }
        guard landing != front else { return false }
        guard let landing else { return true }
        // A window that can't be read (its app is slow to answer) is taken to be the one expected.
        return !expected.contains { expected in
            expected.landing.pid == landing.pid
                && (expected.landing.window == nil || landing.window == nil || expected.landing.window == landing.window)
        }
    }
}

/// The window the open fold names (beside the Tuck button in the shallow fold, at the end of Arrange
/// windows in the full one): the window in front, kept current as it changes, and the one window Tuck
/// and Arrange act on. Once that window is tucked the name goes blank, and stays blank while Tuck hands
/// the keyboard on, so it never names the window behind a moment after the one in front went. The next
/// window the person brings forward fills it again. (The name is from when this was a bar of its own.)
public struct FrontWindowBarState: Hashable, Sendable {
    /// The window named, or nothing: none is in front, or the one named was just tucked.
    public private(set) var shown: FrontWindowInfo?
    /// Set once the named window, or another of its app's, has been tucked; let go when the person
    /// brings a window forward or back.
    public private(set) var isHeldBlank = false

    public init(shown: FrontWindowInfo? = nil) {
        self.shown = shown
    }

    /// Names the window in front, as the panel opens or when it is read again after an action found
    /// its window gone. A blank held since a tuck is let go.
    public mutating func show(_ front: FrontWindowInfo?) {
        shown = front
        isHeldBlank = false
    }

    /// The window in front changed, closed or was renamed while the panel is open. While the name is held
    /// blank, a change Tuck made itself (the keyboard handed on, an app hidden for a moment) is let go by,
    /// and so is one that leaves nothing to name (an app with no window open, a window still on its way);
    /// a window the person brings forward fills it again (`OwnFrontChanges`).
    public mutating func frontChanged(to front: FrontWindowInfo?, byPerson: Bool) {
        guard !isHeldBlank || (byPerson && front != nil) else { return }
        show(front)
    }

    /// The window in front was tucked: from the Tuck button, or by the shortcut, the menu or the notch.
    public mutating func tuckedFrontWindow() {
        shown = nil
        isHeldBlank = true
    }

    /// Windows were tucked from the picker or with Tuck All. If the named window or another of its app's
    /// was among them, the name goes blank as after a tuck from it (`ParkingPolicy.frontWindow`); tucking
    /// another app's windows leaves it as it was.
    public mutating func tucked(_ windows: [ParkedWindow]) {
        guard shown != nil, ParkingPolicy.frontWindow(shown, afterTucking: windows) == nil else { return }
        tuckedFrontWindow()
    }

    /// A tucked window has come back, at the person's asking: what comes forward with it is theirs, so a
    /// blank held since a tuck is let go and the next change fills it.
    public mutating func windowRestored() {
        isHeldBlank = false
    }
}
