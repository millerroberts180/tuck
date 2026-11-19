import AppKit
import ApplicationServices
import TuckCore

/// Notices the person switching to another window, or putting one away themselves, without polling. App
/// switches and hides come from the workspace's notifications. Within the app in front, an Accessibility
/// observer on that app alone reports its focused window changing (⌘` between windows, a click on
/// another of its windows) and a window being minimised. It is re-made at each app switch. Each use runs
/// it only while needed: the parking service runs it while windows are parked off screen or the open
/// fold's Tuck button names a window. Browser tabs aren't windows, so switching tabs isn't seen as a
/// switch (with `watchesEdits` on, it is seen as a rename).
final class FrontWindowWatcher {
    enum Event: Equatable {
        /// Another window came to the front: an app switch, ⌘`, a click on another window.
        case switched
        /// A window was minimised or its app hidden.
        case putAway
    }

    /// Called on the main thread a beat after each switch or put-away, once the new window has focus. A
    /// burst (a hide brings another app forward; a minimise moves focus) is reported once, as a put-away
    /// if any part of it was one.
    var onEvent: ((Event) -> Void)?
    /// Called on the main thread after each burst `onEvent` is told of, and a beat after the focused
    /// window closes or changes its title while `watchesEdits` is on: the cue to read the front window
    /// again.
    var onChange: (() -> Void)?
    /// Whether the focused window closing or being renamed is noticed too. Only the Tuck button needs it,
    /// and only while the fold is open.
    var watchesEdits = false {
        didSet { if watchesEdits != oldValue { observeFocusedWindow() } }
    }
    private var workspaceObservers: [NSObjectProtocol] = []
    private var axObserver: AXObserver?
    private var observedApp: AXUIElement?
    private var observedWindow: AXUIElement?
    private var pending: DispatchWorkItem?
    private var pendingEvent: Event?
    private var pendingEdit: DispatchWorkItem?
    /// Whether the focused window closed during the edit waiting, so the window then focused is watched.
    private var closeWaiting = false

    private static let appNotifications = [kAXFocusedWindowChangedNotification, kAXWindowMiniaturizedNotification]
    private static let editNotifications = [kAXUIElementDestroyedNotification, kAXTitleChangedNotification]

    deinit { stop() }

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.observeWindows(of: app)
            self?.noticed(.switched)
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != getpid() else { return }
            self?.noticed(.putAway)
        })
        observeWindows(of: NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        stopObserving()
        pending?.cancel()
        pending = nil
        pendingEvent = nil
        pendingEdit?.cancel()
        pendingEdit = nil
    }

    /// Waits a moment, so the window that just came forward is the focused one when asked.
    private func noticed(_ event: Event) {
        if pendingEvent != .putAway { pendingEvent = event }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let event = self.pendingEvent else { return }
            self.pendingEvent = nil
            // The front is read again for this burst anyway, so a close or rename waiting is covered.
            self.pendingEdit?.cancel()
            self.pendingEdit = nil
            self.watchAfterClose()
            self.onEvent?(event)
            self.onChange?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// A close or rename waits until the window has been quiet for a moment, on a beat of its own, so a
    /// title that keeps changing (a progress count, a terminal's running command) is read once it settles
    /// and never holds back a switch.
    private func noticedEdit(closed: Bool) {
        if closed { closeWaiting = true }
        pendingEdit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingEdit = nil
            self.watchAfterClose()
            self.onChange?()
        }
        pendingEdit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// A close can be told before the app has moved focus on, so the window watched straight after it
    /// may be the closed one, or none, and the next window's renames and closes would go unseen. Once the
    /// close has settled, the focused window is read again and watched.
    private func watchAfterClose() {
        guard closeWaiting else { return }
        closeWaiting = false
        observeFocusedWindow()
    }

    private func observeWindows(of app: NSRunningApplication?) {
        stopObserving()
        guard AX.isTrusted, let app, app.processIdentifier != getpid(), app.activationPolicy == .regular else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FrontWindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
            switch notification as String {
            case kAXWindowMiniaturizedNotification:
                watcher.noticed(.putAway)
            case kAXUIElementDestroyedNotification, kAXTitleChangedNotification:
                // Only the focused window's own close or rename counts, not that of something inside it.
                guard let observed = watcher.observedWindow, CFEqual(element, observed) else { return }
                let closed = notification as String == kAXUIElementDestroyedNotification
                watcher.noticedEdit(closed: closed)
                // Watched again at once, in case focus has already moved on, and again once it settles.
                if closed { watcher.observeFocusedWindow() }
            default:
                watcher.noticed(.switched)
                watcher.observeFocusedWindow()
            }
        }
        guard AXObserverCreate(app.processIdentifier, callback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        observedApp = element
        observeFocusedWindow()
    }

    /// Minimising is reported on the window, so the focused one is watched too, in case the app's own
    /// element doesn't pass it on; it changes with focus. With `watchesEdits` on, so are its closing and
    /// its title.
    private func observeFocusedWindow() {
        guard let axObserver, let observedApp else { return }
        if let observedWindow { stopObservingWindow(observedWindow, with: axObserver) }
        observedWindow = AX.element(observedApp, kAXFocusedWindowAttribute)
        if let observedWindow {
            let names = [kAXWindowMiniaturizedNotification] + (watchesEdits ? Self.editNotifications : [])
            for name in names {
                AXObserverAddNotification(axObserver, observedWindow, name as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
            }
        }
    }

    /// Removes every notification a window may have been watched for; those it wasn't are simply refused.
    private func stopObservingWindow(_ window: AXUIElement, with observer: AXObserver) {
        for name in [kAXWindowMiniaturizedNotification] + Self.editNotifications {
            AXObserverRemoveNotification(observer, window, name as CFString)
        }
    }

    private func stopObserving() {
        if let axObserver {
            if let observedApp {
                for name in Self.appNotifications {
                    AXObserverRemoveNotification(axObserver, observedApp, name as CFString)
                }
            }
            if let observedWindow { stopObservingWindow(observedWindow, with: axObserver) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
        }
        axObserver = nil
        observedApp = nil
        observedWindow = nil
        closeWaiting = false
    }
}
