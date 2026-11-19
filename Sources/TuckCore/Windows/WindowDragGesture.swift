import CoreGraphics
import Foundation

/// The modifier keys that turn a drag anywhere on a window into a move or resize.
public enum WindowDragModifiers: String, CaseIterable, Identifiable, Codable, Sendable {
    case controlOption
    case controlCommand
    case controlOptionCommand

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .controlOption: return "⌃ ⌥"
        case .controlCommand: return "⌃ ⌘"
        case .controlOptionCommand: return "⌃ ⌥ ⌘"
        }
    }

    /// The Quartz event flags this choice requires.
    public var flags: CGEventFlags {
        switch self {
        case .controlOption: return [.maskControl, .maskAlternate]
        case .controlCommand: return [.maskControl, .maskCommand]
        case .controlOptionCommand: return [.maskControl, .maskAlternate, .maskCommand]
        }
    }

    /// What a mouse-down with these flags should start, if anything. The chosen keys must be held
    /// exactly (Shift aside): left button moves, right button resizes, and adding Shift to a left-button
    /// drag resizes for trackpads where a right-drag is awkward.
    public func gesture(for flags: CGEventFlags, rightButton: Bool) -> WindowDragGesture.Kind? {
        let relevant: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        guard flags.intersection(relevant) == self.flags else { return nil }
        if rightButton { return .resize }
        return flags.contains(.maskShift) ? .resize : .move
    }
}

/// Maths for one modifier-drag. Works in Quartz global coordinates (origin top-left, y down), the space
/// both mouse events and the Accessibility API use, so no conversion happens per event.
public struct WindowDragGesture: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case move, resize }

    /// The corner a resize pulls: whichever quarter of the window the pointer started in.
    public enum Corner: Equatable, Sendable { case topLeft, topRight, bottomLeft, bottomRight }

    public static let minimumSize = CGSize(width: 180, height: 110)

    public let kind: Kind
    public let startPointer: CGPoint
    public let originalFrame: CGRect
    public let corner: Corner

    public init(kind: Kind, pointer: CGPoint, windowFrame: CGRect) {
        self.kind = kind
        self.startPointer = pointer
        self.originalFrame = windowFrame
        let right = pointer.x >= windowFrame.midX
        let bottom = pointer.y >= windowFrame.midY // y grows downwards
        switch (right, bottom) {
        case (false, false): corner = .topLeft
        case (true, false): corner = .topRight
        case (false, true): corner = .bottomLeft
        case (true, true): corner = .bottomRight
        }
    }

    /// The frame for the current pointer position. Moves keep the size; resizes keep the opposite corner
    /// fixed and never shrink below `minimumSize`.
    public func frame(for pointer: CGPoint) -> CGRect {
        let dx = (pointer.x - startPointer.x).rounded()
        let dy = (pointer.y - startPointer.y).rounded()
        switch kind {
        case .move:
            return originalFrame.offsetBy(dx: dx, dy: dy)
        case .resize:
            var minX = originalFrame.minX, maxX = originalFrame.maxX
            var minY = originalFrame.minY, maxY = originalFrame.maxY
            let minimum = Self.minimumSize
            switch corner {
            case .topLeft, .bottomLeft: minX = min(minX + dx, maxX - minimum.width)
            case .topRight, .bottomRight: maxX = max(maxX + dx, minX + minimum.width)
            }
            switch corner {
            case .topLeft, .topRight: minY = min(minY + dy, maxY - minimum.height)
            case .bottomLeft, .bottomRight: maxY = max(maxY + dy, minY + minimum.height)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
}

/// Caps how often frames are sent to another app while dragging. Every Accessibility write is a
/// cross-process call, so sending one per mouse event wastes work the app then has to coalesce.
/// The final frame is always sent on release regardless.
public struct FrameThrottle: Sendable {
    public let interval: TimeInterval
    private var last: TimeInterval?

    public init(framesPerSecond: Double = 60) {
        interval = 1 / framesPerSecond
    }

    public mutating func shouldSend(at time: TimeInterval) -> Bool {
        if let last, time - last < interval { return false }
        last = time
        return true
    }

    public mutating func reset() { last = nil }
}
