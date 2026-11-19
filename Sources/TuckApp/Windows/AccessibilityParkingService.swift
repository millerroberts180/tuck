import AppKit
import os
import TuckCore

/// Real window parking and placement through the Accessibility API, in-process.
///
/// Parking moves a window just beyond a bottom corner of a display (`OffScreenParking`), the way the
/// AeroSpace window manager keeps other workspaces' windows: at once, with no system animation, and only
/// once Tuck's card is on screen over it (`moveOutOfSight`), so the window is simply gone as the card
/// takes its place. The keyboard then goes where it would have gone had the window been minimised. A
/// window that can't be moved there (full screen, or held in view by its app) is minimised instead, its
/// app hidden for that moment so the Dock's animation isn't seen. Restoring sets a window parked off
/// screen straight back; a minimised one is un-minimised and raised, then its frame is checked once it
/// is back and re-anchored if the app kept a size of its own. While parked, a window is watched, so one
/// brought back into view by something other than the person (its app, Mission Control ending) goes
/// out of sight again. Leaving Mission Control brings one back only if the person chose it there.
final class AccessibilityParkingService: WindowParkingService {
    /// Why a window stopped being tucked without the person restoring it from Tuck, and what Mission
    /// Control left, for `log stream`. Info and debug only, so nothing is kept unless someone collects it.
    /// The subsystem is the bundle ID, so it follows Support/release.env; `swift run` has no bundle.
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Tuck", category: "parking")
    private static let dockBundleID = "com.apple.dock"

    /// Elements for windows parked during this run. After a relaunch Tuck finds them again by title.
    private var parked: [UUID: AX.Window] = [:]
    /// Windows parked off screen, by row. Watching for the person going to one of them, and for displays
    /// changing, runs only while there are any; each is watched for moving once it has gone.
    private var offScreen: [UUID: OffScreenWindow] = [:] {
        didSet {
            if offScreen.isEmpty != oldValue.isEmpty { updateWatching() }
            parkedWatcher.watch(offScreen.values.filter(\.hasMoved).map(\.window))
        }
    }
    private var history = PlacementHistory()
    /// Elements behind the most recent window listing, so a choice made from it parks exactly those.
    private var candidateElements: [String: AX.Window] = [:]
    /// The window `frontWindow()` last named, so the bar's Tuck and Arrange reach exactly that one.
    private var frontTarget: AX.Window?
    /// Told when the window in front changes, while the open panel's bar names it.
    private var onFrontWindowChange: ((FrontWindowInfo?, Bool) -> Void)?
    /// Where Tuck's own moves are about to bring the front, so the bar can tell them from the person's.
    private var ownFrontChanges = OwnFrontChanges()
    /// Apps Tuck is resting; their windows are never listed or touched.
    var restingBundleIDs: () -> Set<String> = { [] }
    /// Told when windows meant to wait off screen ended up otherwise.
    var onParkingChanged: ((ParkingChange) -> Void)?
    /// Told when the person goes to a window parked off screen (its app's Dock icon, the app switcher),
    /// so it comes back instead of taking the keyboard out of sight.
    var onParkedWindowFocused: ((UUID) -> Void)?

    /// A window parked off screen: where it was, and whether it has gone yet (it waits in place until its
    /// card covers it).
    private struct OffScreenWindow {
        let window: AX.Window
        /// The display it was on, whose corner it waits beyond.
        let displayID: String?
        /// Its frame before it went (Quartz), so it is never picked to take the keyboard as it leaves.
        let frame: CGRect
        var hasMoved = false
        /// When (system uptime) it was parked again after coming back into view by itself.
        var parkedAgain: [TimeInterval] = []
    }

    /// What became of windows meant to wait off screen, when it isn't what was planned.
    struct ParkingChange {
        /// Minimised instead: they couldn't be moved out of sight, or kept there.
        var minimised: Set<UUID> = []
        /// Still in view: they couldn't be put away at all, so their rows go.
        var refused: Set<UUID> = []
        /// Brought back into view by the person some other way, so their rows go.
        var broughtBack: Set<UUID> = []
    }

    private let focusWatcher = FrontWindowWatcher()
    private let parkedWatcher = ParkedWindowWatcher()
    private let listedWatcher = ListedWindowWatcher()
    private var screenObserver: NSObjectProtocol?
    private var pendingScreenCheck: DispatchWorkItem?
    /// Parked windows that moved by themselves, looked at together once they have settled.
    private var drifted: Set<UUID> = []
    private var pendingDriftCheck: DispatchWorkItem?
    /// Mission Control, App Exposé or Show Desktop: what was in front as it began, and whether what it
    /// left is still its doing.
    private var missionControl = MissionControlVisit()
    /// The look at everything Mission Control left, once its exit has settled.
    private var pendingMissionControlCheck: DispatchWorkItem?
    /// The app in front when focus last changed, to tell going to another app from a change within one.
    private var lastFrontPID: pid_t?
    /// Until when (system uptime) the keyboard landing on a parked window may be Tuck's own doing, from
    /// moving or minimising windows, rather than the person's. (The bar asks `ownFrontChanges`, which
    /// also knows where Tuck's move was meant to land.)
    private var ownChangesUntil: TimeInterval = 0

    /// Tuck has just moved windows or the keyboard. The watcher reports a switch 0.2 s after it, and a
    /// minimise may put its app back in front 0.1 s later still, so half a second covers both.
    private func noteOwnChange() {
        ownChangesUntil = ProcessInfo.processInfo.systemUptime + 0.5
    }

