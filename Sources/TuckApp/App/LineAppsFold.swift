import AppKit

/// Line Apps puts a short line in the menu bar that collapses the family's icons into itself and
/// brings them back. It says so with a distributed notification, and this hides or shows one app's
/// icon to match, fading it as it goes, the nearer the line the sooner.
///
/// Collapsed holds only while Line Apps runs: an app that opens while Line Apps is closed shows its
/// icon, and one that is hidden shows it again if Line Apps quits, so no icon is left out of reach.
/// Nothing runs between changes: three notification observers, and a fourth only while collapsed.
///
/// A hidden icon loses its place: the menu bar forgets where a hidden item was and puts it back at
/// the far end. So the place is noted as the icon goes, in the menu bar's own terms, and handed back
/// just before it shows again, which puts it where it was.
///
/// The same file is in Tuck, Pulse, Hum and Glow; the copy in the line-apps repository
/// (Shared/LineAppsFold.swift) is the one to change first.
@MainActor
final class LineAppsFold {
    static let lineBundleID = "com.millerroberts.lineapps"
    static let foldName = Notification.Name("com.millerroberts.lineapps.fold")
    static let unfoldName = Notification.Name("com.millerroberts.lineapps.unfold")

    /// Whether the icon is collapsed into the line now.
    private(set) var isFolded = false
    /// Hides the icon (true) or shows it (false).
    private let setHidden: (Bool) -> Void
    /// The icon's button, to fade and to measure from the line.
    private let button: () -> NSStatusBarButton?
    /// The status item's autosave name, under which the menu bar keeps its place.
    private let name: () -> String?
    private var observers: [NSObjectProtocol] = []
    private var lineQuit: NSObjectProtocol?
    /// How long this icon waits after the line moves: longer the farther it sits from the line.
    private var delay: TimeInterval = 0
    /// Where the icon sat before it was hidden, as the menu bar records it: points from the right
    /// edge of the screen to the icon's left edge.
    private var place: Double?
    /// Counts changes, so a fade overtaken by the next change doesn't finish.
    private var change = 0

    init(setHidden: @escaping (Bool) -> Void, button: @escaping () -> NSStatusBarButton?, name: @escaping () -> String?) {
        self.setHidden = setHidden
        self.button = button
        self.name = name
    }

    /// Starts listening, and hides the icon at once if the line has the apps collapsed. Call it once
    /// the icon exists.
    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        for (name, folded) in [(Self.foldName, true), (Self.unfoldName, false)] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let lineX = note.userInfo?["x"] as? Double
                MainActor.assumeIsolated { self?.fold(folded, lineX: lineX, animated: true) }
            })
        }
        // Quitting while collapsed leaves the icon as it was, so it opens where it was next time.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isFolded == true { self?.handBackPlace() } }
        })
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.lineBundleID).isEmpty
        if running, UserDefaults(suiteName: Self.lineBundleID)?.bool(forKey: "folded") == true {
            fold(true, lineX: nil, animated: false)
        } else if let name = name(), UserDefaults.standard.object(forKey: Self.visibleKey(name)) as? Bool == false {
            // Left hidden by a quit that never said so; the line isn't holding it, so it shows.
            handBackPlace()
            setHidden(false)
        }
    }

    private func fold(_ folded: Bool, lineX: Double?, animated: Bool) {
        guard folded != isFolded else { return }
        isFolded = folded
        change += 1
        watchForLineQuitting(folded)
        if folded {
            notePlace(laidOut: animated)
            delay = 0
            if let lineX, let frame = button()?.window?.frame {
                delay = min(abs(frame.midX - lineX) / 900, 0.24)
            }
        }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            if !folded { handBackPlace() }
            return setHidden(folded)
        }
        let current = change
        Task { @MainActor [weak self, delay] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            self?.fade(folded, change: current)
        }
    }

    /// Fades the icon out and then takes it away, or puts it back and fades it in.
    private func fade(_ folded: Bool, change current: Int) {
        guard current == change else { return }
        let duration = 0.16
        if folded {
            guard let button = button() else { return setHidden(true) }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                button.animator().alphaValue = 0
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard let self, current == self.change else { return }
                self.setHidden(true)
                self.button()?.alphaValue = 1
            }
        } else {
            button()?.alphaValue = 0
            handBackPlace()
            setHidden(false)
            // An icon made anew as it comes back (Glow's) has its button a moment later.
            Task { @MainActor [weak self] in
                guard let self, current == self.change, let button = self.button() else { return }
                button.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    button.animator().alphaValue = 1
                }
            }
        }
    }

    // MARK: Place

    private static func placeKey(_ name: String) -> String { "NSStatusItem Preferred Position \(name)" }
    private static func visibleKey(_ name: String) -> String { "NSStatusItem Visible \(name)" }

    /// Forgets that the icon was left hidden, before it is made. For an icon SwiftUI makes (Glow's),
    /// which reads that as it opens, before `start()` could show it.
    static func forgetHidden(name: String) {
        UserDefaults.standard.removeObject(forKey: visibleKey(name))
    }

    /// Notes where the icon is before it goes. One collapsed as the app opens isn't laid out yet, so
    /// it keeps the place the menu bar made it at.
    private func notePlace(laidOut: Bool) {
        if laidOut, let window = button()?.window, let screen = window.screen ?? NSScreen.screens.first {
            place = Double(screen.frame.maxX - window.frame.minX)
        } else if let name = name() {
            place = UserDefaults.standard.object(forKey: Self.placeKey(name)) as? Double
        }
    }

    /// Gives the menu bar the icon's place back, and forgets that it was hidden: an icon made anew
    /// (Glow's) would otherwise read that and stay hidden.
    private func handBackPlace() {
        guard let name = name() else { return }
        let defaults = UserDefaults.standard
        if let place { defaults.set(place, forKey: Self.placeKey(name)) }
        defaults.removeObject(forKey: Self.visibleKey(name))
    }

    /// While collapsed, Line Apps quitting, even without a word, brings the icon back.
    private func watchForLineQuitting(_ folded: Bool) {
        if !folded, let lineQuit {
            NSWorkspace.shared.notificationCenter.removeObserver(lineQuit)
            self.lineQuit = nil
        } else if folded, lineQuit == nil {
            lineQuit = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let quitting = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
                MainActor.assumeIsolated {
                    if quitting == LineAppsFold.lineBundleID { self?.fold(false, lineX: nil, animated: true) }
                }
            }
        }
    }
}
