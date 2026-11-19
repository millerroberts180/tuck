import CoreGraphics
import Foundation

// MARK: - Window parking

/// What happened to a window.
public enum WindowActionResult: Hashable, Sendable {
    /// The window took the requested frame.
    case moved
    /// The window moved but kept a size of its own (minimum/maximum size); it was re-anchored.
    case constrained
    /// Nothing moved (the stand-in service used in tests); the frame is what a real move would use.
    case simulated
    /// The window has closed or its app has quit.
    case windowGone
    /// Accessibility permission is needed before Tuck can move windows.
    case needsPermission
    /// The app refused the change.
    case failed
    /// Nothing to do: no earlier frame to return to, or no other display.
    case unchanged
}

extension WindowActionResult {
    /// Whether a restore attempt with this result may drop the parked-window row. Only a confirmed
    /// restore or a window confirmed gone does; a failure, a missing permission or a no-op keeps the
    /// row so the window is never silently lost.
    public var removesParkedRow: Bool {
        switch self {
        case .moved, .constrained, .simulated, .windowGone: true
        case .failed, .needsPermission, .unchanged: false
        }
    }
}

/// What the system says about a window element Tuck is holding.
public enum WindowElementState: Hashable, Sendable {
    case alive
    /// The window no longer exists.
    case destroyed
    /// The app did not answer in time, or the query failed for another reason.
    case unresponsive
}

/// What looking for a parked window's live counterpart found.
public enum WindowLookup: Hashable, Sendable {
    case found
    /// Confirmed gone: its app has quit, or the system reports the window no longer exists.
    case gone
    /// Neither confirmed nor found: the app is busy, or no tucked window matches its title.
    case unavailable

    /// - Parameters:
    ///   - appRunning: whether the window's app is still running; nil when that cannot be told.
    ///   - cached: the state of the element held since parking, if Tuck still holds one.
    ///   - titleMatchFound: whether a tucked window of the app (minimised, or hidden with it) with the same
    ///     title was found.
    public static func classify(appRunning: Bool?, cached: WindowElementState?, titleMatchFound: Bool) -> WindowLookup {
        if cached == .alive { return .found }
        // A quit app cannot answer at all, so its windows read as unresponsive; quitting decides first.
        if appRunning == false { return .gone }
        switch cached {
        case .destroyed: return .gone
        case .unresponsive: return .unavailable
        case .alive, nil: break
        }
        return titleMatchFound ? .found : .unavailable
    }
}

public struct WindowActionOutcome: Hashable, Sendable {
    public let placement: Placement
    /// The frame applied (or that would be applied), in AppKit global coordinates.
    public let frame: WindowFrame?
    public let result: WindowActionResult

    public init(placement: Placement, frame: WindowFrame?, result: WindowActionResult) {
        self.placement = placement
        self.frame = frame
        self.result = result
    }
}

public enum ParkResult: Hashable, Sendable {
    case parked(ParkedWindow)
    /// Already tucked a moment ago and still on its way (a second click, a repeated shortcut): nothing
    /// to do and nothing to report.
    case alreadyTucked
    case noWindow
    case needsPermission
    case failed
}

/// Names one real window without holding it: the parking service keeps the window itself and makes the
/// token from it, so reading the same window again gives an equal token and a token can only ever reach
/// the window it was made from.
public struct WindowToken: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// The window that "Tuck" and "Arrange" act on: the focused window of the frontmost app.
public struct FrontWindowInfo: Hashable, Sendable {
    public let app: AppIdentity
    public let title: String
    /// The window itself, so Tuck and Arrange act on the one it names. Nil when no window can be read
    /// (Accessibility isn't allowed), when the fold names the app alone.
    public let window: WindowToken?

    public init(app: AppIdentity, title: String, window: WindowToken? = nil) {
        self.app = app
        self.title = title
        self.window = window
    }

    /// Whether both name the same window: renamed, perhaps, but not another one.
    public func isSameWindow(as other: FrontWindowInfo?) -> Bool {
        guard let other else { return false }
        return window == other.window && app.isSameApp(as: other.app)
    }
}

/// Where a restore should land: the usable area of the display the person is looking at, whether the
/// window's original display still exists, and the display after it for "Next display".
public struct PlacementContext: Hashable, Sendable {
    public var visibleFrame: CGRect
    public var originalDisplayAvailable: Bool
    public var nextVisibleFrame: CGRect?