    init() {
        focusWatcher.onEvent = { [weak self] _ in
            guard let self, !self.offScreen.isEmpty else { return }
            self.frontWindowChanged()
        }
        // After any keyboard landing on a parked window has been seen to, so the bar reads where it went.
        focusWatcher.onChange = { [weak self] in
            guard let self, let onFrontWindowChange = self.onFrontWindowChange else { return }
            let read = self.readFront()
            let byPerson = self.ownFrontChanges.changed(to: read.landing, at: ProcessInfo.processInfo.systemUptime)
            onFrontWindowChange(read.front, byPerson)
        }
        parkedWatcher.onChange = { [weak self] element in self?.parkedWindowChanged(element) }
        parkedWatcher.onMissionControlStarted = { [weak self] in self?.missionControlStarted() }
        parkedWatcher.onMissionControlEnded = { [weak self] in self?.missionControlEnded() }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    func windowCandidates() -> [WindowCandidate] {
        guard AX.isTrusted else {
            candidateElements = [:]
            return []
        }
        let collected = WindowCandidateSource.collect(skippingBundleIDs: restingBundleIDs())
        candidateElements = collected.elements
        return collected.candidates
    }

    func stillListed(_ candidates: [WindowCandidate]) -> [WindowCandidate] {
        guard AX.isTrusted else { return [] }
        return candidates.filter { candidate in
            // A quit app's window can't answer and reads as busy, not closed, so quitting is asked first.
            guard let window = candidateElements[candidate.id], Self.isRunning(window.pid), !isResting(window.pid)
            else { return false }
            // A busy app's window stays listed: it may answer by the time it is tucked, which checks again.
            return AX.state(of: window.element) != .destroyed && !isAlreadyTucked(window)
        }
    }

    func watchListedWindows(_ candidates: [WindowCandidate], onChange: (() -> Void)?) {
        listedWatcher.onChange = onChange
        listedWatcher.watch(onChange == nil ? [] : candidates.compactMap { candidateElements[$0.id] })
    }

    /// Parks exactly the chosen windows. Each is checked again first: still there, still not tucked.
    func park(_ candidates: [WindowCandidate]) -> [ParkResult] {
        guard AX.isTrusted else {
            AX.promptForTrust()
            return candidates.map { _ in .needsPermission }
        }
        // The listing's elements are only needed for this choice; let go of them afterwards.
        defer { candidateElements = [:] }
        var results: [ParkResult?] = Array(repeating: nil, count: candidates.count)
        var chosen: [pid_t: [(index: Int, window: AX.Window)]] = [:]
        for (index, candidate) in candidates.enumerated() {
            guard let window = candidateElements[candidate.id], AX.state(of: window.element) == .alive else {
                results[index] = .noWindow
                continue
            }
            // Tucked meanwhile (by a shortcut, say): already where it was meant to go.
            if isAlreadyTucked(window) {
                results[index] = .alreadyTucked
                continue
            }
            chosen[window.pid, default: []].append((index, window))
        }
        // One app at a time, so an app whose every visible window must be minimised is hidden once.
        for (_, picks) in chosen {
            for (offset, result) in park(picks.map(\.window)).enumerated() { results[picks[offset].index] = result }
        }
        return results.map { $0 ?? .noWindow }
    }

    /// The window in front, or nothing when no window is there to act on: the app in front is hidden or
    /// has no window open, or its window was just tucked and is still on its way.
    func frontWindow() -> FrontWindowInfo? {
        let read = readFront()
        ownFrontChanges.read(read.landing)
        return read.front
    }

    /// The window in front as `frontWindow()` names it, and where the front is for telling Tuck's own
    /// changes from the person's: the app in front, and its focused window even when that is tucked.
    private func readFront() -> (front: FrontWindowInfo?, landing: OwnFrontChanges.Landing?) {
        frontTarget = nil
        guard let running = NSWorkspace.shared.frontmostApplication else { return (nil, nil) }
        let pid = running.processIdentifier
        guard pid != getpid(), running.activationPolicy == .regular, !running.isHidden else {
            return (nil, OwnFrontChanges.Landing(pid: pid))
        }
        let app = AppIdentity(bundleID: running.bundleIdentifier ?? "", name: running.localizedName ?? "App")
        // Without Accessibility no window can be read; the bar still names the app and explains why.
        guard AX.isTrusted else { return (FrontWindowInfo(app: app, title: ""), OwnFrontChanges.Landing(pid: pid)) }
        // A resting app is paused and can't answer. The window is read from the app just named, never from
        // the front again: focus moving in between would otherwise pair one app's name with another's window.
        guard !isResting(pid), let window = AX.focusedWindow(of: pid) else { return (nil, OwnFrontChanges.Landing(pid: pid)) }
        let landing = OwnFrontChanges.Landing(pid: pid, window: Self.token(for: window))
        // A tucked window is never offered again.
        guard !isAlreadyTucked(window) else { return (nil, landing) }
        frontTarget = window
        return (FrontWindowInfo(app: app, title: AX.title(of: window.element), window: landing.window), landing)
    }

    /// Tuck is about to bring this app forward, or exactly this window of it.
    private func expectFront(_ pid: pid_t, window: AX.Window? = nil) {
        ownFrontChanges.expect(OwnFrontChanges.Landing(pid: pid, window: window.map(Self.token)),
                               at: ProcessInfo.processInfo.systemUptime)
    }

    private static func token(for window: AX.Window) -> WindowToken { WindowToken(window.key) }

    /// The window a token names, if it is the one `frontWindow()` last named and its app isn't resting.
    private func held(_ token: WindowToken?) -> AX.Window? {
        guard let frontTarget, let token, Self.token(for: frontTarget) == token, !isResting(frontTarget.pid) else { return nil }
        return frontTarget
    }

    func check(_ window: WindowToken?) -> ShownWindowCheck {
        guard AX.isTrusted else {
            AX.promptForTrust()
            return .needsPermission
        }
        guard let target = held(window) else {
            // Still the window named, but its app is resting: put away by Tuck, and never touched.
            if let frontTarget, window == Self.token(for: frontTarget) { return .putAway }
            return .stale
        }
        return ShownWindowCheck.classify(appRunning: Self.isRunning(target.pid), state: AX.state(of: target.element),
                                         isPutAway: self.isAlreadyTucked(target))
    }

    func park(_ window: WindowToken) -> ParkResult {
        guard AX.isTrusted else {
            AX.promptForTrust()
            return .needsPermission
        }
        guard let target = held(window), AX.state(of: target.element) == .alive else { return .noWindow }
        guard !isAlreadyTucked(target) else { return .alreadyTucked }
        return park([target])[0]
    }

    func watchFrontWindow(_ onChange: ((FrontWindowInfo?, Bool) -> Void)?) {
        onFrontWindowChange = onChange
        focusWatcher.watchesEdits = onChange != nil
        if onChange != nil {
            focusWatcher.start()
        } else {
            frontTarget = nil
            if offScreen.isEmpty { focusWatcher.stop() }
        }
    }

    /// The focused window at this moment, for the shortcut, the menu and the notch.
    func parkFrontWindow() -> ParkResult {
        guard AX.isTrusted else {
            AX.promptForTrust()
            return .needsPermission
        }
        guard let window = AX.focusedWindow() else { return .noWindow }
        // Tucking twice in quick succession (a double click, a repeated shortcut) finds the same window
        // still focused while it goes. It is already tucked: never add a second row for it.
        guard !isAlreadyTucked(window) else { return .alreadyTucked }
        return park([window])[0]
    }

    /// Records each window's app, title, frame and display. A window that can wait off screen is only
    /// marked for it here, and stays where it is until its card covers it (`moveOutOfSight`); the others
    /// are minimised now. Nothing is recorded for a window that can't be read or put away.
    private func park(_ windows: [AX.Window]) -> [ParkResult] {
        guard let first = windows.first else { return [] }
        let running = NSRunningApplication(processIdentifier: first.pid)
        let frames = windows.map { AX.frame(of: $0.element) }
        let records: [ParkedWindow?] = zip(windows, frames).map { window, quartz in
            guard let quartz else { return nil }
            let frame = Displays.appKit(quartz)
            let screen = Displays.screen(for: frame)
            return ParkedWindow(
                app: AppIdentity(bundleID: running?.bundleIdentifier ?? "", name: running?.localizedName ?? "App"),
                title: AX.title(of: window.element),
                originalFrame: WindowFrame(frame),
                displayID: screen.map { String($0.displayID) },
                displayName: screen?.localizedName
            )
        }
        var results: [ParkResult] = Array(repeating: .noWindow, count: windows.count)
        var minimisingNow: [Int] = []
        for index in windows.indices {
            guard var record = records[index], let frame = frames[index] else { continue }
            if canWaitOffScreen(windows[index], size: frame.size, displayID: record.displayID) {
                record.method = .offScreen
                parked[record.id] = windows[index]
                offScreen[record.id] = OffScreenWindow(window: windows[index], displayID: record.displayID, frame: frame)
                results[index] = .parked(record)
            } else {
                minimisingNow.append(index)
            }
        }
        let minimised = minimise(minimisingNow.map { windows[$0] })
        for (index, done) in zip(minimisingNow, minimised) {
            guard var record = records[index] else { continue }
            guard done else {
                results[index] = .failed
                continue
            }
            record.method = .minimised
            parked[record.id] = windows[index]
            results[index] = .parked(record)
        }
        return results
    }

    /// Whether a window can wait off screen: not full screen (a full-screen window has a Space of its
    /// own and can't be moved), its position open to change, and some display with a corner free for it.
    private func canWaitOffScreen(_ window: AX.Window, size: CGSize, displayID: String?) -> Bool {
        AX.bool(window.element, "AXFullScreen") != true
            && AX.isSettable(window.element, kAXPositionAttribute)
            && OffScreenParking.origin(for: size, preferring: Displays.quartzFrame(ofDisplay: displayID),
                                       displays: Displays.quartzFrames) != nil
    }

    func moveOutOfSight(_ ids: Set<UUID>) {
        let due = ids.filter { offScreen[$0]?.hasMoved == false }
        guard !due.isEmpty else { return }
        guard AX.isTrusted else { return fallBack(Array(due)) }
        defer { noteOwnChange() }
        var moved: [UUID] = []
        var refused: [UUID] = []
        for id in due {
            guard let entry = offScreen[id] else { continue }
            if moveBeyondCorner(entry) {
                offScreen[id]?.hasMoved = true
                moved.append(id)
            } else {
                refused.append(id)
            }
        }
        if !refused.isEmpty { fallBack(refused) }
        guard !moved.isEmpty else { return }
        handOffKeyboard(from: moved)
        // An app can pull a window back a moment after letting it go; it is looked at once more then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.keepOutOfSight(Set(moved)) }
    }

    /// Moves a window beyond a corner of its display (or of another, when other displays lie beyond both
    /// of its own), and reads back where the app let it go.
    private func moveBeyondCorner(_ entry: OffScreenWindow) -> Bool {
        let displays = Displays.quartzFrames
        guard let size = AX.frame(of: entry.window.element)?.size,
              let origin = OffScreenParking.origin(for: size, preferring: Displays.quartzFrame(ofDisplay: entry.displayID),
                                                   displays: displays) else { return false }
        AX.move(entry.window, to: origin)
        guard let frame = AX.frame(of: entry.window.element) else { return false }
        return OffScreenParking.isOutOfSight(frame, displays: displays)
    }

    /// Minimises windows that couldn't be moved out of sight or kept there, one app at a time. One that
    /// can't be minimised either goes back where it was, and its row goes.
    private func fallBack(_ ids: [UUID]) {
        var change = ParkingChange()
        let entries = ids.compactMap { id in offScreen[id].map { (id: id, entry: $0) } }
        for (_, group) in Dictionary(grouping: entries, by: { $0.entry.window.pid }) {
            for ((id, entry), done) in zip(group, minimise(group.map(\.entry.window))) {
                offScreen[id] = nil
                if done {
                    Self.log.debug("Minimised \(Self.bundleID(of: entry.window), privacy: .public) instead: it couldn't be kept out of sight")
                    change.minimised.insert(id)
                } else {
                    logUntucked(entry.window, "couldn't be kept out of sight or minimised, so put back where it was (refused)")
                    parked[id] = nil
                    AX.move(entry.window, to: entry.frame.origin)
                    change.refused.insert(id)
                }
            }
        }
        if !change.minimised.isEmpty || !change.refused.isEmpty { onParkingChanged?(change) }
    }

    /// Checks that windows parked off screen are still there: an app may pull a window back a moment
    /// after it went, and a display going or changing can leave one in view, or with nothing left on any
    /// display (which macOS soon pulls back into view). Those are moved again, or minimised if that fails.
    /// For windows that moved by themselves (`drifted`), `OffScreenParking.drift` decides: one the person
    /// has in front is left to them, and one pulled back again and again is minimised. Around Mission
    /// Control nothing is judged or fallen back from here: what it leaves is looked at all together by
    /// `missionControlSettled` instead.
    private func keepOutOfSight(_ ids: Set<UUID>, drifted: Bool = false) {
        guard AX.isTrusted else { return }
        if missionControl.isUnderway(at: ProcessInfo.processInfo.systemUptime) { return settleAfterMissionControl() }
        let displays = Displays.quartzFrames
        let now = ProcessInfo.processInfo.systemUptime
        var change = ParkingChange()
        var refused: [UUID] = []
        for id in ids {
            guard let entry = offScreen[id], entry.hasMoved, !isResting(entry.window.pid) else { continue }
            let state = parkedState(of: entry)
            guard case .at(let frame) = state else {
                seeTo(id, entry, state, change: &change)
                continue
            }
            guard !OffScreenParking.isParked(frame, displays: displays) else { continue }
            if drifted {
                switch OffScreenParking.drift(of: frame, displays: displays, inFront: isInFront(entry.window),
                                              parkedAgain: entry.parkedAgain, now: now) {
                case .stays, .bringBack:
                    Self.log.debug("Left a parked \(Self.bundleID(of: entry.window), privacy: .public) window in view: the person has it in front, or no display can be read")
                    continue
                case .minimise:
                    refused.append(id)
                    continue
                case .parkAgain:
                    offScreen[id]?.parkedAgain = entry.parkedAgain.filter { now - $0 < OffScreenParking.pullBackSpan } + [now]
                }
            }
            if !moveBeyondCorner(entry) { refused.append(id) }
        }
        if !change.minimised.isEmpty { onParkingChanged?(change) }
        if !refused.isEmpty { fallBack(refused) }
    }

    /// What a parked window is now, from asking it.
    private enum ParkedState {
        case closed
        /// It didn't answer, or its frame couldn't be read.
        case busy
        /// Minimised some other way.
        case minimised
        case at(CGRect)
    }

    private func parkedState(of entry: OffScreenWindow) -> ParkedState {
        switch AX.state(of: entry.window.element) {
        case .destroyed: return .closed
        case .unresponsive: return .busy
        case .alive: break
        }
        if AX.bool(entry.window.element, kAXMinimizedAttribute) == true { return .minimised }
        return AX.frame(of: entry.window.element).map(ParkedState.at) ?? .busy
    }

    /// A parked window that is no longer simply waiting off screen. A closed one has nothing left to keep,
    /// and its row goes when it is next restored. One minimised some other way is still tucked, now in
    /// the Dock. A busy one is left as it is, to be looked at again.
    private func seeTo(_ id: UUID, _ entry: OffScreenWindow, _ state: ParkedState, change: inout ParkingChange) {
        switch state {
        case .closed:
            logUntucked(entry.window, "closed while tucked, so no longer watched (its row goes when next restored)")
            offScreen[id] = nil
        case .minimised:
            offScreen[id] = nil
            change.minimised.insert(id)
        case .busy, .at:
            break
        }
    }

    /// Whether the person has this window in front: its app active, and the window its focused one. The
    /// app itself is asked, so a click that has just brought the window forward counts at once.
    private func isInFront(_ window: AX.Window) -> Bool {
        AX.bool(window.app, kAXFrontmostAttribute) == true
            && AX.element(window.app, kAXFocusedWindowAttribute).map { CFEqual($0, window.element) } == true
    }

    /// A parked window moved or changed size: Tuck's own moves, or something bringing it back into view
    /// while it is still tucked (its app resizing it, or holding it on screen once Mission Control let it
    /// go). While Mission Control shows, the Dock has the windows and nothing moves them, so a move then
    /// means it has ended, or is ending, without the Dock saying so: everything it left is looked at once
    /// that has settled.
    private func parkedWindowChanged(_ element: AXUIElement) {
        guard let id = offScreen.first(where: { CFEqual($0.value.window.element, element) })?.key else { return }
        guard !missionControl.isShowing else {
            Self.log.debug("A parked window moved while Mission Control showed; taking it to have ended")
            return missionControlEnded(assumed: true)
        }
        noticeDrift([id])
    }

    /// Windows that moved by themselves are looked at together 0.2 s after the last move, once their app
    /// has settled them (a resize and a move, an animated frame). During a display change they are left
    /// to `displaysChanged`, as before. Until Mission Control's exit has settled, a move only puts off the
    /// look at everything it left (`settleAfterMissionControl`).
    private func noticeDrift(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if missionControl.isUnderway(at: ProcessInfo.processInfo.systemUptime) { return settleAfterMissionControl() }
        drifted.formUnion(ids)
        pendingDriftCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let ids = self.drifted
            self.drifted = []
            self.pendingDriftCheck = nil
            // Mission Control began meanwhile: once it ends, every parked window is looked at.
            guard self.pendingScreenCheck == nil,
                  !self.missionControl.isUnderway(at: ProcessInfo.processInfo.systemUptime) else { return }
            self.keepOutOfSight(ids, drifted: true)
        }
        pendingDriftCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Displays were added, removed or rearranged. Windows parked off screen are checked at once and
    /// once more a second later, after macOS has moved windows onto the displays that are left.
    private func displaysChanged() {
        keepOutOfSight(Set(offScreen.keys))
        pendingScreenCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingScreenCheck = nil
            self.keepOutOfSight(Set(self.offScreen.keys))
        }
        pendingScreenCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func updateWatching() {
        if offScreen.isEmpty {
            // The open panel's bar may still be following the window in front.
            if onFrontWindowChange == nil { focusWatcher.stop() }
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            pendingScreenCheck?.cancel()
            pendingScreenCheck = nil
            pendingDriftCheck?.cancel()
            pendingDriftCheck = nil
            drifted = []
            pendingMissionControlCheck?.cancel()
            pendingMissionControlCheck = nil
            missionControl = MissionControlVisit()
        } else {
            lastFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            focusWatcher.start()
            if screenObserver == nil {
                screenObserver = NotificationCenter.default.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
                ) { [weak self] _ in self?.displaysChanged() }
            }
        }
    }

