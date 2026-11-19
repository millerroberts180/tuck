import CoreGraphics
import Foundation

/// Where a window should go. A normal click restores `.original`; Command-click opens the chooser with
/// the four primary placements plus a compact row of finer layouts.
public enum Placement: String, CaseIterable, Identifiable, Codable, Sendable {
    case original
    case leftHalf
    case rightHalf
    case fullScreen
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
    case nextDisplay

    public var id: String { rawValue }

    /// The labelled row of the chooser.
    public static let primary: [Placement] = [.original, .leftHalf, .rightHalf, .fullScreen]
    /// The compact, icon-only row underneath.
    public static let secondary: [Placement] = Placement.allCases.filter { !primary.contains($0) }

    public var title: String {
        switch self {
        case .original: return "Original"
        case .leftHalf: return "Left half"
        case .rightHalf: return "Right half"
        case .fullScreen: return "Full screen"
        case .leftThird: return "Left third"
        case .centerThird: return "Centre third"
        case .rightThird: return "Right third"
        case .leftTwoThirds: return "Left two thirds"
        case .rightTwoThirds: return "Right two thirds"
        case .topLeft: return "Top left quarter"
        case .topRight: return "Top right quarter"
        case .bottomLeft: return "Bottom left quarter"
        case .bottomRight: return "Bottom right quarter"
        case .center: return "Centre"
        case .nextDisplay: return "Next display"
        }
    }

    /// Phrase used in confirmations ("restored to …", "placed on …").
    public var restoreDescription: String {
        switch self {
        case .original: return "where it was"
        case .fullScreen: return "full screen"
        case .center: return "the centre"
        case .nextDisplay: return "the next display"
        default: return title.lowercased()
        }
    }

    /// Edges a size-constrained window should stay pinned to when it cannot take the exact frame.
    public var anchorEdges: PlacementAnchor {
        switch self {
        case .leftHalf, .leftThird, .leftTwoThirds: return [.left]
        case .rightHalf, .rightThird, .rightTwoThirds: return [.right]
        case .topLeft: return [.left, .top]
        case .topRight: return [.right, .top]
        case .bottomLeft: return [.left, .bottom]
        case .bottomRight: return [.right, .bottom]
        case .original, .fullScreen, .centerThird, .center, .nextDisplay: return []
        }
    }

    /// Placements whose target spans the full usable height.
    var fillsHeight: Bool {
        switch self {
        case .leftHalf, .rightHalf, .fullScreen, .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds:
            return true
        default:
            return false
        }
    }
}

/// Edges a placement is attached to. Empty means "centred in the target".
public struct PlacementAnchor: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = PlacementAnchor(rawValue: 1 << 0)
    public static let right = PlacementAnchor(rawValue: 1 << 1)
    public static let top = PlacementAnchor(rawValue: 1 << 2)
    public static let bottom = PlacementAnchor(rawValue: 1 << 3)
}

/// The intent produced by committing the chooser.
public struct PlacementRequest: Hashable, Sendable {
    public let windowID: UUID
    public let placement: Placement

    public init(windowID: UUID, placement: Placement) {
        self.windowID = windowID
        self.placement = placement
    }
}

/// State for the compact inline chooser attached to one window row at a time.
public struct PlacementChooserState: Hashable, Sendable {
    public private(set) var openWindowID: UUID?
    public private(set) var highlighted: Placement = .original

    public init() {}

    public var isOpen: Bool { openWindowID != nil }

    public func isOpen(for windowID: UUID) -> Bool { openWindowID == windowID }

    /// Opens the chooser for a window, replacing any chooser open on another row.
    public mutating func open(for windowID: UUID) {
        openWindowID = windowID
        highlighted = .original
    }

    /// Command-clicking the same row again closes it; another row moves the chooser there.
    public mutating func toggle(for windowID: UUID) {
        if openWindowID == windowID {
            dismiss()
        } else {
            open(for: windowID)
        }
    }

    public mutating func highlight(_ placement: Placement) {
        guard isOpen else { return }
        highlighted = placement
    }

