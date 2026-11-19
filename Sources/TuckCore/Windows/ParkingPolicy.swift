import Foundation

/// How a window that can't be parked off screen (full screen, say, or an app that won't let it go) is
/// minimised instead. Each way but the last keeps the Dock's animation out of view.
public enum ParkingPlan: Equatable, Sendable {
    /// The app can be hidden briefly, then its windows are minimised out of sight and the app is shown
    /// again. Used when all visible windows are going, as well as when other windows must stay open.
    case hideApp
    /// Other windows of the app stay open: the app is hidden for a moment, the chosen window is
    /// minimised out of sight, and the app is shown again, its other windows back within a couple of frames.
    case minimiseOutOfSight
    /// The app can't be hidden: the window is minimised in view, and macOS animates it to the Dock.
    case minimiseInView

    public var method: ParkingMethod { .minimised }
}

/// How windows are put away and brought back without anything going down to the Dock.
///
/// Tuck parks windows off screen (`OffScreenParking`). A window that can't be parked that way is
/// minimised, and macOS animates every minimised window down to the Dock, with no public way to aim or
/// skip that animation. So Tuck briefly hides apps that can be hidden, minimises the chosen windows while
/// hidden, then shows the app again. This avoids the Dock animation without leaving an app hidden. If an
/// app cannot be hidden, its window is minimised in view instead.
public enum ParkingPolicy {
    public static func plan(visibleWindowCount: Int, tuckingCount: Int, appCanHide: Bool) -> ParkingPlan {
        guard appCanHide else { return .minimiseInView }
        return tuckingCount > 0 && tuckingCount >= visibleWindowCount ? .hideApp : .minimiseOutOfSight
    }

    public static func method(visibleWindowCount: Int, tuckingCount: Int, appCanHide: Bool) -> ParkingMethod {
        plan(visibleWindowCount: visibleWindowCount, tuckingCount: tuckingCount, appCanHide: appCanHide).method
    }

    /// Showing a hidden app shows every window it hid. Restoring one of several windows tucked by hiding
    /// their app would bring them all back, so the others are minimised first (while the app is still
    /// hidden, so nothing is seen moving) and stay tucked.
    public static func siblingsToKeepTucked(restoring window: ParkedWindow, among rows: [ParkedWindow]) -> [ParkedWindow] {
        guard window.isHiddenWithApp else { return [] }
        return rows.filter { $0.id != window.id && $0.isHiddenWithApp && $0.sharesApp(with: window) }
    }

    /// The window the fold names once windows have been tucked. If the window in front was one of them,
    /// or of their app, it has just been put away: the name goes blank rather than naming it (or the
    /// window behind it) a moment after it went. Tucking another app's windows leaves the name as it was.
    public static func frontWindow(_ front: FrontWindowInfo?, afterTucking tucked: [ParkedWindow]) -> FrontWindowInfo? {
        guard let front, !tucked.contains(where: { $0.app.isSameApp(as: front.app) }) else { return nil }
        return front
    }
}