    public init(visibleFrame: CGRect, originalDisplayAvailable: Bool = true, nextVisibleFrame: CGRect? = nil) {
        self.visibleFrame = visibleFrame
        self.originalDisplayAvailable = originalDisplayAvailable
        self.nextVisibleFrame = nextVisibleFrame
    }
}

/// Hides, restores and places real windows. The app's implementation uses the Accessibility API
/// in-process (Tuck is unsandboxed, so there is no helper process).
public protocol WindowParkingService: AnyObject {
    /// The window in front, holding on to it so `check`, `park(_:)` and `place` reach exactly this one.
    func frontWindow() -> FrontWindowInfo?
    /// Calls `onChange` on the main thread a beat after the window in front changes, closes or is renamed,
    /// or its app is hidden, with the window now in front (read as `frontWindow()` reads it) and whether
    /// the person brought it there rather than Tuck moving windows or the keyboard (`OwnFrontChanges`).
    /// Nil stops. Only the open panel watches, and nothing is looked at meanwhile.
    func watchFrontWindow(_ onChange: ((_ front: FrontWindowInfo?, _ byPerson: Bool) -> Void)?)
    /// Whether the window `frontWindow()` last named can still be acted on, asked just before the fold's
    /// Tuck or Arrange does. Prompts for Accessibility when it isn't allowed.
    func check(_ window: WindowToken?) -> ShownWindowCheck
    /// Parks the window `frontWindow()` named, checked again first; never another.
    func park(_ window: WindowToken) -> ParkResult
    /// Captures the focused window's frame at this moment and parks it, for the shortcut, the menu and the
    /// notch, which name no window. One parked off screen (`ParkingMethod.offScreen`) stays where it is
    /// until `moveOutOfSight` is called; one that can't be is minimised at once.
    func parkFrontWindow() -> ParkResult
    /// Moves windows parked off screen out of sight, once their cards cover them, so that nothing is
    /// seen going and no frame shows an empty spot. Ids of windows already out of sight, or minimised,
    /// are ignored.
    func moveOutOfSight(_ ids: Set<UUID>)
    /// Restores a parked window and reports once the result is confirmed: un-minimising animates, so a
    /// minimised window is only known to be back a moment after it is asked to come back. One parked
    /// off screen is moved straight back.
    func restore(_ window: ParkedWindow, placement: Placement, context: PlacementContext,
                 completion: @escaping (WindowActionOutcome) -> Void)
    /// Places the window `frontWindow()` named without parking it; one closed or tucked since is left
    /// alone. `.original` puts back the frame it had before Tuck first placed it.
    func place(_ window: WindowToken, placement: Placement) -> WindowActionOutcome
    /// Every open window with the facts `CandidatePolicy` needs. Listing never changes anything.
    func windowCandidates() -> [WindowCandidate]
    /// Those of the last listing's windows still open and not tucked meanwhile, so an open picker offers
    /// only what it would tuck.
    func stillListed(_ candidates: [WindowCandidate]) -> [WindowCandidate]
    /// While the picker is open, calls `onChange` on the main thread when one of these windows (from the
    /// last listing) closes or its app quits, so the picker can drop it. Nil stops; nothing is watched
    /// while the picker is closed.
    func watchListedWindows(_ candidates: [WindowCandidate], onChange: (() -> Void)?)
    /// Parks exactly these windows, each checked again just before it is put away. One result per
    /// candidate, in order; as with `parkFrontWindow`, those parked off screen move with `moveOutOfSight`.
    func park(_ candidates: [WindowCandidate]) -> [ParkResult]
    /// Minimises tucked windows so they stay tucked without Tuck's help: those tucked by hiding their app,
    /// before the app is shown again for one of its other windows, and those parked off screen, before
    /// Tuck quits or when their row is forgotten. Returns the ones that are now minimised.
    func keepTucked(_ windows: [ParkedWindow]) -> Set<UUID>
}

/// Stand-in for tests and previews: computes the exact frame a real restore would use and moves nothing.
public final class MockWindowParkingService: WindowParkingService {
    public private(set) var restores: [WindowActionOutcome] = []
    public var front: FrontWindowInfo?

    public init(front: FrontWindowInfo? = nil) {
        self.front = front
    }

    public func frontWindow() -> FrontWindowInfo? { front }

    /// Who is told when the window in front changes; a test calls it as the watcher would.
    public private(set) var frontWindowWatch: ((FrontWindowInfo?, Bool) -> Void)?

    public func watchFrontWindow(_ onChange: ((FrontWindowInfo?, Bool) -> Void)?) {
        frontWindowWatch = onChange
    }

