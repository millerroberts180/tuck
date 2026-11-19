import Foundation

/// Everything in Tuck: one stream of tucked windows and held items, each newest first, plus the Rest
/// state of apps. Pure value logic so it can be unit-tested and persisted without touching UI code.
///
/// There are no sessions. Libraries saved with sessions are merged into this one stream on load
/// (`LegacySessions`), every window and item kept.
public struct TuckLibrary: Codable, Equatable, Sendable {
    /// Most recently tucked first.
    public private(set) var windows: [ParkedWindow]
    /// Most recently added first. A stack is one item.
    public private(set) var items: [HeldItem]
    /// App-level Rest state, keyed by bundle identifier.
    public private(set) var restStates: [String: RestState]

    public init(windows: [ParkedWindow] = [], items: [HeldItem] = [], restStates: [String: RestState] = [:]) {
        self.windows = windows
        self.items = items
        self.restStates = restStates
    }

    // MARK: Queries

    public var isEmpty: Bool { windows.isEmpty && items.isEmpty }

    /// Everything tucked: windows and held rows, a stack counting as one.
    public var totalItemCount: Int { windows.count + items.count }

    public func window(id: UUID) -> ParkedWindow? { windows.first { $0.id == id } }

    public func heldItem(id: UUID) -> HeldItem? { items.first { $0.id == id } }

    public func restState(for bundleID: String) -> RestState { restStates[bundleID] ?? .awake }

    /// Most held rows Tuck keeps. A stack counts as one row. Tuck is a short-term surface, so a full
    /// stream refuses new drops rather than silently dropping old ones. A library migrated from
    /// sessions may hold more than this; nothing is taken out, new drops just wait for room.
    public static let heldItemLimit = 200

    /// How many more held rows fit right now.
    public var remainingCapacity: Int { max(Self.heldItemLimit - items.count, 0) }

    /// Every file reference held, stack members included.
    public var referencedFileURLs: Set<URL> {
        Set(items.flatMap(\.fileURLs).map(\.standardizedFileURL))
    }

    // MARK: Items

    /// Adds a held item at the top of the stream.
    public mutating func add(_ item: HeldItem) {
        items.insert(item, at: 0)
    }

    /// Tucks a window at the top of the stream.
    public mutating func park(_ window: ParkedWindow) {
        windows.insert(window, at: 0)
    }

    /// Tucks several windows at once; the first ends up on top. Each stays its own restorable row.
    public mutating func parkAll(_ windows: [ParkedWindow]) {
        self.windows.insert(contentsOf: windows, at: 0)
    }

    @discardableResult
    public mutating func removeWindow(id: UUID) -> ParkedWindow? {
        guard let position = windows.firstIndex(where: { $0.id == id }) else { return nil }
        return windows.remove(at: position)
    }

    /// Removes an item wherever it is: a row of its own, or a file inside a stack (a stack left with one
    /// file becomes that file). Returns the item removed, or nil if there was none.
    @discardableResult
    public mutating func removeHeldItem(id: UUID) -> HeldItem? {
        if let position = items.firstIndex(where: { $0.id == id }) {
            return items.remove(at: position)
        }
        var member: HeldItem?
        reconcileHeldItems { item in
            guard item.id == id else { return item }
            member = item
            return nil
        }
        return member
    }

    /// Takes every held item out and returns them, so the caller can delete the files Tuck itself saved
    /// for them; the person's own files are only ever referenced and are never touched.
    public mutating func removeAllItems() -> [HeldItem] {
        defer { items.removeAll() }
        return items
    }

    /// Records how windows are now put away (after windows hidden with their app were minimised).
    public mutating func setParkingMethod(_ method: ParkingMethod, forWindows ids: Set<UUID>) {
        for position in windows.indices where ids.contains(windows[position].id) {
            windows[position].method = method
        }
    }

    /// Updates the payload of a text item. Returns false if the item is missing or not text.
    @discardableResult
    public mutating func updateText(itemID: UUID, to text: String) -> Bool {
        guard let position = items.firstIndex(where: { $0.id == itemID && $0.kind == .text }) else { return false }
        items[position].updateText(text)
        return true
    }

    /// Replaces a stack with its members, in place.
    @discardableResult
    public mutating func unstack(itemID: UUID) -> Bool {
        guard let position = items.firstIndex(where: { $0.id == itemID && $0.kind == .stack }) else { return false }
        items.replaceSubrange(position...position, with: items[position].children ?? [])
        return true
    }

    /// Rewrites every held item (and stack member) through `transform`; returning nil removes it.
    /// Stacks left with a single member collapse back to that member; empty stacks disappear.
    /// Returns how many items were removed.
    @discardableResult
    public mutating func reconcileHeldItems(_ transform: (HeldItem) -> HeldItem?) -> Int {
        var removed = 0
        func apply(_ items: [HeldItem]) -> [HeldItem] {
            items.compactMap { item in
                guard item.kind == .stack else {
                    let result = transform(item)
                    if result == nil { removed += 1 }
                    return result
                }
                var stack = item
                let members = apply(item.children ?? [])
                switch members.count {
                case 0: return nil
                case 1: return members[0]
                default:
                    stack.children = members
                    stack.title = HeldItem.stackTitle(count: members.count)
                    return stack
                }
            }
        }
        items = apply(items)
        return removed
    }

    public mutating func setRestState(_ state: RestState, for bundleID: String) {
        restStates[bundleID] = state
    }
}
