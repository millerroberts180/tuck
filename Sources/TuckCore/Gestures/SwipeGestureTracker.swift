import CoreGraphics
import Foundation

/// Turns two-finger trackpad scroll deltas on the Tuck surface into at most one deliberate action per
/// gesture. Vertical swipes step the surface through its depths, the fold following the fingers:
/// swiping down brings a tucked surface back, opens the collapsed one into the shallow fold, and deepens
/// that into the full fold; swiping up goes back the same way, one depth per swipe, and tucks the
/// collapsed surface away into the notch. Sideways movement does nothing: there are no pages or
/// sessions to move between, so a gesture locks to the vertical only when it is clearly vertical, and a
/// sideways brush never opens or closes anything. An action fires once, when the travel crosses a
/// threshold, which is also the only moment a haptic tick may play; until then `pull` tells the surface
/// how far the gesture has gone so it can follow the fingers.
public final class SwipeGestureTracker {
    public enum Stage: Hashable, Sendable {
        /// Swiped away: nothing but the hardware notch (or an invisible spot on displays without one).
        case tucked
        case collapsed
        /// The shallow fold: the first rows of everything, with the lenses beside the notch.
        case expanded
        /// The full fold: the whole stream, with search and Arrange windows.
        case full
    }

    public enum Action: Hashable, Sendable {
        case reveal
        case tuckAway
        case expand
        case collapse
        /// From the shallow fold to the full one.
        case unfold
        /// From the full fold back to the shallow one.
        case fold
    }

    public enum Axis: Hashable, Sendable { case vertical, horizontal }

    /// Travel needed to step out of the tucked or collapsed stage.
    public var verticalThreshold: CGFloat
    /// Travel needed to close or fold an open panel; shorter, because folding should take only a flick.
    public var closeThreshold: CGFloat
    /// Travel after which the gesture is locked to the axis it moved along most.
    public var lockDistance: CGFloat
    public private(set) var travelDown: CGFloat = 0
    public private(set) var travelRight: CGFloat = 0
    public private(set) var hasCommitted = false
    /// The axis the gesture is locked to, once it has travelled `lockDistance`.
    public private(set) var axis: Axis?

    public init(verticalThreshold: CGFloat = 24, closeThreshold: CGFloat = 14, lockDistance: CGFloat = 8) {
        self.verticalThreshold = verticalThreshold
        self.closeThreshold = closeThreshold
        self.lockDistance = lockDistance
    }

    /// The vertical action available from a stage in one direction, if any.
    public static func verticalAction(from stage: Stage, down: Bool) -> Action? {
        switch (stage, down) {
        case (.tucked, true): .reveal
        case (.collapsed, true): .expand
        case (.collapsed, false): .tuckAway
        case (.expanded, true): .unfold
        case (.expanded, false): .collapse
        case (.full, false): .fold
        case (.tucked, false), (.full, true): nil
        }
    }

    /// - Parameters:
    ///   - down: physical finger travel downwards for this event (already corrected for natural scrolling).
    ///   - right: physical finger travel to the right for this event.
    ///   - began/ended: gesture phase boundaries; state resets at both.
    ///   - stage: what the surface is showing when the event arrives.
    public func process(down: CGFloat, right: CGFloat, began: Bool, ended: Bool, stage: Stage) -> Action? {
        if began { reset() }
        defer { if ended { reset() } }
        guard !hasCommitted else { return nil }

        travelDown += down
        travelRight += right
        if axis == nil, max(abs(travelDown), abs(travelRight)) >= lockDistance {
            // In the open panel folding must be meant: the swipe has to be clearly more vertical than
            // sideways.
            let bias: CGFloat = isOpen(stage) ? 1.5 : 1
            axis = abs(travelDown) > abs(travelRight) * bias ? .vertical : .horizontal
        }

        guard axis == .vertical, let action = Self.verticalAction(from: stage, down: travelDown > 0),
              abs(travelDown) >= threshold(for: stage, down: travelDown > 0) else { return nil }
        hasCommitted = true
        return action
    }

    /// How far the gesture in progress has pulled towards its vertical action: 0 at rest, up to 1 when
    /// pulling down and down to -1 when pulling up, reaching ±1 at the moment the action fires. Zero when
    /// the gesture is sideways, already committed, or heading somewhere this stage cannot go.
    public func pull(stage: Stage) -> CGFloat {
        guard !hasCommitted, travelDown != 0, axis != .horizontal, abs(travelDown) >= abs(travelRight),
              Self.verticalAction(from: stage, down: travelDown > 0) != nil else { return 0 }
        return max(-1, min(1, travelDown / threshold(for: stage, down: travelDown > 0)))
    }

    public func reset() {
        travelDown = 0
        travelRight = 0
        hasCommitted = false
        axis = nil
    }

    /// Folding back is a flick; opening and deepening take a deliberate pull.
    private func threshold(for stage: Stage, down: Bool) -> CGFloat {
        isOpen(stage) && !down ? closeThreshold : verticalThreshold
    }

    private func isOpen(_ stage: Stage) -> Bool { stage == .expanded || stage == .full }
}
