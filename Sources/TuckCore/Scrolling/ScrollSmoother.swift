import Foundation

/// How long a smoothed wheel scroll takes to settle.
public enum ScrollSmoothness: String, CaseIterable, Identifiable, Codable, Sendable {
    case snappy
    case balanced
    case gliding

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .snappy: return "Snappy"
        case .balanced: return "Balanced"
        case .gliding: return "Gliding"
        }
    }

    /// Time constant of the exponential ease: after one constant about 63% of the distance has been
    /// covered, after four about 98%.
    public var timeConstant: TimeInterval {
        switch self {
        case .snappy: return 0.05
        case .balanced: return 0.085
        case .gliding: return 0.13
        }
    }
}

/// Which kind of device produced a scroll event, judged from the event's own fields.
public enum ScrollInput: Equatable, Sendable {
    /// A notched mouse wheel: line-based, no gesture phases. Smoothed and optionally reversed.
    case wheel
    /// A high-resolution mouse wheel without gesture phases: already smooth, optionally reversed.
    case preciseWheel
    /// A trackpad or Magic Mouse gesture (or its momentum): left exactly as the system sent it.
    case gesture

    public static func classify(isContinuous: Bool, scrollPhase: Int64, momentumPhase: Int64) -> ScrollInput {
        if scrollPhase != 0 || momentumPhase != 0 { return .gesture }
        return isContinuous ? .preciseWheel : .wheel
    }
}

public struct ScrollFrame: Equatable, Sendable {
    /// Whole pixels to scroll this frame (positive is the direction the original event used).
    public let vertical: Int32
    public let horizontal: Int32
    public let finished: Bool
}

/// Turns notched wheel ticks into a short eased glide.
///
/// Each tick adds distance; every display frame moves a fraction of what is left, following an
/// exponential ease, so ticks that arrive mid-glide simply extend it. Fractions of a pixel are carried
/// between frames, so the total scrolled is exactly the total requested. Reversing direction drops what
/// was left on that axis, so the content never keeps sliding the wrong way.
public struct ScrollSmoother: Sendable {
    /// Added to every tick so a single slow notch moves a useful distance. The system's own
    /// acceleration (larger deltas when spinning fast) is kept on top of it.
    public static let notchLift: Double = 30
    /// Longest frame the ease will integrate; a stalled frame never turns into a jump.
    public static let maximumFrame: TimeInterval = 1.0 / 30
    /// Distance below which a glide is considered done.
    static let settleDistance: Double = 0.5

    public var timeConstant: TimeInterval
    public private(set) var remainingVertical: Double = 0
    public private(set) var remainingHorizontal: Double = 0
    private var carryVertical: Double = 0
    private var carryHorizontal: Double = 0

    public init(smoothness: ScrollSmoothness = .balanced) {
        timeConstant = smoothness.timeConstant
    }

    public var isIdle: Bool { remainingVertical == 0 && remainingHorizontal == 0 }

    /// Distance for one wheel event, from the system's pixel delta for it.
    public static func distance(forPointDelta delta: Double) -> Double {
        guard delta != 0 else { return 0 }
        return delta + (delta > 0 ? notchLift : -notchLift)
    }

    public mutating func add(vertical: Double, horizontal: Double) {
        remainingVertical = Self.accumulate(remainingVertical, vertical)
        remainingHorizontal = Self.accumulate(remainingHorizontal, horizontal)
        if vertical != 0 && (remainingVertical > 0) != (carryVertical > 0) { carryVertical = 0 }
        if horizontal != 0 && (remainingHorizontal > 0) != (carryHorizontal > 0) { carryHorizontal = 0 }
    }

    public mutating func advance(elapsed: TimeInterval) -> ScrollFrame {
        let dt = min(max(elapsed, 0), Self.maximumFrame)
        let fraction = 1 - exp(-dt / max(timeConstant, 0.001))
        let vertical = step(&remainingVertical, &carryVertical, fraction: fraction)
        let horizontal = step(&remainingHorizontal, &carryHorizontal, fraction: fraction)
        return ScrollFrame(vertical: vertical, horizontal: horizontal, finished: isIdle)
    }

    public mutating func reset() {
        remainingVertical = 0
        remainingHorizontal = 0
        carryVertical = 0
        carryHorizontal = 0
    }

    private static func accumulate(_ remaining: Double, _ delta: Double) -> Double {
        guard delta != 0 else { return remaining }
        if remaining != 0 && (remaining > 0) != (delta > 0) { return delta }
        return remaining + delta
    }

    private func step(_ remaining: inout Double, _ carry: inout Double, fraction: Double) -> Int32 {
        guard remaining != 0 else { return 0 }
        var move = remaining * fraction
        if abs(remaining - move) < Self.settleDistance { move = remaining }
        remaining -= move
        if remaining == 0 || abs(remaining) < 1e-9 { remaining = 0 }
        let total = move + carry
        let whole = total.rounded(.towardZero)
        carry = total - whole
        if remaining == 0 {
            // Flush what is left of the carry on the last frame so nothing is lost or invented.
            let flush = carry.rounded()
            carry = 0
            return Int32(clamping: Int(whole + flush))
        }
        return Int32(clamping: Int(whole))
    }
}
