import CoreGraphics
import Foundation

/// The pretend screen in Tuck's setup: a notch, a Notes window and a PDF, and what the person has done
/// with them. The tour and the gesture step share it, so whatever was tucked on one is still there on
/// the other. Plain state, so both can be checked without a window; the setup view draws it and runs
/// Tuck's own swipe, drop and flight logic on it.
public struct TourDesk: Equatable, Sendable {
    /// What the tour teaches, in the order Tuck is used.
    public enum Move: String, CaseIterable, Sendable {
        case open, tuck, hold, bringBack
    }

    /// The swipes the gesture step teaches: opening the fold, deepening it and closing it. Only swipes
    /// count; clicks never tick these off. Tucking Tuck away and bringing it back still work here, as on
    /// the real notch, but aren't taught, so they tick nothing.
    public enum Gesture: String, CaseIterable, Sendable {
        case open, unfold, close
    }

    /// What can be in Tuck here.
    public enum Item: String, Sendable {
        case window, file

        /// The lens beside the notch that shows it.
        public var lens: StreamLens { self == .window ? .windows : .files }
    }

    /// The lens lives only in the shallow fold: deepening, closing or tucking away lets it go.
    public private(set) var stage: SwipeGestureTracker.Stage = .collapsed {
        didSet { if stage != .expanded { lens = nil } }
    }
    /// What's in Tuck, newest first, as its one stream lists it.
    public private(set) var stream: [Item] = []
    /// The lens chosen beside the notch, narrowing the stream; nil shows everything.
    public private(set) var lens: StreamLens?
    /// The held PDF has been dragged out into the note.
    public private(set) var isAttached = false
    /// Each move and gesture counts once, however often it's repeated.
    public private(set) var done: Set<Move> = []
    public private(set) var latest: Move?
    public private(set) var tried: Set<Gesture> = []
    public private(set) var latestGesture: Gesture?

    public init() {}

    public var isOpen: Bool { stage == .expanded || stage == .full }
    public var isFull: Bool { stage == .full }
    public var isTuckedAway: Bool { stage == .tucked }
    /// The Notes window is in Tuck.
    public var isWindowTucked: Bool { stream.contains(.window) }
    /// The PDF is in Tuck. Tuck keeps a reference, so the file itself stays on the desk either way.
    public var isFileHeld: Bool { stream.contains(.file) }
    /// How much Tuck holds on the pretend screen.
    public var count: Int { stream.count }
    /// What the open fold lists: the stream, narrowed by the lens.
    public var rows: [Item] { stream.filter { lens == nil || $0.lens == lens } }

    /// The first move not done yet, for the tour's instruction; nil once everything has been tried.
    public var next: Move? { Move.allCases.first { !done.contains($0) } }

    // MARK: Clicks

    /// A click on the notch: opens or closes the fold, and brings back a tucked-away surface.
    public mutating func toggle() {
        switch stage {
        case .tucked: stage = .collapsed
        case .collapsed: open()
        case .expanded, .full: close()
        }
    }

    public mutating func open() {
        guard !isOpen else { return }
        stage = .expanded
        record(.open)
    }

    public mutating func close() {
        if isOpen { stage = .collapsed }
    }

    /// A lens beside the notch in the shallow fold: narrows the stream to it, or, chosen again, shows
    /// everything again.
    public mutating func toggleLens(_ choice: StreamLens) {
        guard stage == .expanded else { return }
        lens = lens == choice ? nil : choice
    }

    /// Tuck, on the open fold's band: the window goes into Tuck, at the top of the stream.
    @discardableResult
    public mutating func tuckWindow() -> Bool {
        guard isOpen, !isWindowTucked else { return false }
        arrive(.window)
        record(.tuck)
        return true
    }

    /// The PDF let go over the notch or the open fold. Dropping it again changes nothing: it's held.
    @discardableResult
    public mutating func holdFile() -> Bool {
        if isTuckedAway { stage = .collapsed }
        guard !isFileHeld else { return false }
        arrive(.file)
        record(.hold)
        return true
    }

    /// Clicking the window's row: it goes back where it was.
    @discardableResult
    public mutating func restoreWindow() -> Bool {
        guard isOpen, isWindowTucked else { return false }
        stream.removeAll { $0 == .window }
        record(.bringBack)
        return true
    }

    /// The held PDF dragged out of the fold into the Notes window. It stays held, as a held item does
    /// when it's dragged out to be used.
    @discardableResult
    public mutating func attachFile() -> Bool {
        guard isOpen, isFileHeld, !isWindowTucked else { return false }
        isAttached = true
        record(.bringBack)
        return true
    }

    // MARK: Swipes

