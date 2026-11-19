import Foundation

/// Which displays show Tuck's surface.
public enum SurfaceDisplays: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case builtIn
    case external

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "All"
        case .builtIn: return "Built-in"
        case .external: return "External"
        }
    }

    /// The displays to use, in the order given. When none matches (the lid is closed, or nothing is
    /// plugged in), the first display, the one with the menu bar, is used, so Tuck never disappears.
    public func select<Display>(from displays: [Display], isBuiltIn: (Display) -> Bool) -> [Display] {
        let chosen: [Display]
        switch self {
        case .all: chosen = displays
        case .builtIn: chosen = displays.filter(isBuiltIn)
        case .external: chosen = displays.filter { !isBuiltIn($0) }
        }
        return chosen.isEmpty ? Array(displays.prefix(1)) : chosen
    }
}

/// How Tuck looks on a display without a hardware notch.
public enum NotchlessStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    /// A small bubble floating in the menu-bar strip.
    case bubble
    /// A drawn notch hanging from the top edge, like a notched Mac's.
    case notch

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bubble: return "Bubble"
        case .notch: return "Notch"
        }
    }
}
