import Foundation

/// What clearing everything held involves, worked out before anything is removed so the person is
/// asked exactly the question that applies.
///
/// Clearing only ever removes Tuck's own records. A held file is a reference to the person's file and
/// clearing drops the reference, never the file. The one exception, always called out, is files Tuck
/// itself wrote when something arrived without a file of its own (a promised Mail message, a dragged
/// image): those exist only in Tuck's folder and are deleted with their rows. Tucked windows are never
/// part of it: they stay until restored.
public struct ClearPlan: Equatable, Sendable {
    public enum Question: Equatable, Sendable {
        /// Nothing to lose: remove at once.
        case none
        /// Held items only; confirm once. No file is deleted.
        case items
        /// Held items, some of them files Tuck saved from drops, which clearing deletes.
        case deletesSavedFiles(Int)
    }

    /// Held rows, a stack counting as one.
    public let itemCount: Int
    /// Files Tuck saved from drops that clearing would delete. Never a file the person dropped in.
    public let savedFiles: [URL]

    public init(items: [HeldItem], isSavedByTuck: (URL) -> Bool) {
        itemCount = items.count
        savedFiles = items.flatMap(\.fileURLs).filter(isSavedByTuck)
    }

    public var question: Question {
        if !savedFiles.isEmpty { return .deletesSavedFiles(savedFiles.count) }
        return itemCount > 0 ? .items : .none
    }
}
