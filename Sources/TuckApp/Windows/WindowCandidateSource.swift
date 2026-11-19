import AppKit
import TuckCore

/// Gathers open windows for the Suggested picker: what Accessibility says about each window of the
/// apps that have windows on screen, matched against the window server's on-screen list for position
/// and front-to-back order. The on-screen list is read for bounds and owners only (no titles, no
/// pixels), so no Screen Recording permission is involved. Which windows are offered is decided by
/// `CandidatePolicy`; this only reports facts.
enum WindowCandidateSource {
    static func collect(skippingBundleIDs skipped: Set<String>) -> (candidates: [WindowCandidate], elements: [String: AX.Window]) {
        let onScreen = onScreenWindows()
        let pids = Set(onScreen.map(\.pid))
        var candidates: [WindowCandidate] = []
        var elements: [String: AX.Window] = [:]
        // Tuck is never asked about itself (that would wait on its own main thread), and resting apps
        // are never asked at all: a paused process cannot answer.
        for app in NSWorkspace.shared.runningApplications where pids.contains(app.processIdentifier)
            && app.processIdentifier != getpid() && !skipped.contains(app.bundleIdentifier ?? "") {
            let pid = app.processIdentifier
            let axApp = AX.application(pid)
            let identity = AppIdentity(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? "App")
            for element in AX.elements(axApp, kAXWindowsAttribute) {
                guard let quartz = AX.frame(of: element) else { continue }
                let match = onScreen.filter { $0.pid == pid && close($0.bounds, quartz) }.min { $0.order < $1.order }
                let frame = Displays.appKit(quartz)
                let screen = Displays.screen(for: frame)
                let id = "\(pid):\(CFHash(element))"
                candidates.append(WindowCandidate(
                    id: id,
                    app: identity,
                    pid: pid,
                    title: AX.title(of: element),
                    frame: frame,
                    displayID: screen.map { String($0.displayID) },
                    displayName: screen?.localizedName,
                    subrole: AX.string(element, kAXSubroleAttribute),
                    isMinimised: AX.bool(element, kAXMinimizedAttribute) ?? false,
                    isFullScreen: AX.bool(element, "AXFullScreen") ?? false,
                    // The window server lists a window parked off screen as on screen; only a sliver shows.
                    isOnScreen: match != nil && !Displays.isOutOfSight(quartz),
                    isRegularApp: app.activationPolicy == .regular,
                    isOwnApp: false,
                    isAppResting: false,
                    stackOrder: match?.order ?? Int.max
                ))
                elements[id] = AX.Window(element: element, app: axApp, pid: pid)
            }
        }
        return (candidates, elements)
    }

    /// Ordinary (layer 0) windows on screen now, front to back, in Quartz coordinates. Windows parked off
    /// screen are among them, and a window moved a moment ago can still be listed where it was.
    static func onScreenWindows() -> [(pid: pid_t, bounds: CGRect, order: Int)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.enumerated().compactMap { index, entry in
            guard entry[kCGWindowLayer as String] as? Int == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return nil }
            return (pid, bounds, index)
        }
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}
