import CoreGraphics
import Foundation

/// A window frame in global screen coordinates (AppKit convention, origin bottom-left).
public struct WindowFrame: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// The application that owns a parked window.
public struct AppIdentity: Hashable, Codable, Sendable {
    public var bundleID: String
    public var name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Whether two identities are the same app: by bundle identifier, or by name for apps without one.
    public func isSameApp(as other: AppIdentity) -> Bool {
        bundleID.isEmpty ? name == other.name : bundleID == other.bundleID
    }
}

/// How a tucked window was put away. Tuck parks windows off screen, so nothing but its own card is seen
/// moving; a window that can't be parked that way is minimised to the Dock. Hidden with its app is how
/// earlier versions put some windows away, and such rows still restore.
public enum ParkingMethod: String, Hashable, Codable, Sendable {
    case minimised
    case hiddenWithApp
    /// Moved just beyond a corner of a display (see `OffScreenParking`): still open, not minimised.
    case offScreen
}

/// A window Tuck has hidden and remembers how to restore.
public struct ParkedWindow: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var app: AppIdentity
    public var title: String
    public var originalFrame: WindowFrame
    /// Identifier of the display the window was on, when known.
    public var displayID: String?
    /// Human-readable display name, used only for hover metadata.
    public var displayName: String?
    public var tuckedAt: Date
    /// True when a frozen thumbnail was captured at tuck time (needs Screen Recording; optional).
    public var hasFrozenPreview: Bool
    /// How it was put away; nil (libraries saved before hiding existed) means minimised.
    public var method: ParkingMethod?

    public var isHiddenWithApp: Bool { method == .hiddenWithApp }
    public var isOffScreen: Bool { method == .offScreen }

    public init(
        id: UUID = UUID(),
        app: AppIdentity,
        title: String,
        originalFrame: WindowFrame,
        displayID: String? = nil,
        displayName: String? = nil,
        tuckedAt: Date = Date(),
        hasFrozenPreview: Bool = false,
        method: ParkingMethod? = nil
    ) {
        self.id = id
        self.app = app
        self.title = title
        self.originalFrame = originalFrame
        self.displayID = displayID
        self.displayName = displayName
        self.tuckedAt = tuckedAt
        self.hasFrozenPreview = hasFrozenPreview
        self.method = method
    }

    /// Whether two rows are windows of the same app.
    public func sharesApp(with other: ParkedWindow) -> Bool { app.isSameApp(as: other.app) }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled window" : trimmed
    }
}