    /// Moves the highlight for keyboard use through the labelled row, then the compact row, stopping at
    /// either end.
    public mutating func moveHighlight(by offset: Int) {
        guard isOpen else { return }
        let all = Placement.allCases
        let current = all.firstIndex(of: highlighted) ?? 0
        highlighted = all[min(max(current + offset, 0), all.count - 1)]
    }

    /// Returns the chosen placement (or the highlighted one) and closes the chooser.
    public mutating func commit(_ placement: Placement? = nil) -> PlacementRequest? {
        guard let windowID = openWindowID else { return nil }
        let request = PlacementRequest(windowID: windowID, placement: placement ?? highlighted)
        dismiss()
        return request
    }

    public mutating func dismiss() {
        openWindowID = nil
        highlighted = .original
    }
}

/// Converts a placement into a concrete frame inside a display's usable area (menu bar and Dock
/// excluded). Frames use AppKit global coordinates (origin bottom-left, y up). Splits are rounded down
/// to whole points and the remainder goes to the last column, so neighbouring windows tile exactly.
public enum PlacementGeometry {
    public static func frame(
        for placement: Placement,
        originalFrame: CGRect,
        visibleFrame: CGRect,
        originalDisplayAvailable: Bool = true,
        destinationVisibleFrame: CGRect? = nil
    ) -> CGRect {
        let area = visibleFrame.integral
        switch placement {
        case .original:
            if originalDisplayAvailable { return originalFrame }
            return centered(size: originalFrame.size, in: area)
        case .leftHalf: return columns(area, count: 2, from: 0, span: 1)
        case .rightHalf: return columns(area, count: 2, from: 1, span: 1)
        case .fullScreen: return area
        case .leftThird: return columns(area, count: 3, from: 0, span: 1)
        case .centerThird: return columns(area, count: 3, from: 1, span: 1)
        case .rightThird: return columns(area, count: 3, from: 2, span: 1)
        case .leftTwoThirds: return columns(area, count: 3, from: 0, span: 2)
        case .rightTwoThirds: return columns(area, count: 3, from: 1, span: 2)
        case .topLeft: return quarter(area, right: false, top: true)
        case .topRight: return quarter(area, right: true, top: true)
        case .bottomLeft: return quarter(area, right: false, top: false)
        case .bottomRight: return quarter(area, right: true, top: false)
        case .center: return centered(size: originalFrame.size, in: area)
        case .nextDisplay:
            guard let destination = destinationVisibleFrame else { return originalFrame }
            return translate(originalFrame, from: area, to: destination.integral)
        }
    }

    /// Column `from` (spanning `span` columns) of `count` equal columns. Columns are floor(width/count)
    /// wide; the last one absorbs the leftover points so the right edge is always flush.
    static func columns(_ area: CGRect, count: Int, from index: Int, span: Int) -> CGRect {
        let unit = (area.width / CGFloat(count)).rounded(.down)
        let minX = area.minX + unit * CGFloat(index)
        let isLast = index + span == count
        let width = isLast ? area.maxX - minX : unit * CGFloat(span)
        return CGRect(x: minX, y: area.minY, width: width, height: area.height)
    }

    static func quarter(_ area: CGRect, right: Bool, top: Bool) -> CGRect {
        let halfWidth = (area.width / 2).rounded(.down)
        let halfHeight = (area.height / 2).rounded(.down)
        let x = right ? area.minX + halfWidth : area.minX
        let width = right ? area.maxX - x : halfWidth
        // AppKit y grows upwards, so the top row starts halfway up.
        let y = top ? area.minY + halfHeight : area.minY
        let height = top ? area.maxY - y : halfHeight
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Centres a window of the given size on the display, shrinking it to fit if needed.
    public static func centered(size: CGSize, in area: CGRect) -> CGRect {
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        return CGRect(
            x: (area.midX - width / 2).rounded(.down),
            y: (area.midY - height / 2).rounded(.down),
            width: width,
            height: height
        )
    }

    /// Moves a frame to another display, keeping its relative position and size, shrunk to fit.
    public static func translate(_ frame: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return centered(size: frame.size, in: destination) }
        let width = min(frame.width, destination.width)
        let height = min(frame.height, destination.height)
        let relativeX = (frame.minX - source.minX) / max(source.width - frame.width, 1)
        let relativeY = (frame.minY - source.minY) / max(source.height - frame.height, 1)
        let x = destination.minX + (destination.width - width) * min(max(relativeX, 0), 1)
        let y = destination.minY + (destination.height - height) * min(max(relativeY, 0), 1)
        return CGRect(x: x.rounded(.down), y: y.rounded(.down), width: width, height: height)
    }

