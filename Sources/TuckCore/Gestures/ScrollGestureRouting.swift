import CoreGraphics
import Foundation

/// Who a two-finger trackpad gesture on the surface belongs to: the surface, as a swipe; the full fold's
/// list, which scrolls; or the shallow fold's strip, which scrolls sideways. A gesture that starts over a
/// list long enough to scroll scrolls that list for the rest of the gesture, and anywhere else but the
/// strip it is a swipe.
///
/// Over the strip the gesture's first events are held back until it has travelled `lockDistance` and
/// shown its axis, by the same rule the fold's swipes lock with: clearly more up or down than sideways
/// (`verticalBias`) makes it a swipe, which can deepen, fold or close the fold as anywhere else;
/// otherwise it belongs to the strip, which is handed the held events and scrolls, and it never moves
/// the fold. A gesture too short to show an axis is a swipe that went nowhere.
///
/// Ownership is decided once per gesture, as it starts or, over the strip, once its axis shows, and
/// never again mid-gesture. It was once re-decided at every event over a list that scrolls, which
/// restarted the swipe each time.
public struct ScrollGestureRouting: Sendable {
    public enum Owner: Hashable, Sendable { case surface, list, strip }

    /// Where a gesture starts.
    public enum Region: Hashable, Sendable {
        /// Anywhere a gesture is a swipe.
        case surface
        /// The fold's list while it has more than it shows.
        case scrollableList
        /// The shallow fold's strip while it holds more than it shows.
        case strip
    }

    /// What the surface does with one event.
    public enum Step: Hashable, Sendable {
        /// A swipe; `began` when the swipe starts with this event.
        case swipe(began: Bool)
        /// The event goes on to the list or the strip.
        case passOn
        /// Held back while a gesture over the strip shows which way it goes.
        case hold
        /// The gesture held back went up or down: the held events, then this one, are a swipe, begun by
        /// the first of them.
        case swipeHeld
        /// The gesture held back went sideways: the held events go on to the strip, then this one.
        case passOnHeld
    }

    public var lockDistance: CGFloat
    public var verticalBias: CGFloat
    public private(set) var owner: Owner = .surface
    /// A gesture has begun and not yet ended.
    public private(set) var isInGesture = false
    /// A gesture over the strip is being held back until its axis shows.
    public private(set) var isHolding = false
    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0

    /// The same lock distance and bias as `SwipeGestureTracker` in the open fold.
    public init(lockDistance: CGFloat = 8, verticalBias: CGFloat = 1.5) {
        self.lockDistance = lockDistance
        self.verticalBias = verticalBias
    }

    /// Routes one event of a gesture (not its momentum, which follows the owner). `starts` is the event's
    /// .began or .mayBegin phase; devices that omit those start a gesture at its first event after the
    /// last one ended.
    public mutating func route(starts: Bool, ends: Bool, region: Region, dx: CGFloat, dy: CGFloat) -> Step {
        let began = starts || !isInGesture
        isInGesture = !ends
        if began {
            travelX = 0
            travelY = 0
            isHolding = region == .strip
            owner = region == .scrollableList ? .list : .surface
        }
        guard isHolding else { return owner == .surface ? .swipe(began: began) : .passOn }
        travelX += dx
        travelY += dy
        if max(abs(travelX), abs(travelY)) >= lockDistance {
            isHolding = false
            guard abs(travelY) > abs(travelX) * verticalBias else {
                owner = .strip
                return .passOnHeld
            }
            return .swipeHeld
        }
        if ends {
            isHolding = false
            return .swipeHeld
        }
        return .hold
    }

    /// For a gesture over the surface or the full fold's list: whether the surface takes the event and,
    /// if so, whether the swipe starts with it.
    public mutating func route(starts: Bool, ends: Bool, overScrollableList: Bool,
                               dx: CGFloat, dy: CGFloat) -> (surface: Bool, began: Bool) {
        let step = route(starts: starts, ends: ends, region: overScrollableList ? .scrollableList : .surface, dx: dx, dy: dy)
        guard case .swipe(let began) = step else { return (false, false) }
        return (true, began)
    }
}
