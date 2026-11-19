import AppKit
import ApplicationServices

/// Notices windows listed in the open Suggested picker closing, or their apps quitting, without polling,
/// so the picker drops them at once. Each listed app has one Accessibility observer, told when exactly
/// those windows are destroyed (a dozen at most, `CandidatePolicy.limit`). A quit app reports nothing, so
/// quitting comes from the workspace's notification. It runs only while the picker is open.
final class ListedWindowWatcher {
    /// Called on the main thread when a watched window closes or the app of one quits.
    var onChange: (() -> Void)?

    private var watched: [AX.Window] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var terminationObserver: NSObjectProtocol?

    deinit { watch([]) }

    /// Watches exactly these windows from now on; with none, everything stops.
    func watch(_ windows: [AX.Window]) {
        stop()
        guard !windows.isEmpty else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for window in windows {
            guard let observer = observer(for: window.pid) else { continue }
            AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString, refcon)
        }
        watched = windows
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // Only a listed app's quitting matters; any other app may come and go.
            guard let self, let pid = app?.processIdentifier, self.watched.contains(where: { $0.pid == pid }) else { return }
            self.onChange?()
        }
    }

    private func stop() {
        for window in watched {
            guard let observer = observers[window.pid] else { continue }
            AXObserverRemoveNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString)
        }
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        watched = []
        observers = [:]
        if let terminationObserver { NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver) }
        terminationObserver = nil
    }

    private func observer(for pid: pid_t) -> AXObserver? {
        if let observer = observers[pid] { return observer }
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<ListedWindowWatcher>.fromOpaque(refcon).takeUnretainedValue().onChange?()
        }
        var observer: AXObserver?
        guard AX.isTrusted, AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        return observer
    }
}
