import Foundation

/// Mission Control (or App Exposé, or Show Desktop) as the parking service sees it: what was in front as
/// it began, and how long after it ends what it left behind is still taken as its doing. It shows every
/// window on the Space, parked ones too. As it ends it, or an app as it lets go, can leave a parked window
/// back in view, or the keyboard in one. Neither is the person bringing that window back. Only choosing
/// it there is: the front has moved onto it since Mission Control began. Leaving with the front where it
/// was (the window that was in front clicked, Esc, the key or swipe again) chooses nothing new, so every
/// parked window goes out of sight again.
public struct MissionControlVisit: Sendable {
    public typealias Landing = OwnFrontChanges.Landing

    /// How long after the exit its windows are first looked at, so its animation, and any app moving a
    /// window as it lets go, have settled.
    public static let settleDelay: TimeInterval = 0.4
    /// How long after a move or a focus change during the settling it is looked at, at the soonest.
    public static let beat: TimeInterval = 0.2
    /// How long after the exit a parked window back in view, or the keyboard landing on one, is still
    /// judged by what was in front as it began, rather than as anything else would be.
    public static let span: TimeInterval = 1.5

    /// Where the front was as it began: the app in front and its focused window. Nil when that isn't
    /// known, and then nothing counts as chosen.
    public private(set) var frontAtStart: Landing?
    public private(set) var isShowing = false
    /// When (system uptime) it last ended.
    public private(set) var endedAt: TimeInterval?
    /// Whether it was last taken to have ended without the Dock saying so.
    private var endAssumed = false
    /// Windows that have already failed once to be parked again during this visit.
    private var retried: Set<UUID> = []
    /// When (system uptime) a window that failed is tried again, at the soonest.
    private var retryAt: TimeInterval?

    public init() {}

    /// It began, with this in front. Moving between its views (Mission Control to App Exposé, say) keeps
    /// where it began.
    public mutating func began(front: Landing?) {
        guard !isShowing else { return }
        frontAtStart = front
        isShowing = true
        endedAt = nil
        endAssumed = false
        retried = []
        retryAt = nil
    }

    /// It ended: as the Dock says, or as Tuck takes it to have (`assumed`), when something only its end
    /// explains happens and the Dock hasn't said so (it may not, for a swipe). The Dock saying so later is
    /// still this visit's end, however long after. An end with no start seen (Tuck began watching while it
    /// showed, say) leaves what was in front unknown.
    public mutating func ended(at now: TimeInterval, assumed: Bool = false) {
        if !isShowing && !endAssumed && !isUnderway(at: now) {
            frontAtStart = nil
            retried = []
            retryAt = nil
        }
        endAssumed = assumed
        isShowing = false
        endedAt = now
    }

    /// Whether it is showing, or ended so lately that what it left is still its doing, or a window it
    /// left is still to be tried again.
    public func isUnderway(at now: TimeInterval) -> Bool {
        isShowing || endedAt.map { now - $0 < Self.span } == true || retryAt.map { now <= $0 } == true
    }

    /// How long from now until what it left is looked at: `settleDelay` after the exit, at least a `beat`
    /// after the latest move or focus change, and not before a window that failed is due another try.
    public func wait(at now: TimeInterval) -> TimeInterval {
        max(Self.beat, (endedAt ?? now) + Self.settleDelay - now, (retryAt ?? now) - now)
    }

    /// Whether the person chose this parked window there: it is now the focused window of the app in
    /// front, and wasn't as Mission Control began. With the front where it was, they chose nothing new,
    /// even if that left the keyboard in a parked window (one it couldn't be handed on from as it went).
    public func choseWindow(_ window: Landing, front: Landing?) -> Bool {
        guard let frontAtStart, let front else { return false }
        return front == window && frontAtStart != window
    }

    /// A window it left in view couldn't be parked again, or couldn't be asked. The first time in a visit
    /// it is tried once more, `settleDelay` later, rather than falling back at once: the exit may still
    /// hold it, its frame may not yet read true, or its app may be busy redrawing.
    public mutating func mayRetry(_ window: UUID, at now: TimeInterval) -> Bool {
        guard retried.insert(window).inserted else { return false }
        retryAt = max(retryAt ?? now, now + Self.settleDelay)
        return true
    }
}