    // MARK: The keyboard

    /// If the window with the keyboard has just gone off screen, the keyboard goes where a minimise would
    /// have sent it: to the app's frontmost other window in view, else to the frontmost window in view
    /// (and its app), else to the desktop.
    private func handOffKeyboard(from moved: [UUID]) {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return }
        let app = AX.application(front.processIdentifier)
        guard let focused = AX.element(app, kAXFocusedWindowAttribute) ?? AX.element(app, kAXMainWindowAttribute),
              moved.contains(where: { id in offScreen[id].map { CFEqual($0.window.element, focused) } ?? false })
        else { return }
        giveKeyboard(to: nextWindow(after: front.processIdentifier))
    }

    /// The window in view that takes the keyboard from one of this app's, as `OffScreenParking.successor`
    /// picks it from the window server's list, front to back.
    private func nextWindow(after pid: pid_t) -> OffScreenParking.ListedWindow? {
        let leaving = offScreen.values.map { OffScreenParking.ListedWindow(pid: $0.window.pid, frame: $0.frame) }
        let listed = WindowCandidateSource.onScreenWindows()
            .filter { $0.pid != getpid() && !isResting($0.pid) }
            .map { OffScreenParking.ListedWindow(pid: $0.pid, frame: $0.bounds) }
        return OffScreenParking.successor(to: pid, leaving: leaving, in: listed, displays: Displays.quartzFrames)
    }

    private func giveKeyboard(to next: OffScreenParking.ListedWindow?) {
        noteOwnChange()
        guard let next else {
            // Nothing else in view: the desktop takes the keyboard, as when the last window is hidden.
            if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                expectFront(finder.processIdentifier)
                AX.makeFrontmost(AX.application(finder.processIdentifier), pid: finder.processIdentifier)
            }
            return
        }
        let app = AX.application(next.pid)
        let element = AX.elements(app, kAXWindowsAttribute).first { element in
            AX.frame(of: element).map { Self.close($0, next.frame) } ?? false
        }
        if let element {
            let window = AX.Window(element: element, app: app, pid: next.pid)
            expectFront(next.pid, window: window)
            AX.focus(window)
            // Handed to another window of the same app, the keyboard can stay where it was, in the window
            // that has just gone off screen, if the app wouldn't move its focus.
            if let stuck = parkedWindow(focusedIn: next.pid) {
                Self.log.info("The keyboard stayed in a parked \(Self.bundleID(of: stuck), privacy: .public) window after it was handed on")
            }
        } else {
            expectFront(next.pid)
            AX.makeFrontmost(app, pid: next.pid)
        }
    }

    /// The keyboard moved while windows are parked off screen. If it went to one of them, the person
    /// either went to that app (its Dock icon, the app switcher, a link opened in it) and the window
    /// comes back, or the app passed it on by itself (its last window in view closed, ⌘` cycled past),
    /// and the keyboard goes on to a window in view instead. Either way nothing is typed out of sight.
    /// Around Mission Control nothing is judged here: see `missionControlSettled`.
    private func frontWindowChanged() {
        let front = NSWorkspace.shared.frontmostApplication
        // The Dock comes forward for Mission Control and Launchpad, not as an app the person went to: the
        // app in front before it still counts, so coming back to that isn't a switch.
        guard front?.bundleIdentifier != Self.dockBundleID else { return }
        if missionControl.isShowing {
            // Another app coming forward while Mission Control shows means it has ended, should the Dock not
            // say so.
            if front?.processIdentifier != missionControl.frontAtStart?.pid { missionControlEnded(assumed: true) }
            return
        }
        // Until its exit has settled, a change only puts off the look at everything it left.
        if missionControl.isUnderway(at: ProcessInfo.processInfo.systemUptime) { return settleAfterMissionControl() }
        let switchedApp = front?.processIdentifier != lastFrontPID
        lastFrontPID = front?.processIdentifier
        guard AX.isTrusted, let front, front.processIdentifier != getpid(), !isResting(front.processIdentifier) else { return }
        let pid = front.processIdentifier
        guard let focused = AX.element(AX.application(pid), kAXFocusedWindowAttribute),
              let match = offScreen.first(where: { CFEqual($0.value.window.element, focused) }),
              match.value.hasMoved else { return }
        let id = match.key
        let ownDoing = ProcessInfo.processInfo.systemUptime < ownChangesUntil
        if let frame = AX.frame(of: focused), !Displays.isOutOfSight(frame) {
            // Back in view. Moments after Tuck moved it, its app pulled it back, which `keepOutOfSight` is
            // about to see to; otherwise the person brought it back some other way, and it isn't tucked.
            guard !ownDoing else { return }
            logUntucked(match.value.window, "back in view with the keyboard in it, so taken as brought back by the person (broughtBack)")
            offScreen[id] = nil
            parked[id] = nil
            onParkingChanged?(ParkingChange(broughtBack: [id]))
            return
        }
        let next = nextWindow(after: pid)
        if let next, next.pid == pid { return giveKeyboard(to: next) }
        if switchedApp && !ownDoing, let onParkedWindowFocused {
            logUntucked(match.value.window, "its app came forward with the keyboard in it, so taken as the person going to it (restored)")
            return onParkedWindowFocused(id)
        }
        giveKeyboard(to: next)
    }

    /// The parked window that has the keyboard of this app, if one does.
    private func parkedWindow(focusedIn pid: pid_t) -> AX.Window? {
        guard let focused = AX.element(AX.application(pid), kAXFocusedWindowAttribute) else { return nil }
        return offScreen.values.first { $0.hasMoved && CFEqual($0.window.element, focused) }?.window
    }

    // MARK: Mission Control

    /// Mission Control, App Exposé or Show Desktop began. What is in front now is what leaving it without
    /// choosing anything comes back to.
    private func missionControlStarted() {
        guard !missionControl.isShowing else { return }
        pendingMissionControlCheck?.cancel()
        pendingMissionControlCheck = nil
        let front = frontLanding(seeingPastTheDock: true)
        missionControl.began(front: front)
        Self.log.debug("Mission Control began; in front: \(self.describe(front), privacy: .public)")
    }

    /// It ended, as the Dock says, or as Tuck takes it to have (`assumed`) when an app came forward or a
    /// parked window moved meanwhile. What it left is looked at all together once the exit has settled,
    /// and no parked window is judged before.
    private func missionControlEnded(assumed: Bool = false) {
        missionControl.ended(at: ProcessInfo.processInfo.systemUptime, assumed: assumed)
        pendingDriftCheck?.cancel()
        pendingDriftCheck = nil
        drifted = []
        Self.log.debug("Mission Control ended\(assumed ? " (assumed: the Dock hadn't said)" : "", privacy: .public)")
        settleAfterMissionControl()
    }

    /// Waits until Mission Control's exit has settled: `MissionControlVisit.settleDelay` after it, and a
    /// beat after each move or focus change since, so each is looked at with the rest. One wait at a
    /// time, and nothing repeats.
    private func settleAfterMissionControl() {
        guard !missionControl.isShowing, !offScreen.isEmpty else { return }
        pendingMissionControlCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMissionControlCheck = nil
            self.missionControlSettled()
        }
        pendingMissionControlCheck = work
        let wait = missionControl.wait(at: ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// Looks at every parked window once Mission Control's exit has settled, judged by what was in front
    /// as it began. One the person chose there comes back where it was. Any other that it left in view
    /// (or that its app put there as Mission Control let go) goes out of sight again, wherever the
    /// keyboard is (`OffScreenParking.driftAfterMissionControl`). One that can't be parked again, or
    /// can't be asked, is tried once more a little later, and only falls back if it still can't be moved.
    /// Then the keyboard is handed on from a parked window left with it, so nothing is typed out of sight.
    private func missionControlSettled() {
        guard AX.isTrusted, !offScreen.isEmpty else { return }
        let displays = Displays.quartzFrames
        let now = ProcessInfo.processInfo.systemUptime
        let front = frontLanding()
        // From here on a switch is judged from where Mission Control left the front, never from the Dock.
        if let front, NSRunningApplication(processIdentifier: front.pid)?.bundleIdentifier != Self.dockBundleID {
            lastFrontPID = front.pid
        }
        var change = ParkingChange()
        var chosen: [UUID] = []
        var refused: [UUID] = []
        var retrying = false
        for (id, entry) in offScreen where entry.hasMoved && !isResting(entry.window.pid) {
            let state = parkedState(of: entry)
            guard case .at(let frame) = state else {
                // Busy redrawing what Mission Control showed, say: asked once more when it has had a moment.
                if case .busy = state, missionControl.mayRetry(id, at: now) { retrying = true }
                seeTo(id, entry, state, change: &change)
                continue
            }
            let chose = missionControl.choseWindow(Self.landing(of: entry.window), front: front)
            switch OffScreenParking.driftAfterMissionControl(of: frame, displays: displays, chosen: chose) {
            case .bringBack:
                chosen.append(id)
            case .parkAgain:
                Self.log.debug("Mission Control left a parked \(Self.bundleID(of: entry.window), privacy: .public) window in view; parking it again")
                guard !moveBeyondCorner(entry) else { continue }
                // The exit may still hold it, or its frame not yet read true: tried again once settled.
                if missionControl.mayRetry(id, at: now) {
                    retrying = true
                } else if AX.state(of: entry.window.element) == .alive {
                    refused.append(id)
                }
            case .stays, .minimise:
                continue
            }
        }
        if !change.minimised.isEmpty { onParkingChanged?(change) }
        if !refused.isEmpty { fallBack(refused) }
        if retrying { settleAfterMissionControl() }
        for id in chosen {
            guard let entry = offScreen[id] else { continue }
            logUntucked(entry.window, "chosen by the person in Mission Control (restored)")
            onParkedWindowFocused?(id)
        }
        // Mission Control's exit made a parked window its app's key window again, or the keyboard never
        // left it as it went. It goes on to a window in view, as when the app passes it there itself. (A
        // window chosen there has come back by now, and is no longer parked.)
        if let front, offScreen.values.contains(where: { $0.hasMoved && Self.landing(of: $0.window) == front }) {
            Self.log.info("Mission Control left the keyboard in a parked window; handing it on")
            giveKeyboard(to: nextWindow(after: front.pid))
        }
    }

    /// Where the front is, to tell the person's choice in Mission Control from what it left: the app in
    /// front and its focused window, tucked or not. Seeing past the Dock, which Mission Control may bring
    /// forward, it is the app that was in front before it.
    private func frontLanding(seeingPastTheDock: Bool = false) -> OwnFrontChanges.Landing? {
        guard let running = NSWorkspace.shared.frontmostApplication else { return nil }
        var pid = running.processIdentifier
        if seeingPastTheDock, running.bundleIdentifier == Self.dockBundleID, let before = lastFrontPID { pid = before }
        // A resting app is paused and can't answer.
        guard pid != getpid(), !isResting(pid) else { return OwnFrontChanges.Landing(pid: pid) }
        let app = AX.application(pid)
        let focused = AX.element(app, kAXFocusedWindowAttribute)
        return OwnFrontChanges.Landing(pid: pid, window: focused.map { Self.token(for: AX.Window(element: $0, app: app, pid: pid)) })
    }

    private static func landing(of window: AX.Window) -> OwnFrontChanges.Landing {
        OwnFrontChanges.Landing(pid: window.pid, window: token(for: window))
    }

    // MARK: Diagnostics

    private static func bundleID(of window: AX.Window) -> String {
        NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier ?? "pid \(window.pid)"
    }

    /// Notes why a window stopped being tucked (or nearly did) without the person restoring it from Tuck,
    /// with its app and how lately Mission Control ended.
    private func logUntucked(_ window: AX.Window, _ reason: String) {
        Self.log.info("Untucked \(Self.bundleID(of: window), privacy: .public): \(reason, privacy: .public); \(self.missionControlNote(), privacy: .public)")
    }

    private func missionControlNote() -> String {
        if missionControl.isShowing { return "Mission Control showing" }
        guard let ended = missionControl.endedAt else { return "no Mission Control seen while windows were parked" }
        return String(format: "Mission Control ended %.2f s before", ProcessInfo.processInfo.systemUptime - ended)
    }

    private func describe(_ front: OwnFrontChanges.Landing?) -> String {
        guard let front else { return "nothing" }
        let app = NSRunningApplication(processIdentifier: front.pid)?.bundleIdentifier ?? "pid \(front.pid)"
        let parkedInFront = offScreen.values.contains { $0.hasMoved && Self.landing(of: $0.window) == front }
        return "\(app), \(front.window == nil ? "no window read" : parkedInFront ? "a parked window focused" : "a window in view focused")"
    }

    // MARK: Tucked state

    func keepTucked(_ windows: [ParkedWindow]) -> Set<UUID> {
        guard AX.isTrusted else { return [] }
        var minimised: Set<UUID> = []
        // Parked off screen: minimised one app at a time with its app hidden for the moment, so the Dock's
        // animation, which would start from the corner, isn't seen.
        let away = windows.filter(\.isOffScreen).compactMap { window -> (UUID, AX.Window)? in
            guard !restingBundleIDs().contains(window.app.bundleID),
                  let live = parked[window.id] ?? tuckedWindow(like: window) else { return nil }
            return (window.id, live)
        }
        for (_, group) in Dictionary(grouping: away, by: { $0.1.pid }) {
            for ((id, live), done) in zip(group, minimise(group.map(\.1))) where done {
                parked[id] = live
                offScreen[id] = nil
                minimised.insert(id)
            }
        }
        // Hidden with their app: the app is about to be shown, and a window it hasn't minimised yet would
        // come back with it.
        var asked: [(id: UUID, window: AX.Window)] = []
        for window in windows where !window.isOffScreen {
            guard let live = parked[window.id] ?? tuckedWindow(like: window),
                  AX.setMinimised(true, live.element) || AX.bool(live.element, kAXMinimizedAttribute) == true else { continue }
            parked[window.id] = live
            asked.append((window.id, live))
        }
        _ = AX.waitUntilMinimised(asked.map(\.window.element))
        return minimised.union(asked.filter { AX.bool($0.window.element, kAXMinimizedAttribute) == true }.map(\.id))
    }

    /// After a relaunch, takes up windows still parked off screen (Tuck stopped without minimising them,
    /// or couldn't), so the keyboard is kept from them and display changes are seen to again.
    func adopt(_ windows: [ParkedWindow]) {
        guard AX.isTrusted else { return }
        var adopted: Set<UUID> = []
        for window in windows where window.isOffScreen && offScreen[window.id] == nil
            && !restingBundleIDs().contains(window.app.bundleID) {
            guard let live = tuckedWindow(like: window), AX.bool(live.element, kAXMinimizedAttribute) != true else { continue }
            parked[window.id] = live
            offScreen[window.id] = OffScreenWindow(window: live, displayID: window.displayID,
                                                   frame: Displays.quartz(window.originalFrame.cgRect), hasMoved: true)
            adopted.insert(window.id)
        }
        if !adopted.isEmpty { keepOutOfSight(adopted) }
    }

    /// A tucked window found again after a relaunch, when Tuck no longer holds its element. It is matched
    /// by title among the app's windows put away the same way, so a same-titled window the person has in
    /// view is never taken. One parked off screen whose title has changed since (a browser's, say) is
    /// found by its size, if it is the only window of that size out of sight.
    private func tuckedWindow(like window: ParkedWindow) -> AX.Window? {
        let windows = AX.windows(bundleID: window.app.bundleID)
        func titled(_ candidate: AX.Window) -> Bool { AX.title(of: candidate.element) == window.title }
        func minimised(_ candidate: AX.Window) -> Bool { AX.bool(candidate.element, kAXMinimizedAttribute) == true }
        switch window.method {
        case .hiddenWithApp:
            return windows.first { !minimised($0) && titled($0) }
        case .offScreen:
            let away = windows.filter { candidate in
                !minimised(candidate) && AX.isOutOfSight(candidate.element)
                    && !parked.contains { $0.key != window.id && CFEqual($0.value.element, candidate.element) }
            }
            if let match = away.first(where: titled) ?? windows.first(where: { minimised($0) && titled($0) }) { return match }
            let size = window.originalFrame.cgRect.size
            let sized = away.filter { candidate in
                AX.frame(of: candidate.element).map { abs($0.width - size.width) <= 2 && abs($0.height - size.height) <= 2 } ?? false
            }
            return sized.count == 1 ? sized.first : nil
        case .minimised, nil:
            return windows.first { minimised($0) && titled($0) }
        }
    }

    /// Windows minimised in the last moment. While the Dock animation runs a window can still read as
    /// not minimised; after that, only its minimised state counts, so a window the person brought back
    /// from the Dock themselves can be tucked again.
    private var minimising: [(element: AXUIElement, at: TimeInterval)] = []

    private func isAlreadyTucked(_ window: AX.Window) -> Bool {
        if AX.bool(window.element, kAXMinimizedAttribute) == true { return true }
        if NSRunningApplication(processIdentifier: window.pid)?.isHidden == true { return true }
        // Parked off screen, or waiting in place for its card to cover it, or left off screen before a
        // relaunch.
        if offScreen.values.contains(where: { CFEqual($0.window.element, window.element) }) { return true }
        if AX.isOutOfSight(window.element) { return true }
        let now = ProcessInfo.processInfo.systemUptime
        minimising.removeAll { now - $0.at > 1.5 }
        return minimising.contains { CFEqual($0.element, window.element) }
    }

    private func isResting(_ pid: pid_t) -> Bool {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return restingBundleIDs().contains(bundleID)
    }

    /// Minimises windows of one app without the Dock's animation being seen: the app is hidden for a
    /// moment, they are minimised while it is hidden, and it is shown again, and put back in front if it
    /// was. This also keeps an app with no other windows in view from being left hidden. If the app can't
    /// be hidden, they are minimised in view. Returns whether each is now minimised (or on its way).
    private func minimise(_ windows: [AX.Window]) -> [Bool] {
        guard let first = windows.first else { return [] }
        let running = NSRunningApplication(processIdentifier: first.pid)
        let visible = AX.elements(first.app, kAXWindowsAttribute).filter {
            AX.string($0, kAXSubroleAttribute) == CandidatePolicy.standardSubrole
                && AX.bool($0, kAXMinimizedAttribute) != true && !AX.isOutOfSight($0)
        }
        let tucking = visible.filter { element in windows.contains { CFEqual($0.element, element) } }.count
        let plan = ParkingPolicy.plan(visibleWindowCount: visible.count, tuckingCount: tucking,
                                      appCanHide: running?.activationPolicy == .regular && running?.isHidden == false)
        let wasFrontmost = running?.isActive == true
        // Once done waiting on the app: until then no switch it causes can be reported. An app that was in
        // front stays there (put back if hiding it brought another forward), with whichever of its windows
        // takes focus.
        defer {
            noteOwnChange()
            if wasFrontmost { expectFront(first.pid) }
        }
        let hiddenForAMoment = plan != .minimiseInView && AX.hide(first) && AX.waitUntilOffScreen(first.pid)
        for window in windows { _ = AX.setMinimised(true, window.element) }
        if hiddenForAMoment {
            _ = AX.waitUntilMinimised(windows.map(\.element))
            _ = running?.unhide()
            // Hiding it brought another app forward, as its windows left the screen. It goes back in
            // front, as a minimise would have left it, once its windows are back: asked any sooner, the
            // request is accepted and then dropped.
            if wasFrontmost {
                _ = AX.waitUntilOnScreen(first.pid)
                AX.makeFrontmost(first.app, pid: first.pid)
                // Should it still be dropped, it is made once more a moment later, unless the person
                // has clicked or typed since and may have chosen another app themselves.
                let asked = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard let app = NSRunningApplication(processIdentifier: first.pid), !app.isActive, !app.isHidden,
                          !AX.personClickedOrTyped(since: asked) else { return }
                    AX.makeFrontmost(first.app, pid: first.pid)
                }
            }
        } else if running?.isHidden == true {
            // Hiding was asked for but didn't finish in time: show the app again and minimise in view.
            _ = running?.unhide()
        }
        let now = ProcessInfo.processInfo.systemUptime
        return windows.map { window in
            // Still open (the app ignored the request while hidden, say): minimised in view instead.
            if AX.bool(window.element, kAXMinimizedAttribute) != true, !AX.setMinimised(true, window.element) { return false }
            minimising.append((window.element, now))
            return true
        }
    }

    // MARK: Restoring

    func restore(_ window: ParkedWindow, placement: Placement, context: PlacementContext,
                 completion: @escaping (WindowActionOutcome) -> Void) {
        let target = PlacementGeometry.frame(
            for: placement,
            originalFrame: window.originalFrame.cgRect,
            visibleFrame: context.visibleFrame,
            originalDisplayAvailable: context.originalDisplayAvailable,
            destinationVisibleFrame: context.nextVisibleFrame
        )
        func finish(_ result: WindowActionResult, frame: CGRect? = nil) {
            completion(WindowActionOutcome(placement: placement, frame: frame.map(WindowFrame.init), result: result))
        }
        guard AX.isTrusted else {
            AX.promptForTrust()
            return finish(.needsPermission)
        }
        // Find the window, and only call it gone when that is confirmed: its app has quit or the system
        // says the window no longer exists. A busy app or an unmatched title leaves the row in place.
        let cached = parked[window.id]
        let cachedState = cached.map { AX.state(of: $0.element) }
        let appRunning: Bool? = cached.map { Self.isRunning($0.pid) } ?? (window.app.bundleID.isEmpty
            ? nil
            : !NSRunningApplication.runningApplications(withBundleIdentifier: window.app.bundleID).isEmpty)
        let match = cachedState == nil && appRunning != false ? tuckedWindow(like: window) : nil
        switch WindowLookup.classify(appRunning: appRunning, cached: cachedState, titleMatchFound: match != nil) {
        case .gone:
            parked[window.id] = nil
            offScreen[window.id] = nil
            return finish(.windowGone)
        case .unavailable:
            return finish(.failed)
        case .found:
            break
        }
        guard let live = cachedState == .alive ? cached : match else { return finish(.failed) }
        // Coming back on purpose: it can be tucked again at once, not taken for a repeated click.
        minimising.removeAll { CFEqual($0.element, live.element) }
        let area = placement == .nextDisplay ? (context.nextVisibleFrame ?? context.visibleFrame) : context.visibleFrame
        if window.isOffScreen, AX.bool(live.element, kAXMinimizedAttribute) != true {
            return restoreFromOffScreen(window, live, target: target, placement: placement, area: area,
                                        completion: completion)
        }
        offScreen[window.id] = nil
        // Many apps accept a frame while minimised (or hidden) and come back already in place.
        AX.setFrame(Displays.quartz(target), of: live)
        let accepted: Bool
        if window.isHiddenWithApp {
            // Hidden with its app: showing the app brings it back where it was, without any Dock animation.
            // (Windows hidden with it that should stay tucked were minimised first.)
            accepted = NSRunningApplication(processIdentifier: live.pid)?.unhide() ?? false
            if AX.bool(live.element, kAXMinimizedAttribute) == true { _ = AX.setMinimised(false, live.element) }
        } else {
            accepted = AX.setMinimised(false, live.element)
        }
        AX.raise(live)
        confirmRestored(live, accepted: accepted, attempt: 0) { [weak self] restored in
            guard let self else { return }
            guard restored else {
                // Still minimised: not restored. It stays parked, and held, for another try.
                self.parked[window.id] = live
                return finish(.failed)
            }
            self.parked[window.id] = nil
            // The un-minimise animation can reset the frame; settle it once the window is back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                _ = Self.apply(target, placement: placement, to: live, visibleFrame: area)
            }
            finish(.moved, frame: target)
        }
    }

    /// A window parked off screen is still open: it is raised while still out of sight, so it arrives in
    /// front rather than behind and then jumping forward, and set straight back in place. No system
    /// animation runs, and there is nothing to wait for.
    private func restoreFromOffScreen(_ window: ParkedWindow, _ live: AX.Window, target: CGRect, placement: Placement,
                                      area: CGRect, completion: @escaping (WindowActionOutcome) -> Void) {
        let entry = offScreen.removeValue(forKey: window.id)
        // An app hidden by the person meanwhile is shown again, or its window would come back unseen.
        if let running = NSRunningApplication(processIdentifier: live.pid), running.isHidden { _ = running.unhide() }
        AX.focus(live)
        let outcome = Self.apply(target, placement: placement, to: live, visibleFrame: area)
        switch outcome.result {
        case .moved, .constrained, .windowGone:
            parked[window.id] = nil
            completion(outcome)
        case .failed where !AX.isOutOfSight(live.element):
            // Back in view, though not where it was asked to go: it is out, so its row goes all the same.
            parked[window.id] = nil
            completion(WindowActionOutcome(placement: placement, frame: outcome.frame, result: .constrained))
        default:
            // Still out of sight: the app wouldn't let it come back. It stays parked for another try.
            if let entry { offScreen[window.id] = entry }
            parked[window.id] = live
            completion(WindowActionOutcome(placement: placement, frame: nil, result: .failed))
        }
    }

    /// A window reports itself minimised until its un-minimise animation is under way, so it is
    /// checked every 50 ms for about a second, without blocking, before the restore counts as failed.
    /// If the state cannot be read at all, the app's acceptance of the request decides.
    private func confirmRestored(_ window: AX.Window, accepted: Bool, attempt: Int, done: @escaping (Bool) -> Void) {
        let minimised = AX.bool(window.element, kAXMinimizedAttribute)
        let hidden = AX.bool(window.app, kAXHiddenAttribute)
        if minimised == false && hidden != true { return done(true) }
        guard attempt < 20 else { return done(minimised == nil && accepted) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.confirmRestored(window, accepted: accepted, attempt: attempt + 1, done: done)
        }
    }

    /// Whether a process still exists, asked of the kernel directly so a quit is seen at once.
    private static func isRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }

    func place(_ token: WindowToken, placement: Placement) -> WindowActionOutcome {
        guard AX.isTrusted else {
            AX.promptForTrust()
            return WindowActionOutcome(placement: placement, frame: nil, result: .needsPermission)
        }
        // A tucked window is never placed: that would bring it back into view while its row stays.
        guard let window = held(token), AX.state(of: window.element) == .alive, !isAlreadyTucked(window),
              let quartz = AX.frame(of: window.element) else {
            return WindowActionOutcome(placement: placement, frame: nil, result: .windowGone)
        }
        let current = Displays.appKit(quartz)
        guard let screen = Displays.screen(for: current) else {
            return WindowActionOutcome(placement: placement, frame: nil, result: .failed)
        }
        let target: CGRect
        var area = screen.visibleFrame
        if placement == .original {
            guard let previous = history.take(for: window.key) else {
                return WindowActionOutcome(placement: placement, frame: WindowFrame(current), result: .unchanged)
            }
            target = previous
            area = Displays.screen(for: previous)?.visibleFrame ?? area
        } else {
            let next = placement == .nextDisplay ? Displays.next(after: screen) : nil
            if placement == .nextDisplay && next == nil {
                return WindowActionOutcome(placement: placement, frame: WindowFrame(current), result: .unchanged)
            }
            history.remember(current, for: window.key)
            target = PlacementGeometry.frame(for: placement, originalFrame: current, visibleFrame: screen.visibleFrame,
                                             destinationVisibleFrame: next?.visibleFrame)
            area = next?.visibleFrame ?? area
        }
        return Self.apply(target, placement: placement, to: window, visibleFrame: area)
    }

    /// Applies a frame, reads back what the app actually did, and re-anchors size-constrained windows.
    private static func apply(_ target: CGRect, placement: Placement, to window: AX.Window, visibleFrame: CGRect) -> WindowActionOutcome {
        AX.setFrame(Displays.quartz(target), of: window)
        guard let quartz = AX.frame(of: window.element) else {
            return WindowActionOutcome(placement: placement, frame: nil, result: .windowGone)
        }
        let actual = Displays.appKit(quartz)
        switch PlacementGeometry.fit(actual: actual, target: target) {
        case .exact:
            return WindowActionOutcome(placement: placement, frame: WindowFrame(actual), result: .moved)
        case .constrained:
            let anchored = PlacementGeometry.anchored(actualSize: actual.size, target: target, placement: placement,
                                                      visibleFrame: visibleFrame)
            AX.setPosition(Displays.quartz(anchored).origin, of: window.element)
            return WindowActionOutcome(placement: placement, frame: WindowFrame(anchored), result: .constrained)
        case .rejected:
            return WindowActionOutcome(placement: placement, frame: WindowFrame(actual), result: .failed)
        }
    }
}
