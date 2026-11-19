import CoreGraphics
import Foundation

/// Facts about one open window, gathered from Accessibility and the window server's on-screen list.
/// Plain data, so which windows are offered can be decided, and tested, without either.
public struct WindowCandidate: Identifiable, Hashable, Sendable {
    /// Stable while the window exists: its process and Accessibility element.
    public let id: String
    public let app: AppIdentity
    public let pid: Int32
    public let title: String
    /// AppKit global coordinates.
    public let frame: CGRect
    public let displayID: String?
    public let displayName: String?
    /// Accessibility subrole, such as "AXStandardWindow".
    public let subrole: String?
    public let isMinimised: Bool
    public let isFullScreen: Bool
    /// Showing now on the current desktop, according to the window server.
    public let isOnScreen: Bool
    /// An ordinary Dock app, not a background or menu-bar-only agent.
    public let isRegularApp: Bool
    public let isOwnApp: Bool
    /// Tuck is resting the app, so its windows must not be touched.
    public let isAppResting: Bool
    /// Front-to-back position in the on-screen list; lower is nearer the front.
    public let stackOrder: Int

    public init(id: String, app: AppIdentity, pid: Int32, title: String, frame: CGRect, displayID: String? = nil,
                displayName: String? = nil, subrole: String?, isMinimised: Bool = false, isFullScreen: Bool = false,
                isOnScreen: Bool = true, isRegularApp: Bool = true, isOwnApp: Bool = false, isAppResting: Bool = false,
                stackOrder: Int) {
        self.id = id
        self.app = app
        self.pid = pid
        self.title = title
        self.frame = frame
        self.displayID = displayID
        self.displayName = displayName
        self.subrole = subrole
        self.isMinimised = isMinimised
        self.isFullScreen = isFullScreen
        self.isOnScreen = isOnScreen
        self.isRegularApp = isRegularApp
        self.isOwnApp = isOwnApp
        self.isAppResting = isAppResting
        self.stackOrder = stackOrder
    }

    public var displayTitle: String { title.isEmpty ? "Untitled window" : title }

    /// The title read out after the app's name, or nil when it would say nothing more: an untitled
    /// window, or one titled after its app, as Music and Calendar title theirs.
    public var pageTitle: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare(app.name) != .orderedSame else { return nil }
        return trimmed
    }
}

/// Why an open window is not offered for tucking.
public enum CandidateExclusion: Hashable, Sendable {
    case tuckItself
    case backgroundApp
    case resting
    case notStandardWindow
    case minimised
    case fullScreen
    case offScreen
    case tooSmall
}

/// Which open windows Tuck offers. Conservative on purpose: only ordinary, visible, standard windows
/// of ordinary apps on the current desktop, nearest the front first, and never more than a short list.
/// Offering a window never tucks it; only an explicit choice does.
public enum CandidatePolicy {
    public static let limit = 12
    public static let minimumSize = CGSize(width: 120, height: 80)
    public static let standardSubrole = "AXStandardWindow"

    public static func exclusion(for candidate: WindowCandidate) -> CandidateExclusion? {
        if candidate.isOwnApp { return .tuckItself }
        if !candidate.isRegularApp { return .backgroundApp }
        if candidate.isAppResting { return .resting }
        if candidate.subrole != standardSubrole { return .notStandardWindow }
        if candidate.isMinimised { return .minimised }
        if candidate.isFullScreen { return .fullScreen }
        if !candidate.isOnScreen { return .offScreen }
        if candidate.frame.width < minimumSize.width || candidate.frame.height < minimumSize.height { return .tooSmall }
        return nil
    }

    /// The windows worth offering, nearest the front first, capped at `limit`.
    public static func suggestions(from all: [WindowCandidate]) -> [WindowCandidate] {
        Array(all.filter { exclusion(for: $0) == nil }.sorted { $0.stackOrder < $1.stackOrder }.prefix(limit))
    }

    /// Suggestions grouped by app process, apps in the order of their front-most window.
    public static func groupedByApp(_ suggestions: [WindowCandidate]) -> [CandidateGroup] {
        var order: [Int32] = []
        var buckets: [Int32: [WindowCandidate]] = [:]
        for candidate in suggestions {
            if buckets[candidate.pid] == nil { order.append(candidate.pid) }
            buckets[candidate.pid, default: []].append(candidate)
        }
        return order.compactMap { pid in
            guard let windows = buckets[pid], let first = windows.first else { return nil }
            return CandidateGroup(app: first.app, pid: pid, windows: windows)
        }
    }
}

/// One app's offered windows.
public struct CandidateGroup: Identifiable, Hashable, Sendable {
    public let app: AppIdentity
    public let pid: Int32
    public let windows: [WindowCandidate]

    public var id: Int32 { pid }
}

/// Which offered windows the person has ticked. Nothing is ticked to begin with.
public struct WindowSelection: Equatable, Sendable {
    public private(set) var selected: Set<String> = []

    public init() {}

    public var count: Int { selected.count }
    public var isEmpty: Bool { selected.isEmpty }
    /// The explicit action: "Tuck 3".
    public var actionTitle: String { selected.isEmpty ? "Tuck" : "Tuck \(selected.count)" }

    public func isSelected(_ id: String) -> Bool { selected.contains(id) }

    public mutating func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    public func allSelected(in group: CandidateGroup) -> Bool {
        group.windows.allSatisfy { selected.contains($0.id) }
    }

    /// How many of one app's windows are ticked, for its row's "2 of 3 selected".
    public func count(in group: CandidateGroup) -> Int {
        group.windows.filter { selected.contains($0.id) }.count
    }

    /// Ticks every window of one app, or unticks them all when they are all ticked already.
    public mutating func toggleAll(in group: CandidateGroup) {
        let ids = Set(group.windows.map(\.id))
        if ids.isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
    }

    /// Keeps only ticks for windows still offered after the list is refreshed.
    public mutating func keepOnly(_ candidates: [WindowCandidate]) {
        selected.formIntersection(candidates.map(\.id))
    }

    /// The ticked windows, in the order they were offered.
    public func chosen(from candidates: [WindowCandidate]) -> [WindowCandidate] {
        candidates.filter { selected.contains($0.id) }
    }
}

/// How a batch of restores went, for one calm summary instead of a message per window.
public struct RestoreSummary: Equatable, Sendable {
    public private(set) var restored = 0
    public private(set) var gone = 0
    public private(set) var kept = 0

    public init(results: [WindowActionResult] = []) {
        results.forEach { add($0) }
    }

    public mutating func add(_ result: WindowActionResult) {
        switch result {
        case .moved, .constrained, .simulated: restored += 1
        case .windowGone: gone += 1
        case .failed, .needsPermission, .unchanged: kept += 1
        }
    }

    public var total: Int { restored + gone + kept }
}
