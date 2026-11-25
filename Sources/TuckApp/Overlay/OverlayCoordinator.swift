import AppKit
import TuckCore

/// Owns one overlay per display and the few event monitors Tuck needs. Monitors are event-driven and the
/// outside-click monitor exists only while a panel is open, so a collapsed Tuck does no background work.
final class OverlayCoordinator {
    private unowned let model: TuckModel
    private var controllers: [CGDirectDisplayID: OverlayController] = [:]
    private var outsideClickMonitor: Any?
    private var scrollMonitor: Any?
    private let depositAnimator = DepositAnimator()
    private var screenObserver: NSObjectProtocol?
    private var isStarted = false

    /// Where and how the surfaces show, from Settings → Notch and Held.
    struct Options: Equatable {
        var displays: SurfaceDisplays = .all
        var notchless: NotchlessStyle = .bubble
        var showInFullScreen = true
        var showInScreenshots = true
        var dropInvitation = true
    }
    private var options = Options()
    private lazy var dragWatcher = DragApproachWatcher(
        zones: { [weak self] in self?.controllers.values.map { ($0.anchor.screenID, $0.approachZone) } ?? [] },
        onPrompt: { [weak self] screenID, level in
            self?.controllers.forEach { id, controller in controller.setDropPrompt(id == screenID ? level : nil) }
        },
        onContent: { [weak self] kind in self?.model.dragStarted(kind: kind) },
        onApproach: { [weak self] screenID in
            guard let self else { return }
            self.model.dragEntered(on: screenID, kind: self.model.dragKind)
        },
        onLeave: { [weak self] screenID in self?.model.dragApproachEnded(on: screenID) }
    )

    init(model: TuckModel) {
        self.model = model
        model.requestKeyFocus = { [weak self] screenID in self?.controllers[screenID]?.makeKey() }
        model.visibleFrameProvider = { screenID in
            NSScreen.screens.first { $0.displayID == screenID }?.visibleFrame
        }
        model.displayExists = { identifier in
            NSScreen.screens.contains { String($0.displayID) == identifier || $0.localizedName == identifier }
        }
        model.addObserver { [weak self] in self?.modelChanged() }
        model.onWindowsTucked = { [weak self] windows, covered, arrived, landed in
            // A turn later, once the open panel has laid out the rows these windows have just taken.
            DispatchQueue.main.async {
                guard let self else {
                    covered(Set(windows.map(\.id)))
                    return landed(true)
                }
                self.depositAnimator.fly(windows, target: {
                    self.depositTarget(for: $0, frame: $0.originalFrame.cgRect)
                }, covered: covered, arrived: arrived, landed: landed)
            }
        }
        model.onWindowRestoring = { [weak self] window, frame, landed in
            guard let self else { return landed() }
            self.depositAnimator.flyOut(window, to: frame, from: self.depositTarget(for: window, frame: frame),
                                        landed: landed)
        }
    }

    /// Applies changed options: displays and style rebuild the surfaces, visibility updates them in place,
    /// and the drag watcher runs only while the drop invitation is on.
    func apply(_ next: Options) {
        guard next != options else { return }
        let previous = options
        options = next
        guard isStarted else { return }
        if next.displays != previous.displays || next.notchless != previous.notchless {
            rebuildControllers()
        }
        if next.showInFullScreen != previous.showInFullScreen || next.showInScreenshots != previous.showInScreenshots {
            controllers.values.forEach(applyVisibility)
            depositAnimator.isHiddenFromCapture = !next.showInScreenshots
        }
        if next.dropInvitation != previous.dropInvitation {
            next.dropInvitation ? dragWatcher.start() : dragWatcher.stop()
        }
    }

