import CoreGraphics
import Foundation

/// Where a tucked window waits while it stays open: just beyond a bottom corner of a display, the way
/// the AeroSpace window manager keeps the windows of other workspaces. Moving a window there and back is
/// instant and has no system animation, so Tuck's card is the only movement seen. Frames are in Quartz
/// global coordinates (origin at the top left of the primary display, y growing downwards), as the
/// Accessibility API reads and writes them.
///
/// macOS doesn't let an ordinary window leave every display. Measured with AppKit windows: moved above
/// a display, a window is held below the menu bar; moved beyond a side, it is pulled back until about
/// 40 points show; moved down, it is held while its title bar (28 points, 52 with a toolbar) is still on
/// the display; and moved so that nothing is left on any display, it is pulled back a moment later.
/// What stays put is a window one point over a display's outer edge at the bottom. All that shows of
/// it is a strip one point wide and as tall as its title bar, along the very edge of the screen.
public enum OffScreenParking {
    /// How far a parked window stays over its display's edge. Less is rounded to nothing, and a window
    /// with nothing left on any display is pulled back into view.
    public static let overlap: CGFloat = 1
    /// The thickest and longest strip of a window still counted as out of sight. The length allows for
    /// the title bar macOS keeps on the display, toolbars included.
    public static let thickestSliver: CGFloat = 2
    public static let longestSliver: CGFloat = 120

    /// Where to move a window of this size: beyond the bottom-right corner of a display, or else its
    /// bottom-left, wherever no other display lies beyond. Its own display is tried first, so the strip
    /// stays on the display it was on and the window stays on that display's desktop. Nil without
    /// displays.
    public static func origin(for size: CGSize, preferring display: CGRect?, displays: [CGRect]) -> CGPoint? {
        let ordered = displays.filter { $0 == display } + displays.filter { $0 != display }
        for screen in ordered {
            let corners = [CGPoint(x: screen.maxX - overlap, y: screen.maxY - overlap),
                           CGPoint(x: screen.minX - size.width + overlap, y: screen.maxY - overlap)]
            for origin in corners {
                // macOS may hold the window higher, by up to its title bar's height: nowhere on the way up
                // may it cross another display.
                let reach = CGRect(x: origin.x, y: screen.maxY - longestSliver, width: size.width,
                                   height: size.height + longestSliver - overlap)
                if isOutOfSight(reach, displays: displays) { return origin }
            }
        }
        return nil
    }

    /// Whether no more than a sliver of this frame shows on any display. False without displays, when
    /// nothing can be told.
    public static func isOutOfSight(_ frame: CGRect, displays: [CGRect]) -> Bool {
        !displays.isEmpty && displays.allSatisfy { display in
            guard let shown = shared(frame, display) else { return true }
            return min(shown.width, shown.height) <= thickestSliver && max(shown.width, shown.height) <= longestSliver
        }
    }

    /// Whether a frame is where a parked window waits: out of sight, with its strip still on a display.
    /// One with nothing left on any display (after a display was removed, say) is soon pulled back into
    /// view by macOS, so it is parked again.
    public static func isParked(_ frame: CGRect, displays: [CGRect]) -> Bool {
        isOutOfSight(frame, displays: displays) && displays.contains { shared(frame, $0) != nil }
    }

    /// What becomes of a parked window that moved or changed size without Tuck moving it, or that is
    /// looked at again once Mission Control ends.
    public enum Drift: Equatable, Sendable {
        /// Still parked; or nothing can be told (no displays); or the person has it in front, having
        /// gone to it or dragged it back, which the focus watcher sees to.
        case stays
        /// Back in view without Tuck restoring it (its app resized it or held it on screen once Mission
        /// Control let it go, say): moved out of sight again.
        case parkAgain
        /// Back in view again, moments after being parked again more than once: its app is holding it
        /// on screen, so it is minimised.
        case minimise
        /// Chosen by the person in Mission Control: it comes back where it was, as when they go to it
        /// from its app's Dock icon. Only `driftAfterMissionControl` gives this.
        case bringBack
    }

    /// How many times a window that came back into view by itself is parked again within
    /// `pullBackSpan` before its app is taken to be holding it there.
    public static let pullBacksAllowed = 2
    public static let pullBackSpan: TimeInterval = 2

    /// `parkedAgain` holds when (system uptime) the window was last parked again after coming back.
    public static func drift(of frame: CGRect, displays: [CGRect], inFront: Bool, parkedAgain: [TimeInterval],
                             now: TimeInterval) -> Drift {
        guard !displays.isEmpty, !isParked(frame, displays: displays), !inFront else { return .stays }
        let recent = parkedAgain.filter { now - $0 < pullBackSpan }.count
        return recent < pullBacksAllowed ? .parkAgain : .minimise
    }

    /// What becomes of a parked window once Mission Control's exit has settled (`MissionControlVisit`).
    /// One the person chose there comes back. Any other back in view is parked again, even with the
    /// keyboard in it, since Mission Control put it there, or its app did as Mission Control let go. That
    /// isn't its app pulling it back, so it doesn't count towards minimising it.
    public static func driftAfterMissionControl(of frame: CGRect, displays: [CGRect], chosen: Bool) -> Drift {
        if chosen { return .bringBack }
        guard !displays.isEmpty, !isParked(frame, displays: displays) else { return .stays }
        return .parkAgain
    }

    /// A window as the window server lists it: its owner and its frame.
    public struct ListedWindow: Equatable, Sendable {
        public let pid: Int32
        public let frame: CGRect

        public init(pid: Int32, frame: CGRect) {
            self.pid = pid
            self.frame = frame
        }
    }

    /// Which window takes the keyboard once the window it was in goes off screen, so nothing is typed
    /// into a window no one can see. `listed` runs front to back. The frontmost of the app's other
    /// windows in view comes first, as when a window is minimised; otherwise the frontmost window in view
    /// of another app, as when an app is hidden. Windows leaving now (matched by owner and frame, since
    /// the list can lag a move by a moment), windows already out of sight and windows too small to be
    /// offered for tucking are passed over. Nil when nothing else is in view.
    public static func successor(to pid: Int32, leaving: [ListedWindow], in listed: [ListedWindow],
                                 displays: [CGRect]) -> ListedWindow? {
        let inView = listed.filter { window in
            window.frame.width >= CandidatePolicy.minimumSize.width
                && window.frame.height >= CandidatePolicy.minimumSize.height
                && !isOutOfSight(window.frame, displays: displays)
                && !leaving.contains { $0.pid == window.pid && close($0.frame, window.frame) }
        }
        return inView.first { $0.pid == pid } ?? inView.first
    }

    private static func shared(_ frame: CGRect, _ display: CGRect) -> CGRect? {
        let shown = display.intersection(frame)
        return shown.isNull || shown.width <= 0 || shown.height <= 0 ? nil : shown
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}
