import Foundation

/// Setup's steps, in order: Accessibility, which tucking needs; the core moves, done with the real Tuck;
/// then where Settings and the tutorial are, and open at login. Reopened from Settings as the tutorial it
/// is only the practice, since the permission and the login item are already settled there.
public enum SetupStep: Int, CaseIterable, Sendable {
    case accessibility, practice, done

    public static func steps(tutorialOnly: Bool) -> [SetupStep] { tutorialOnly ? [.practice] : allCases }
}

/// The practice step's checklist: the moves Tuck is used for, each ticked off when the real Tuck reports
/// that it happened, never by a timer. Plain state, so what counts can be checked without a window.
public struct SetupPractice: Equatable, Sendable {
    /// What the practice teaches, in the order Tuck is used.
    public enum Move: String, CaseIterable, Sendable {
        case open, tuck, bringBack, drop
    }

    /// What Tuck reports while setup is open.
    public enum Event: Equatable, Sendable {
        /// The fold opened, by any trigger: a click, a swipe, the shortcut or the menu-bar item.
        case opened
        /// Windows went into Tuck.
        case tucked(count: Int)
        /// A tucked window's restore finished, as it did.
        case restored(WindowActionResult)
        /// Something dropped onto Tuck was kept.
        case dropped(count: Int)

        /// The move this counts as, if any: only a window actually back on screen, and only something
        /// that actually arrived. A window that had closed, or a refused restore, counts for nothing.
        public var move: Move? {
            switch self {
            case .opened: .open
            case .tucked(let count): count > 0 ? .tuck : nil
            case .restored(let result): [.moved, .constrained, .simulated].contains(result) ? .bringBack : nil
            case .dropped(let count): count > 0 ? .drop : nil
            }
        }
    }

    /// Each move counts once, however often it's repeated.
    public private(set) var done: Set<Move> = []

    public init() {}

    /// The first move not done yet; nil once all are.
    public var next: Move? { Move.allCases.first { !done.contains($0) } }
    public var isComplete: Bool { next == nil }

    /// Ticks off the move an event stands for; whether it was new.
    @discardableResult
    public mutating func record(_ event: Event) -> Bool {
        guard let move = event.move else { return false }
        return done.insert(move).inserted
    }
}