    func start() {
        isStarted = true
        depositAnimator.isHiddenFromCapture = !options.showInScreenshots
        rebuildControllers()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildControllers() }
        if options.dropInvitation { dragWatcher.start() }
        // Local, so it only sees scrolls aimed at Tuck's own windows, and sees them before the panel's
        // list does: a swipe over a list too short to scroll still closes the panel.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let controller = self?.controllers.values.first(where: { $0.panel === event.window }) else { return event }
            return controller.handleScroll(event) ? nil : event
        }

        #if DEBUG
        // Testing and demo aid: `Tuck -TuckOpenOnLaunch YES` opens the panel once at startup; with
        // `-TuckOpenPage full` unfolded, `windows`, `files` or `copied` through that lens, or `picker` with
        // the window picker.
        if UserDefaults.standard.bool(forKey: "TuckOpenOnLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                self.expandOnPreferredScreen()
                // Once the panel has opened, as a person would choose (`-TuckOpenPageDelay 0` tries it
                // while the panel is still opening).
                let delay = UserDefaults.standard.string(forKey: "TuckOpenPageDelay").flatMap(Double.init) ?? 0.8
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    let page = UserDefaults.standard.string(forKey: "TuckOpenPage")
                    if page == "picker" {
                        self.model.openWindowPicker()
                    } else if page == "full" {
                        self.model.unfold()
                    } else if let lens = page.flatMap(StreamLens.init(rawValue:)) {
                        self.model.toggleLens(lens)
                    }
                }
            }
        }
        #endif
    }

    /// Displays whose closed surface can be tucked away: a bubble or a drawn notch. A closed hardware
    /// notch is already bare.
    var tuckableScreenIDs: [CGDirectDisplayID] {
        controllers.values.filter { $0.anchor.kind == .bubble || $0.anchor.isSimulated }.map(\.anchor.screenID)
    }

    /// Prefers the notched built-in display, otherwise the display with the menu bar.
    func expandOnPreferredScreen() {
        let preferred = controllers.values.first { $0.anchor.kind == .notch && !$0.anchor.isSimulated }
            ?? NSScreen.main.flatMap { controllers[$0.displayID] }
            ?? controllers.values.first
        if let id = preferred?.anchor.screenID { model.expand(on: id, via: .menu) }
    }

    /// Opens or closes the panel from the keyboard: it opens on the display under the pointer, where the
    /// person is working, or on the preferred display if that can't be told.
    func togglePanelFromKeyboard() {
        if model.expandedScreenID != nil { return model.collapse(via: .keyboard) }
        let pointer = NSEvent.mouseLocation
        guard let controller = controllers.values.first(where: { NSMouseInRect(pointer, $0.anchor.screenFrame, false) }) else {
            return expandOnPreferredScreen()
        }
        model.expand(on: controller.anchor.screenID, via: .keyboard)
    }

    /// Where a tucked window's stand-in lands (or, coming back, sets off): its row in the open panel, or
    /// the mark, on the surface of the display holding `frame` (where the window was, or will be), so the
    /// flight never has to cross between displays.
    private func depositTarget(for window: ParkedWindow, frame: CGRect) -> DepositLanding? {
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        func overlap(_ controller: OverlayController) -> CGFloat {
            let shared = controller.anchor.screenFrame.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        let controller = controllers.values.first { $0.anchor.screenFrame.contains(centre) }
            ?? controllers.values.max { overlap($0) < overlap($1) }
        return controller?.depositLanding(window: window.id)
    }

    private func modelChanged() {
        controllers.values.forEach { $0.refresh() }
        updateOutsideClickMonitor()
    }

    private func rebuildControllers() {
        var next: [CGDirectDisplayID: OverlayController] = [:]
        var created: [OverlayController] = []
        let screens = options.displays.select(from: NSScreen.screens) { CGDisplayIsBuiltin($0.displayID) != 0 }
        for screen in screens {
            let anchor = ScreenAnchor.resolve(for: screen, notchless: options.notchless)
            if let existing = controllers[anchor.screenID], existing.anchor == anchor {
                next[anchor.screenID] = existing
            } else {
                controllers[anchor.screenID]?.close()
                let controller = OverlayController(anchor: anchor, model: model)
                applyVisibility(controller)
                next[anchor.screenID] = controller
                created.append(controller)
            }
        }
        for (id, controller) in controllers where next[id] == nil { controller.close() }
        controllers = next
        if let expanded = model.expandedScreenID, controllers[expanded] == nil {
            model.collapse(via: .outside)
        }
        // A surface rebuilt for the same display (its resolution or menu bar changed) picks up where the
        // old one was: tucked away, or open.
        created.forEach { $0.refresh() }
        updateOutsideClickMonitor()
    }

    private func applyVisibility(_ controller: OverlayController) {
        controller.panel.apply(showInFullScreen: options.showInFullScreen, showInScreenshots: options.showInScreenshots)
    }

    private func updateOutsideClickMonitor() {
        let needsMonitor = model.expandedScreenID != nil
        if needsMonitor, outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.model.collapse(via: .outside)
            }
        } else if !needsMonitor, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