    public func check(_ window: WindowToken?) -> ShownWindowCheck {
        guard let front else { return .closed }
        // No token: no window could be read, as when Accessibility isn't allowed.
        guard let window else { return .needsPermission }
        return front.window == window ? .ready : .stale
    }

    public func park(_ window: WindowToken) -> ParkResult {
        guard check(window) == .ready else { return .noWindow }
        return parkFrontWindow()
    }

    public func parkFrontWindow() -> ParkResult {
        guard let front else { return .noWindow }
        return .parked(ParkedWindow(app: front.app, title: front.title,
                                    originalFrame: WindowFrame(x: 120, y: 120, width: 900, height: 640)))
    }

    /// Every window asked to move out of sight, in the order asked.
    public private(set) var movedOutOfSight: [UUID] = []

    public func moveOutOfSight(_ ids: Set<UUID>) {
        movedOutOfSight += ids.sorted { $0.uuidString < $1.uuidString }
    }

    public func restore(_ window: ParkedWindow, placement: Placement, context: PlacementContext,
                        completion: @escaping (WindowActionOutcome) -> Void) {
        let frame = PlacementGeometry.frame(
            for: placement,
            originalFrame: window.originalFrame.cgRect,
            visibleFrame: context.visibleFrame,
            originalDisplayAvailable: context.originalDisplayAvailable,
            destinationVisibleFrame: context.nextVisibleFrame
        )
        let outcome = WindowActionOutcome(placement: placement, frame: WindowFrame(frame), result: .simulated)
        restores.append(outcome)
        completion(outcome)
    }

    public func place(_ window: WindowToken, placement: Placement) -> WindowActionOutcome {
        WindowActionOutcome(placement: placement, frame: nil, result: check(window) == .ready ? .simulated : .windowGone)
    }

    public func keepTucked(_ windows: [ParkedWindow]) -> Set<UUID> { Set(windows.map(\.id)) }

    public var candidates: [WindowCandidate] = []
    /// Candidates that refuse to be put away.
    public var refusing: Set<String> = []
    public private(set) var parkedCandidates: [String] = []

    public func windowCandidates() -> [WindowCandidate] { candidates }

    public func stillListed(_ candidates: [WindowCandidate]) -> [WindowCandidate] {
        candidates.filter { !parkedCandidates.contains($0.id) }
    }

    /// Who is told when a listed window closes; a test calls it as the watcher would.
    public private(set) var listedWindowsWatch: (() -> Void)?

    public func watchListedWindows(_ candidates: [WindowCandidate], onChange: (() -> Void)?) {
        listedWindowsWatch = onChange
    }

    public func park(_ candidates: [WindowCandidate]) -> [ParkResult] {
        candidates.map { candidate in
            guard !refusing.contains(candidate.id) else { return .failed }
            parkedCandidates.append(candidate.id)
            return .parked(ParkedWindow(app: candidate.app, title: candidate.title,
                                        originalFrame: WindowFrame(candidate.frame),
                                        displayID: candidate.displayID, displayName: candidate.displayName))
        }
    }
}

// MARK: - Rest

/// App-level pause and wake. The app's implementation is experimental and off by default: while
/// `isEnabled` is false nothing is paused (waking always works). See docs/decision-log.md.
public protocol RestService: AnyObject {
    var isEnabled: Bool { get }
    /// Quick enough for a menu: the policy and whether the app is in front. No app is asked anything.
    func eligibility(for app: AppIdentity) -> RestEligibility
    /// Checked when the person asks to rest: also counts the app's visible windows and checks audio.
    /// Busy-ness is measured as part of resting itself.
    func currentEligibility(for app: AppIdentity) -> RestEligibility
    /// Pauses an app after the explanation was accepted, measuring how busy it is first.
    func rest(_ app: AppIdentity, confirmedStrongly: Bool, acknowledged: Bool,
              completion: @escaping (Result<RestState, RestFailure>) -> Void)
    func wake(_ state: RestState) -> WakeOutcome
    /// Wakes every recorded app (before quitting or sleeping, and at launch after a crash). Returns the
    /// states still recorded: only apps that could not be woken.
    func wakeAll(_ states: [String: RestState]) -> [String: RestState]
}

/// Rest with no process control at all, for previews and tests of the surrounding flow.
public final class DisabledRestService: RestService {
    public init() {}
    public var isEnabled: Bool { false }

