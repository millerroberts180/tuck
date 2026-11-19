import CoreGraphics
import Foundation

/// Decides, from pointer positions alone, when a supported drag is invited to drop into Tuck, how
/// strongly, and when an approaching drag has settled near it.
///
/// The invitation appears as soon as the drag enters a generous range around the top-centre surface,
/// well before the pointer reaches the notch, and strengthens as it nears; over the surface (as it
/// pops out to take the drop) it shows the accepted state. Leaving the range needs the pointer to pass
/// a retreat margin beyond it, so the boundary never flickers. Settling is separate and more
/// deliberate: the pointer must rest in the smaller approach zone for a short dwell. It opens nothing;
/// a fold that is already open stays open for the drop.
public enum DropApproach {
    /// Invitation levels; the surface redraws only when the level changes. `levels` is the accepted
    /// state: the pointer is over the drop target.
    public static let levels = 8
    /// How far the invitation range reaches beyond the collapsed surface: to each side, and downwards.
    public static let rangeReach = CGSize(width: 260, height: 220)
    /// How far the drop target extends beyond the collapsed surface, matching how far it pops out.
    public static let targetSlack = CGSize(width: 12, height: 30)
    /// How far past a zone the pointer must go to leave it once inside.
    public static let retreatMargin: CGFloat = 36
    /// How long the pointer must rest in the approach zone to have settled there.
    public static let dwell: TimeInterval = 0.18
    /// The approach zone's size, at the top centre of a display.
    public static let approachSize = CGSize(width: 460, height: 120)

    /// Where a drag settles: the top centre of the display.
    public static func approachZone(in display: CGRect) -> CGRect {
        CGRect(x: display.midX - approachSize.width / 2, y: display.maxY - approachSize.height,
               width: approachSize.width, height: approachSize.height)
    }

    /// Geometry for one display, in AppKit global coordinates (y grows upwards).
    public struct Zone: Equatable, Sendable {
        /// The collapsed surface at rest.
        public var surface: CGRect
        /// Resting here for `dwell` is settling near Tuck.
        public var approach: CGRect
        public var display: CGRect

        public init(surface: CGRect, approach: CGRect, display: CGRect) {
            self.surface = surface
            self.approach = approach
            self.display = display
        }

        /// Where a supported drag is invited: around the surface, from the top of the display down.
        public var range: CGRect {
            grown(by: DropApproach.rangeReach).intersection(display)
        }

        /// The surface as it pops out to take a drop.
        public var target: CGRect {
            grown(by: DropApproach.targetSlack).intersection(display)
        }

        public var retreat: CGRect {
            approach.insetBy(dx: -DropApproach.retreatMargin, dy: -DropApproach.retreatMargin)
        }

        var rangeRetreat: CGRect {
            range.insetBy(dx: -DropApproach.retreatMargin, dy: -DropApproach.retreatMargin)
        }

        /// The surface widened to both sides and lengthened downwards, still reaching the display top.
        private func grown(by reach: CGSize) -> CGRect {
            CGRect(x: surface.minX - reach.width, y: surface.minY - reach.height,
                   width: surface.width + reach.width * 2, height: display.maxY - (surface.minY - reach.height))
        }
    }

    /// The invitation for a pointer: nil when there is none, otherwise 0 (just inside the range) up to
    /// `levels` (over the drop target). `wasInviting` applies the retreat margin once the invitation shows.
    public static func invitation(pointer: CGPoint, zone: Zone, wasInviting: Bool) -> Int? {
        if zone.target.contains(pointer) { return levels }
        guard (wasInviting ? zone.rangeRetreat : zone.range).contains(pointer) else { return nil }
        let target = zone.target
        let dx = max(target.minX - pointer.x, 0, pointer.x - target.maxX)
        let dy = max(target.minY - pointer.y, 0, pointer.y - target.maxY)
        let reach = max(rangeReach.width, rangeReach.height)
        let closeness = 1 - min((dx * dx + dy * dy).squareRoot() / reach, 1)
        // Ease in so the growth concentrates near the target; just short of it stays below `levels`.
        return min(Int((closeness * closeness * CGFloat(levels - 1)).rounded()), levels - 1)
    }

    /// Whether the pointer counts as inside the approach zone, given whether it already was.
    public static func isArmed(pointer: CGPoint, zone: Zone, wasArmed: Bool) -> Bool {
        (wasArmed ? zone.retreat : zone.approach).contains(pointer)
    }
}

/// Decides whether a mouse drag carries something Tuck can take, from the drag pasteboard's change
/// count and its advertised types alone. Contents are never read before a drop.
///
/// Source apps write the drag pasteboard only once their drag actually begins, a few events after the
/// mouse starts moving, so a drag stays pending until the pasteboard changes. A drag that has not
/// written it within a short window is a window move, a selection or similar, and is left alone.
public enum DragClassification {
    public enum Kind: Hashable, Sendable {
        case pending
        case content
        case other
    }

    public static let decisionWindow: TimeInterval = 0.8

    public static func classify(changeCountAtMouseDown: Int, changeCount: Int, advertisesSupportedType: Bool,
                                elapsed: TimeInterval) -> Kind {
        if changeCount != changeCountAtMouseDown { return advertisesSupportedType ? .content : .other }
        return elapsed < decisionWindow ? .pending : .other
    }
}
