import AppKit
import ApplicationServices

/// Notices windows parked off screen being moved or resized, and Mission Control ending, without
/// polling. Each app with a parked window has one Accessibility observer, told when exactly those
/// windows move or change size: Tuck's own moves, and any other (an app resizing its window, or holding
/// it on screen once Mission Control lets it go). The Dock's observer reports Mission Control, App
/// Exposé and Show Desktop starting and ending, under names that are undocumented but long stable (window
/// managers such as yabai listen for the same). It runs only while windows are parked off screen.
final class ParkedWindowWatcher {
    /// Called on the main thread when a watched window moves or changes size.
    var onChange: ((AXUIElement) -> Void)?
    /// Called on the main thread when Mission Control, App Exposé or Show Desktop begins, and again on
    /// moving between them. While one shows, the Dock has the windows laid out, and they are left be.
    var onMissionControlStarted: (() -> Void)?
    /// Called on the main thread when Mission Control, App Exposé or Show Desktop ends.
    var onMissionControlEnded: (() -> Void)?

    private var watched: [AX.Window] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var dock: (pid: pid_t, observer: AXObserver, element: AXUIElement)?

    private static let windowNotifications = [kAXWindowMovedNotification, kAXWindowResizedNotification]
    private static let missionControlShown = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows", "AXExposeShowDesktop"]
    private static let missionControlEnded = "AXExposeExit"

    deinit { watch([]) }

    /// Watches exactly these windows from now on; with none, everything stops.
    func watch(_ windows: [AX.Window]) {
        for window in watched where !windows.contains(where: { CFEqual($0.element, window.element) }) {
            guard let observer = observers[window.pid] else { continue }
            for name in Self.windowNotifications {
                AXObserverRemoveNotification(observer, window.element, name as CFString)
            }
        }
        watched.removeAll { window in !windows.contains { CFEqual($0.element, window.element) } }
        for window in windows where !watched.contains(where: { CFEqual($0.element, window.element) }) {
            guard let observer = observer(for: window.pid) else { continue }
            for name in Self.windowNotifications {
                AXObserverAddNotification(observer, window.element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
            watched.append(window)
        }
        for (pid, observer) in observers where !watched.contains(where: { $0.pid == pid }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = nil
        }
        if watched.isEmpty { stopWatchingDock() } else { watchDock() }
    }

    private func observer(for pid: pid_t) -> AXObserver? {
        if let observer = observers[pid] { return observer }
        guard let observer = Self.makeObserver(pid) else { return nil }
        observers[pid] = observer
        return observer
    }

    /// Made again if the Dock has restarted since, so Mission Control is never missed.
    private func watchDock() {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?
            .processIdentifier, dock?.pid != pid else { return }
        stopWatchingDock()
        guard let observer = Self.makeObserver(pid) else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.missionControlShown + [Self.missionControlEnded] {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        dock = (pid, observer, element)
    }

    private func stopWatchingDock() {
        guard let dock else { return }
        for name in Self.missionControlShown + [Self.missionControlEnded] {
            AXObserverRemoveNotification(dock.observer, dock.element, name as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(dock.observer), .defaultMode)
        self.dock = nil
    }

    private func received(_ notification: String, on element: AXUIElement) {
        if Self.missionControlShown.contains(notification) {
            onMissionControlStarted?()
        } else if notification == Self.missionControlEnded {
            onMissionControlEnded?()
        } else {
            onChange?(element)
        }
    }

    private static func makeObserver(_ pid: pid_t) -> AXObserver? {
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<ParkedWindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
            watcher.received(notification as String, on: element)
        }
        var observer: AXObserver?
        guard AX.isTrusted, AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        return observer
    }
}
