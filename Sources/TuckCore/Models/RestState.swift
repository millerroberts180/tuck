import Foundation

// Rest: an explicit, app-level, sleep-like state for a tucked application. It pauses the app's
// process to reduce active CPU work while keeping it in memory for a quick, deliberate wake. It does
// not free memory, does not reach an app's helper processes, and is never automatic. This file holds
// the model, the safety policy and the pause/wake logic; the macOS side only supplies process facts
// and the two signals, through `ProcessControl`.

/// Who a paused process is, so a later wake can never signal a different process that reused its pid.
public struct ProcessIdentity: Hashable, Codable, Sendable {
    public let pid: Int32
    /// Kernel start time, in seconds since 1970 with microsecond precision. With the pid, unique.
    public let startTime: Double
    public let executablePath: String
    public let bundleID: String

    public init(pid: Int32, startTime: Double, executablePath: String, bundleID: String) {
        self.pid = pid
        self.startTime = startTime
        self.executablePath = executablePath
        self.bundleID = bundleID
    }
}

public enum RestState: Hashable, Codable, Sendable {
    case awake
    case resting(since: Date, process: ProcessIdentity)

    public var isResting: Bool {
        if case .resting = self { return true }
        return false
    }
}

public enum RestEligibility: Hashable, Sendable {
    case eligible
    /// Allowed only after a stronger, explicit confirmation.
    case needsStrongConfirmation(reason: String)
    case unavailable(reason: String)
}

/// Kinds of app that are never rested: pausing them can drop calls, stall transfers, corrupt syncs,
/// freeze a build or cut a connection.
public enum RestRiskCategory: String, CaseIterable, Sendable {
    case media, calls, transfers, terminal, developerTools, vpn, sync, remoteDesktop, system, browser, communication

    public var label: String {
        switch self {
        case .media: "media"
        case .calls: "calling"
        case .transfers: "download"
        case .terminal: "terminal"
        case .developerTools: "developer"
        case .vpn: "VPN"
        case .sync: "sync"
        case .remoteDesktop: "remote desktop"
        case .system: "system"
        case .browser: "browser"
        case .communication: "messaging and mail"
        }
    }
}

/// What is true of an app right now, gathered by the macOS side when Rest is considered.
public struct RestContext: Equatable, Sendable {
    public var isOwnApp: Bool
    public var isFrontmost: Bool
    /// Windows of the app still on screen (not minimised, not tucked).
    public var visibleWindowCount: Int
    /// Whether the app is playing or recording audio; nil when it cannot be told.
    public var isUsingAudio: Bool?
    /// Recent CPU use as a percentage of one core; nil when it has not been measured.
    public var recentCPUPercent: Double?

    public init(isOwnApp: Bool = false, isFrontmost: Bool = false, visibleWindowCount: Int = 0,
                isUsingAudio: Bool? = false, recentCPUPercent: Double? = nil) {
        self.isOwnApp = isOwnApp
        self.isFrontmost = isFrontmost
        self.visibleWindowCount = visibleWindowCount
        self.isUsingAudio = isUsingAudio
        self.recentCPUPercent = recentCPUPercent
    }
}

/// Who may be rested, and when. An allow-list: only offline document apps that hold no calls, media,
/// connections or background work of their own. Every other app, known risky or simply unknown, is
/// unavailable; normal tucking stays available for all of them.
public enum RestSafetyPolicy {
    public static let firstUseExplanation = "Rest pauses this app to reduce active CPU work. It stays in memory and may pause playback, calls, downloads, syncing, terminals, or network activity."

    public static let allowList: Set<String> = [
        "com.apple.Preview",
        "com.apple.TextEdit",
        "com.apple.iWork.Pages",
        "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote",
        "com.apple.calculator",
        "com.apple.FontBook"
    ]

    /// Known risky apps, so the reason given is specific. Unlisted apps are refused anyway.
    public static let knownRisky: [String: RestRiskCategory] = [
        "com.apple.Music": .media, "com.spotify.client": .media, "com.apple.TV": .media,
        "com.apple.podcasts": .media, "com.apple.QuickTimePlayerX": .media, "org.videolan.vlc": .media,
        "com.apple.FaceTime": .calls, "us.zoom.xos": .calls, "com.microsoft.teams2": .calls,
        "com.hnc.Discord": .calls, "com.tinyspeck.slackmacgap": .communication,
        "com.apple.MobileSMS": .communication, "com.apple.mail": .communication,
        "com.apple.Terminal": .terminal, "com.googlecode.iterm2": .terminal, "dev.warp.Warp-Stable": .terminal,
        "com.apple.dt.Xcode": .developerTools, "com.microsoft.VSCode": .developerTools,
        "com.getdropbox.dropbox": .sync, "com.google.drivefs": .sync, "com.microsoft.OneDrive": .sync,
        "com.apple.ScreenSharing": .remoteDesktop, "com.microsoft.rdc.macos": .remoteDesktop,
        "com.apple.ActivityMonitor": .system, "com.apple.systempreferences": .system,
        "com.apple.finder": .system, "com.apple.Safari": .browser, "com.google.Chrome": .browser,
        "org.mozilla.firefox": .browser, "app.zen-browser.zen": .browser,
        "com.transmissionbt.Transmission": .transfers
    ]