    /// Applies a committed swipe from the real `SwipeGestureTracker`. Returns whether it changed
    /// anything; like the real surface, a swipe plays no haptic.
    @discardableResult
    public mutating func apply(_ action: SwipeGestureTracker.Action) -> Bool {
        switch action {
        case .expand:
            guard !isOpen else { return false }
            open()
            mark(.open)
            return true
        case .unfold:
            guard stage == .expanded else { return false }
            stage = .full
            mark(.unfold)
            return true
        case .fold:
            guard stage == .full else { return false }
            stage = .expanded
            return true
        case .collapse:
            guard isOpen else { return false }
            stage = .collapsed
            mark(.close)
            return true
        case .tuckAway:
            guard stage == .collapsed else { return false }
            stage = .tucked
            return true
        case .reveal:
            guard isTuckedAway else { return false }
            stage = .collapsed
            return true
        }
    }

    /// Whatever arrives shows at the top of the stream, so a lens that would hide it is let go.
    private mutating func arrive(_ item: Item) {
        stream.insert(item, at: 0)
        lens = nil
    }

    private mutating func record(_ move: Move) {
        done.insert(move)
        latest = move
    }

    private mutating func mark(_ gesture: Gesture) {
        tried.insert(gesture)
        latestGesture = gesture
    }
}

/// Where things sit on the pretend screen, in points with y growing upwards (as AppKit and Tuck's
/// geometry expect), so setup can run Tuck's own drop invitation and card flight on it. The screen is a
/// scaled-down screen top; the setup view flips y to draw it, inside a bezel.
public enum TourLayout {
    public static let size = CGSize(width: 760, height: 280)
    public static var bounds: CGRect { CGRect(origin: .zero, size: size) }
    public static let menuBarHeight: CGFloat = 24
    /// The hardware notch. While Tuck holds something, its closed surface adds a wing either side: the
    /// mark in the left one, the dot that becomes the Tuck button in the right.
    public static let notchSize = CGSize(width: 112, height: 24)
    /// As on the real surface, each wing is a square of the notch's height plus a little room.
    public static let wing: CGFloat = notchSize.height + 4
    /// The open fold, about seven tenths of the real one's width: room beside the notch for all three
    /// lenses' names.
    public static let panelWidth: CGFloat = 390
    /// Tuck's mark on the closed notch, at about three quarters of its real size.
    public static let notchMarkSize: CGFloat = 15
    /// The fold's rows at this size: one line beside a small icon, as the real rows are. The first sits
    /// just under the band, the line level with the notch.
    public static let rowHeight: CGFloat = 22
    public static let rowIconSize: CGFloat = 14
    public static let listTop: CGFloat = notchSize.height + 2
    /// From the fold's side to a row's icon: the list's inset and the row's own padding.
    public static let rowIconInset: CGFloat = 12

    public static var surface: CGRect {
        let width = notchSize.width + wing * 2
        return CGRect(x: size.width / 2 - width / 2, y: size.height - notchSize.height, width: width, height: notchSize.height)
    }

    public static var notch: CGRect {
        CGRect(x: size.width / 2 - notchSize.width / 2, y: size.height - notchSize.height,
               width: notchSize.width, height: notchSize.height)
    }

    /// The open fold, hanging from the top edge, for a given height.
    public static func panel(height: CGFloat) -> CGRect {
        CGRect(x: size.width / 2 - panelWidth / 2, y: size.height - height, width: panelWidth, height: height)
    }

    /// The Notes window, at rest on the desk, clear of the open fold so it can fly up over it.
    public static let window = CGRect(x: 14, y: 22, width: 170, height: 186)
    /// The PDF's icon, at rest on the desk.
    public static let file = CGPoint(x: 640, y: 88)

    /// The drop invitation's geometry, exactly as Tuck builds it for a real display.
    public static var zone: DropApproach.Zone {
        DropApproach.Zone(surface: surface, approach: DropApproach.approachZone(in: bounds), display: bounds)
    }

    /// The middle of the mark on the closed notch's left wing. A deposit lands in the mark's dip, which
    /// at this size is within a third of a point of its middle.
    public static var mark: CGPoint { CGPoint(x: surface.minX + wing / 2, y: surface.midY) }

    /// The mark's line at this size, an eighth of its side as `TuckLogo` draws small marks: a deposit on
    /// the closed notch arrives as a dot this thick.
    public static var markStroke: CGFloat { notchMarkSize / 8 }

    /// The icon of the open fold's row `row` from the top, where a tucked window lands as a dot (always
    /// the top row: it's the newest) and where it leaves from to come back.
    public static func rowIcon(_ row: Int) -> CGPoint {
        CGPoint(x: size.width / 2 - panelWidth / 2 + rowIconInset + rowIconSize / 2,
                y: size.height - listTop - rowHeight * (CGFloat(row) + 0.5))
    }

    /// Where a deposit lands: on a row's icon in the open fold, or in the closed notch's mark.
    public static func landing(open: Bool, row: Int = 0) -> CGPoint {
        open ? rowIcon(row) : mark
    }

    /// The Notes window's path into Tuck, from where it was, arriving the size of what it lands on: a
    /// row's icon, or the mark's line.
    public static func flight(open: Bool, row: Int = 0) -> DepositFlight {
        DepositFlight(window: window, target: landing(open: open, row: row), endSize: open ? rowIconSize : markStroke)
    }
}