    public func eligibility(for app: AppIdentity) -> RestEligibility {
        RestSafetyPolicy.eligibility(for: app, context: RestContext())
    }

    public func currentEligibility(for app: AppIdentity) -> RestEligibility { eligibility(for: app) }

    public func rest(_ app: AppIdentity, confirmedStrongly: Bool, acknowledged: Bool,
                     completion: @escaping (Result<RestState, RestFailure>) -> Void) {
        completion(.failure(.disabled))
    }

    public func wake(_ state: RestState) -> WakeOutcome { state.isResting ? .stale : .wasAwake }
    /// Cannot signal anything, so whatever is recorded stays recorded.
    public func wakeAll(_ states: [String: RestState]) -> [String: RestState] { states }
}

// MARK: - Opening held items

public enum OpenOutcome: Hashable, Sendable {
    case opened(appName: String)
    case simulatedOpen(appName: String)
    case failed(reason: String)
}

public protocol HeldItemOpening {
    func open(_ item: HeldItem) -> OpenOutcome
}

/// Stand-in for tests and previews: reports which app would open the item without launching anything.
public struct SimulatedItemOpener: HeldItemOpening {
    public init() {}

    public func open(_ item: HeldItem) -> OpenOutcome {
        switch item.kind {
        case .file:
            switch item.url?.pathExtension.lowercased() ?? "" {
            case "pdf", "png", "jpg", "jpeg", "heic": return .simulatedOpen(appName: "Preview")
            case "txt", "md", "rtf": return .simulatedOpen(appName: "TextEdit")
            case "": return .failed(reason: "Missing file")
            default: return .simulatedOpen(appName: "its default app")
            }
        case .link:
            return .simulatedOpen(appName: "your browser")
        case .music:
            return .simulatedOpen(appName: HeldItemClassifier.musicProvider(for: item.url) ?? "your music app")
        case .text:
            return .failed(reason: "Text is copied, not opened")
        case .stack:
            return .simulatedOpen(appName: "the Finder")
        }
    }
}

// MARK: - Pasteboard

public protocol PasteboardWriting {
    func copy(_ text: String)
    /// Puts a clipboard entry back as it was copied: its files, image, styling or colour, with its text.
    func copy(_ entry: ClipboardEntry)
}

extension PasteboardWriting {
    public func copy(_ entry: ClipboardEntry) { copy(entry.text) }
}

// MARK: - Haptics

/// The only moments that carry a tactile tick: a drag crossing into the drop target, something landing
/// in Tuck, and a window snapping into a placement. Opening, folding, scrolling and clicks add none;
/// they are shown on screen only.
public enum HapticEvent: CaseIterable, Sendable {
    /// A drag crossed into the drop target.
    case dropTargetEntered
    /// A drop or tuck landed in Tuck.
    case deposited
    /// A window snapped into a placement.
    case placementSnapped
}

/// Keeps ticks apart: a second one within `minimumInterval` of the last is dropped, so quick swipes in
/// a row never turn into a buzz.
public struct HapticPacing: Sendable {
    public static let minimumInterval: TimeInterval = 0.35
    private var lastTick: TimeInterval?

    public init() {}

    /// Whether a tick may play at `time` (seconds on any steady clock); if so, it counts as played.
    public mutating func allows(at time: TimeInterval) -> Bool {
        if let lastTick, time - lastTick < Self.minimumInterval { return false }
        lastTick = time
        return true
    }
}

public protocol HapticFeedbackProviding: AnyObject {
    var isEnabled: Bool { get set }
    func perform(_ event: HapticEvent)
}

/// Records events instead of playing them; used in tests and previews.
public final class RecordingHaptics: HapticFeedbackProviding {
    public var isEnabled: Bool
    public private(set) var events: [HapticEvent] = []

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public func perform(_ event: HapticEvent) {
        guard isEnabled else { return }
        events.append(event)
    }
}

// MARK: - Persistence

public protocol LibraryPersistence {
    func load() -> TuckLibrary?
    func save(_ library: TuckLibrary)
    /// Writes anything still pending now, rather than after the usual short delay.
    func flush()
}

extension LibraryPersistence {
    public func flush() {}
}

/// Persistence for tests and previews: lives for the process only. The app uses `FileLibraryPersistence`.
public final class InMemoryLibraryPersistence: LibraryPersistence {
    private var stored: TuckLibrary?

    public init(initial: TuckLibrary? = nil) {
        stored = initial
    }

    public func load() -> TuckLibrary? { stored }
    public func save(_ library: TuckLibrary) { stored = library }
}
