import Foundation

/// A spring described the way it is tuned by eye, converted to the mass–stiffness–damping form Core
/// Animation runs (mass 1).
public struct SpringParameters: Equatable, Sendable {
    public let stiffness: Double
    public let damping: Double

    /// - Parameters:
    ///   - duration: perceptual duration; roughly how long the motion takes to settle.
    ///   - bounce: 0 settles without overshooting, towards 1 is springier, below 0 is overdamped.
    public init(duration: Double, bounce: Double) {
        let omega = 2 * Double.pi / duration
        stiffness = omega * omega
        damping = bounce >= 0 ? 2 * omega * (1 - bounce) : 2 * omega / (1 + bounce)
    }

    /// - Parameters:
    ///   - response: period of the undamped spring.
    ///   - dampingFraction: 1 settles as fast as possible without overshooting.
    public init(response: Double, dampingFraction: Double) {
        let omega = 2 * Double.pi / response
        stiffness = omega * omega
        damping = 2 * omega * dampingFraction
    }

    public var dampingRatio: Double { damping / (2 * stiffness.squareRoot()) }

    /// How far past its target a step overshoots, as a fraction of the distance travelled.
    public var overshoot: Double {
        let zeta = dampingRatio
        guard zeta < 1 else { return 0 }
        return exp(-zeta * Double.pi / (1 - zeta * zeta).squareRoot())
    }
}

/// The surface's motion. Opening is one lively spring for the whole shape, overshooting a little and
/// settling, the way notch apps on macOS feel; closing and smaller changes settle without overshoot.
public enum SurfaceMotion {
    /// The surface opening into the panel.
    public static let open = SpringParameters(duration: 0.45, bounce: 0.4)
    /// The panel folding back into the notch.
    public static let close = SpringParameters(response: 0.4, dampingFraction: 1)
    /// A pressed surface letting go without opening.
    public static let release = SpringParameters(duration: 0.6, bounce: 0.35)
    /// Hover, press, tucking away, the panel resizing to new content.
    public static let settle = SpringParameters(response: 0.3, dampingFraction: 1)
    /// The drop invitation popping out.
    public static let pop = SpringParameters(duration: 0.35, bounce: 0.25)
}