    /// Above this recent CPU use an app is busy, and resting it needs a stronger confirmation.
    public static let busyCPUPercent: Double = 15

    public static func eligibility(for app: AppIdentity, context: RestContext) -> RestEligibility {
        if context.isOwnApp { return .unavailable(reason: "Tuck can't rest itself.") }
        if app.bundleID.isEmpty { return .unavailable(reason: "\(app.name) can't be identified safely.") }
        if let category = knownRisky[app.bundleID] {
            return .unavailable(reason: "Not safe to rest \(category.label) apps.")
        }
        guard allowList.contains(app.bundleID) else {
            return .unavailable(reason: "Rest is limited to a few offline document apps for now.")
        }
        if context.isFrontmost { return .unavailable(reason: "Switch away from \(app.name) first.") }
        if context.visibleWindowCount > 0 {
            return .unavailable(reason: "Tuck \(app.name)'s other windows first")
        }
        if context.isUsingAudio == true { return .unavailable(reason: "\(app.name) is playing or recording audio.") }
        if context.isUsingAudio == nil {
            return .needsStrongConfirmation(reason: "Tuck can't tell whether \(app.name) is using audio.")
        }
        if let cpu = context.recentCPUPercent, cpu >= busyCPUPercent {
            return .needsStrongConfirmation(reason: "\(app.name) is busy right now; resting it pauses that work.")
        }
        return .eligible
    }
}

/// Failures are reported, never hidden; a failed rest always leaves the app running.
public enum RestFailure: Error, Hashable, Sendable {
    /// Rest is switched off (the technical spike): nothing is signalled.
    case disabled
    /// The first-use explanation has not been accepted.
    case notAcknowledged
    case notEligible(String)
    case needsStrongConfirmation(String)
    case processGone
    /// The pid now belongs to a different process.
    case processChanged
    case signalFailed
    /// The signal was accepted but the process did not change state.
    case didNotTakeEffect
}

public enum WakeOutcome: Hashable, Sendable {
    case woke
    case wasAwake
    /// The rested process has gone or its pid was reused: nothing was signalled.
    case stale
    case failed(RestFailure)
}

/// The two things Rest needs from the system, plus facts to check them. Same-user, reversible, public:
/// on macOS, a stop signal and a continue signal to the app's own process.
public protocol ProcessControl {
    /// The process running under this pid now, or nil when there is none.
    func identity(of pid: Int32) -> ProcessIdentity?
    func pause(_ pid: Int32) -> Bool
    func resume(_ pid: Int32) -> Bool
    /// Whether the kernel reports the process stopped; nil when it cannot be read.
    func isPaused(_ pid: Int32) -> Bool?
}

/// Pausing and waking, checked at every step: switched on, explained, eligible, the same process, the
/// signal accepted, and the state actually changed. Anything less leaves the app as it was.
public enum RestController {
    public static func rest(expected: ProcessIdentity?, eligibility: RestEligibility, confirmedStrongly: Bool,
                            acknowledged: Bool, isEnabled: Bool, control: ProcessControl,
                            now: Date = Date()) -> Result<RestState, RestFailure> {
        guard isEnabled else { return .failure(.disabled) }
        guard acknowledged else { return .failure(.notAcknowledged) }
        switch eligibility {
        case .unavailable(let reason): return .failure(.notEligible(reason))
        case .needsStrongConfirmation(let reason) where !confirmedStrongly: return .failure(.needsStrongConfirmation(reason))
        case .eligible, .needsStrongConfirmation: break
        }
        guard let expected else { return .failure(.processGone) }
        switch control.identity(of: expected.pid) {
        case nil: return .failure(.processGone)
        case let current? where current != expected: return .failure(.processChanged)
        default: break
        }
        guard control.pause(expected.pid) else { return .failure(.signalFailed) }
        guard control.isPaused(expected.pid) == true else {
            _ = control.resume(expected.pid) // never leave it half-done
            return .failure(.didNotTakeEffect)
        }
        return .success(.resting(since: now, process: expected))
    }

    public static func wake(_ state: RestState, control: ProcessControl) -> WakeOutcome {
        guard case .resting(_, let process) = state else { return .wasAwake }
        guard control.identity(of: process.pid) == process else { return .stale }
        guard control.resume(process.pid) else { return .failed(.signalFailed) }
        if control.isPaused(process.pid) == true { return .failed(.didNotTakeEffect) }
        return .woke
    }

    /// At launch (after a crash, say) and before quitting or sleeping: wakes every app still recorded
    /// as resting. Returns the states left: only apps that could not be woken stay recorded.
    public static func wakeAll(_ states: [String: RestState], control: ProcessControl) -> [String: RestState] {
        states.filter { _, state in
            if case .failed = wake(state, control: control) { return true }
            return false
        }
    }
}
