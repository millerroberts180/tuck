import CoreGraphics
import Foundation

/// The path a tucked window's stand-in takes into Tuck: from where the window was, up into the mark in
/// the notch or bubble, shrinking as it goes. Coordinates are AppKit
/// global (y grows upwards).
public struct DepositFlight: Equatable, Sendable {
    public static let duration: TimeInterval = 0.24
    /// The stand-in never starts bigger than this, so a full-screen window doesn't fill the screen.
    public static let maximumCard = CGSize(width: 240, height: 150)
    /// The stand-in's size on arrival when there is no dot to land on.
    public static let defaultEndSize: CGFloat = 10

    public let window: CGRect
    public let target: CGPoint
    /// The stand-in's diameter on arrival: the dot it lands on, so it arrives the same size as that dot.
    public let endSize: CGFloat

    public init(window: CGRect, target: CGPoint, endSize: CGFloat = defaultEndSize) {
        self.window = window
        self.target = target
        self.endSize = endSize
    }

    /// The stand-in at the start: the window's proportions, at most `maximumCard`, centred on the window.
    public var startCard: CGRect {
        let scale = min(1, Self.maximumCard.width / max(window.width, 1), Self.maximumCard.height / max(window.height, 1))
        let size = CGSize(width: window.width * scale, height: window.height * scale)
        return CGRect(x: window.midX - size.width / 2, y: window.midY - size.height / 2, width: size.width, height: size.height)
    }

    public var endCard: CGRect {
        CGRect(x: target.x - endSize / 2, y: target.y - endSize / 2, width: endSize, height: endSize)
    }

    /// How far the stand-in climbs, from the window's middle to the target.
    private var rise: CGFloat { max(target.y - startCard.midY, 0) }

    /// The curve's first control point, straight above the window: the stand-in rises from it first.
    public var control1: CGPoint {
        CGPoint(x: startCard.midX, y: startCard.midY + rise * 0.5)
    }

    /// The curve's second control point, straight below the target: after gliding across beneath the
    /// menu bar, the stand-in goes straight up into the target, never sideways along the top of the
    /// screen, over the menu bar or across the camera housing.
    public var control2: CGPoint {
        CGPoint(x: target.x, y: target.y - rise * 0.3)
    }

    /// A point along the cubic curve, `t` from 0 to 1.
    public func point(at t: CGFloat) -> CGPoint {
        let start = CGPoint(x: startCard.midX, y: startCard.midY)
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * target.x,
                       y: a * start.y + b * control1.y + c * control2.y + d * target.y)
    }
}
