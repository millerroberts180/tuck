import Foundation

/// Parked windows are listed one row per window: each row is a whole window, brought back as it was.
public enum WindowOrdering {
    /// Most recently tucked first; windows tucked at the same moment fall back to app name.
    public static func newestFirst(_ windows: [ParkedWindow]) -> [ParkedWindow] {
        windows.sorted { lhs, rhs in
            if lhs.tuckedAt != rhs.tuckedAt { return lhs.tuckedAt > rhs.tuckedAt }
            return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
        }
    }
}

/// Parked windows from one app, shown as one row. A single window is a direct row; several windows
/// are an app row that expands, on purpose, to show each whole window.
public struct AppWindowGroup: Identifiable, Hashable, Sendable {
    public let app: AppIdentity
    /// Newest first.
    public let windows: [ParkedWindow]

    public var id: String { app.bundleID.isEmpty ? "name:\(app.name)" : app.bundleID }
    public var isMultiWindow: Bool { windows.count > 1 }
    public var mostRecentTuck: Date { windows.first?.tuckedAt ?? .distantPast }
}

public enum WindowGrouping {
    /// Groups windows by app (bundle identifier, else app name). Groups follow their most recently
    /// tucked window; inside a group, windows are newest first.
    public static func groups(for windows: [ParkedWindow]) -> [AppWindowGroup] {
        var order: [String] = []
        var buckets: [String: [ParkedWindow]] = [:]
        for window in WindowOrdering.newestFirst(windows) {
            let key = window.app.bundleID.isEmpty ? "name:\(window.app.name)" : window.app.bundleID
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(window)
        }
        return order.compactMap { key in
            guard let members = buckets[key], let first = members.first else { return nil }
            return AppWindowGroup(app: first.app, windows: members)
        }
    }
}

/// Which multi-window app rows are open. Everything starts collapsed, a row opens and closes only on
/// a deliberate click, and rows that no longer hold several windows are forgotten.
public struct WindowGroupExpansion: Equatable, Sendable {
    public private(set) var expanded: Set<String> = []

    public init() {}

    public func isExpanded(_ group: AppWindowGroup) -> Bool {
        group.isMultiWindow && expanded.contains(group.id)
    }

    public mutating func toggle(_ group: AppWindowGroup) {
        guard group.isMultiWindow else { return }
        if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
    }

    /// Keeps only rows that still group several windows.
    public mutating func prune(to groups: [AppWindowGroup]) {
        expanded.formIntersection(groups.filter(\.isMultiWindow).map(\.id))
    }
}
