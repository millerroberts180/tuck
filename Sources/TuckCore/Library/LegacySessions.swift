import Foundation

/// Libraries saved before the one stream (format 1) kept windows and held items in sessions, some of
/// them archived, plus a Loose area. Loading one merges all of it into the stream: every window and
/// every item from every session, archived ones and Loose included, newest first. Session names,
/// colours and intentions are not carried over; the file they were saved in is kept as a backup.
public enum LegacySessions {
    /// The parts of a format 1 library that hold anything worth keeping.
    struct Library: Decodable {
        struct Session: Decodable {
            var parkedWindows: [ParkedWindow]
            var heldItems: [HeldItem]
        }

        var sessions: [Session]
        var looseItems: [HeldItem]
        var restStates: [String: RestState]
    }

    struct Envelope: Decodable {
        var library: Library
    }

    /// The format 1 file's contents as one stream, or nil when it can't be read as format 1.
    public static func migrate(_ data: Data) -> TuckLibrary? {
        guard let legacy = try? JSONDecoder().decode(Envelope.self, from: data).library else { return nil }
        return merge(legacy)
    }

    static func merge(_ legacy: Library) -> TuckLibrary {
        let windows = newestFirst(legacy.sessions.flatMap(\.parkedWindows), by: \.tuckedAt)
        let items = newestFirst(legacy.looseItems + legacy.sessions.flatMap(\.heldItems), by: \.addedAt)
        return TuckLibrary(windows: windows, items: items, restStates: legacy.restStates)
    }

    /// Sorted by date, newest first; equal dates keep the order they were saved in.
    private static func newestFirst<Element>(_ elements: [Element], by date: KeyPath<Element, Date>) -> [Element] {
        elements.enumerated().sorted { lhs, rhs in
            let left = lhs.element[keyPath: date], right = rhs.element[keyPath: date]
            return left != right ? left > right : lhs.offset < rhs.offset
        }.map(\.element)
    }
}