    /// The display after `current` in `displays`, wrapping round. Nil when there is only one display.
    public static func nextDisplay<ID: Equatable>(after current: ID, in displays: [ID]) -> ID? {
        guard displays.count > 1, let index = displays.firstIndex(of: current) else { return nil }
        return displays[(index + 1) % displays.count]
    }

    // MARK: Verification

    public enum Fit: Equatable, Sendable {
        /// The window took the target frame (within tolerance).
        case exact
        /// The window kept a different size (minimum/maximum size or fixed aspect); re-anchor it.
        case constrained
        /// The window is badly off target: the app ignored or rejected the move.
        case rejected
    }

    /// Compares the frame an app actually applied with the requested one.
    public static func fit(actual: CGRect, target: CGRect, tolerance: CGFloat = 2) -> Fit {
        let sizeMatches = abs(actual.width - target.width) <= tolerance && abs(actual.height - target.height) <= tolerance
        let originMatches = abs(actual.minX - target.minX) <= tolerance && abs(actual.maxY - target.maxY) <= tolerance
        if sizeMatches && originMatches { return .exact }
        // Some apps refuse a size but still honour the position, or overshoot it; that is fixable.
        let overlap = actual.intersection(target)
        let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
        let targetArea = max(target.width * target.height, 1)
        return overlapArea / targetArea >= 0.25 || !sizeMatches ? .constrained : .rejected
    }

    /// Where a window that kept `actualSize` should sit so it still reads as the chosen placement: pinned
    /// to the placement's edges, otherwise centred in the target, and always inside the usable area.
    public static func anchored(actualSize: CGSize, target: CGRect, placement: Placement, visibleFrame: CGRect) -> CGRect {
        let edges = placement.anchorEdges
        var x = target.midX - actualSize.width / 2
        var y = target.midY - actualSize.height / 2
        if edges.contains(.left) { x = target.minX }
        if edges.contains(.right) { x = target.maxX - actualSize.width }
        if edges.contains(.top) || (placement.fillsHeight && !edges.contains(.bottom)) {
            // Full-height placements hang a shorter window from the top rather than float it.
            y = target.maxY - actualSize.height
        }
        if edges.contains(.bottom) { y = target.minY }
        let area = visibleFrame
        x = min(max(x, area.minX), max(area.maxX - actualSize.width, area.minX))
        y = min(max(y, area.minY), max(area.maxY - actualSize.height, area.minY))
        return CGRect(x: x.rounded(.down), y: y.rounded(.down), width: actualSize.width, height: actualSize.height)
    }

    // MARK: Coordinate spaces

    /// Converts between AppKit global coordinates (origin bottom-left of the primary display, y up) and
    /// the Accessibility/Quartz convention (origin top-left of the primary display, y down). The mapping
    /// is its own inverse.
    public static func flipped(_ rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func flipped(_ point: CGPoint, primaryDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
    }
}

/// Remembers the frame a window had before Tuck placed it, so "Original" can put it back. Bounded and
/// newest first; entries are keyed by an opaque window key chosen by the caller.
public struct PlacementHistory: Sendable {
    public static let capacity = 24
    private var entries: [(key: String, frame: CGRect)] = []

    public init() {}

    public mutating func remember(_ frame: CGRect, for key: String) {
        // Keep the earliest frame while a window is moved repeatedly, so Original means "before Tuck".
        if entries.contains(where: { $0.key == key }) { return }
        entries.insert((key, frame), at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
    }

    public func frame(for key: String) -> CGRect? {
        entries.first { $0.key == key }?.frame
    }

    @discardableResult
    public mutating func take(for key: String) -> CGRect? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        return entries.remove(at: index).frame
    }

    public var count: Int { entries.count }
}
