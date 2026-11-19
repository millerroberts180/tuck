import AppKit
import TuckCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var model: TuckModel!
    private var coordinator: OverlayCoordinator!
    private var settingsWindow: SettingsWindowController!
    private var setupWindow: SetupWindowController?
    private var persistence: FileLibraryPersistence!
    private var clipboardCapture: ClipboardCaptureService!
    private var clipboardPersistence: FileClipboardPersistence!
    private let windowDrag = WindowDragController()
    private let scrolling = ScrollController()
    private let hotKeys = HotKeyCenter()
    private var shortcutMenuItems: [ShortcutAction: NSMenuItem] = [:]
    private var statusItem: NSStatusItem?
    /// Hides the menu-bar item while Line Apps has the family collapsed into its line. The notch and
    /// the bubble stay: they are Tuck's place, not an icon among the others.
    /// The delegate runs on the main thread, as the fold does.
    private lazy var lineFold = MainActor.assumeIsolated {
        LineAppsFold(setHidden: { [weak self] hidden in self?.statusItem?.isVisible = !hidden },
                     button: { [weak self] in self?.statusItem?.button },
                     name: { [weak self] in self?.statusItem?.autosaveName })
    }
    private var accessibilityObserver: NSObjectProtocol?
    private var restObservers: [NSObjectProtocol] = []
    private var promptedForTaps = false
    private var support: URL!
    /// Set once Uninstall starts deleting, so quitting saves nothing back.
    private var uninstalling = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // From a disk image or a translocated copy, Tuck offers once to move itself first.
        if MoveToApplications.offerIfNeeded() { return }
        // Every Accessibility request, to any app or window, gives up after this long, so a hung app can
        // never stall Tuck (the notch included).
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), AX.messagingTimeout)
        // What builds with a trial left behind is deleted, quietly and off the main thread.
        DispatchQueue.global(qos: .utility).async { TrialLeftovers.remove() }
        let settings = SettingsStore()
        let haptics = SystemHaptics(isEnabled: settings.hapticsEnabled)
        let support = Self.supportDirectory()
        let folder = SupportFolder(directory: support)
        let clipboardPersistence = FileClipboardPersistence(fileURL: folder.clipboardHistory, assets: folder.clipboardAssets)
        var clipboard = clipboardPersistence.load() ?? ClipboardHistory()
        clipboard.isEnabled = settings.clipboardHistoryEnabled
        clipboard.retention = settings.clipboardRetention
        clipboard.prune()
        let persistence = FileLibraryPersistence(fileURL: folder.library)
        let received = folder.received

        let parking = AccessibilityParkingService()
        let model = TuckModel(
            parking: parking,
            rest: ProcessRestService(),
            opener: WorkspaceItemOpener(),
            pasteboard: SystemPasteboard(assets: folder.clipboardAssets),
            haptics: haptics,
            persistence: persistence,
            clipboard: clipboard,
            receivedFiles: received,
            paster: SystemPaster()
        )
        model.cardLayout = settings.cardLayout
        model.showsCopyTimes = settings.showsCopyTimes

        parking.restingBundleIDs = { [weak model] in model?.restingBundleIDs ?? [] }
        model.onRestingChanged = { [weak self, weak model] resting in
            guard let self, let model else { return }
            self.observeWorkspaceForRest(resting ? model : nil)
        }
        // Anything still recorded as resting (after a crash, say) is woken first, identity checked;
        // so is anything recorded in a library file that couldn't be read.
        model.recoverRestedApps()
        model.wakeRecorded(persistence.recoveredRestStates)
        observeWorkspaceForRest(model.restingBundleIDs.isEmpty ? nil : model)
        parking.onParkingChanged = { [weak model] change in
            model?.windowsParkedDifferently(minimised: change.minimised, refused: change.refused,
                                            broughtBack: change.broughtBack)
        }
        parking.onParkedWindowFocused = { [weak model] id in model?.parkedWindowFocused(id) }
        // Windows still parked off screen from before (Tuck stopped without minimising them) are taken
        // up again.
        parking.adopt(model.library.windows)

        // Received files nothing refers to any more (after a crash, say) are cleared once, off the main
        // thread; never when the saved library couldn't be read, since it may still refer to them.
        if persistence.setAsideURL == nil {
            let referenced = model.library.items.flatMap(\.fileURLs)
            DispatchQueue.global(qos: .utility).async { received.sweep(keeping: referenced) }
        }

        settings.onChange = { [weak self, weak model] store in
            model?.apply(settings: store)
            self?.updateClipboardCapture()
            self?.applyOverlayOptions()
            self?.updateInputTaps()
            self?.updateStatusItem()
            self?.updateShortcuts()
        }
        hotKeys.onAction = { [weak self] action in self?.perform(action) }

        let settingsWindow = SettingsWindowController(
            settings: settings,
            model: model,
            supportFolder: support,
            onClearClipboard: { [weak model] in model?.clearClipboard() },
            onOpenTutorial: { [weak self] in self?.showSetup(tutorialOnly: true) },
            onUninstall: { [weak self] in self?.uninstall() }
        )
        model.openSettingsHandler = { [weak settingsWindow] in settingsWindow?.show() }
        model.enableRestHandler = { [weak settings] in settings?.restEnabled = true }

        self.settings = settings
        self.model = model
        self.persistence = persistence
        self.clipboardPersistence = clipboardPersistence
        self.settingsWindow = settingsWindow
        self.support = support
        model.onClipboardHistoryChanged = { [weak clipboardPersistence] history in clipboardPersistence?.save(history) }
        // Clear History also deletes any unreadable history files set aside, which hold old entries, and
        // every image and styled text kept beside it.
        model.onClipboardCleared = { [weak clipboardPersistence] in
            clipboardPersistence?.removeSetAsideFiles()
            clipboardPersistence?.removeAllAssets()
        }
        clipboardPersistence.save(model.clipboard)
        // Tiles draw a copied image, styled text, page icon or map from here, and Keep saves an image from it.
        model.clipboardAssets = folder.clipboardAssets
        let enricher = ClipboardEnricher(assets: folder.clipboardAssets)
        enricher.readsTextInImages = settings.clipboardReadsImageText
        model.clipboardEnricher = enricher
        clipboardCapture = ClipboardCaptureService(assets: folder.clipboardAssets) { [weak model] capture in
            model?.recordClipboardCapture(capture)
        }
        clipboardCapture.onAccessChange = { [weak model] heldBack in model?.clipboardAccessHeldBack = heldBack }
        coordinator = OverlayCoordinator(model: model)
        updateClipboardCapture()
        applyOverlayOptions()
        coordinator.start()
        updateStatusItem()
        MainActor.assumeIsolated { lineFold.start() }
        observeAccessibility()
        updateInputTaps()
        updateShortcuts()
        // The first launch opens setup.
        let defaults = UserDefaults.standard
        var opensSetup = !defaults.bool(forKey: SetupModel.completedKey)
        #if DEBUG
        // Testing and demo aid: `Tuck -TuckOpenSettingsOnLaunch YES` opens Settings once at startup,
        // without taking focus from the app in use.
        if defaults.bool(forKey: "TuckOpenSettingsOnLaunch") { settingsWindow.show(activating: false) }
        // Testing and demo aid: `-TuckOpenSetupOnLaunch YES` opens setup every time, and
        // `-TuckOpenTutorialOnLaunch YES` opens the tutorial.
        opensSetup = opensSetup || defaults.bool(forKey: "TuckOpenSetupOnLaunch")
        if !opensSetup, defaults.bool(forKey: "TuckOpenTutorialOnLaunch") { showSetup(tutorialOnly: true) }
        #endif
        if opensSetup { showSetup(tutorialOnly: false) }
    }

    /// Setup the first time; the tutorial (its teaching steps only) from Settings › General. One window
    /// at a time, created when shown and released when closed.
    private func showSetup(tutorialOnly: Bool) {
        if let setupWindow { return setupWindow.present() }
        let window = SetupWindowController(settings: settings, model: model, tutorialOnly: tutorialOnly) { [weak self] in
            // Finishing the first run opens the real panel, so the person sees where Tuck lives.
            guard !tutorialOnly else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.coordinator.expandOnPreferredScreen() }
        }
        window.onClose = { [weak self] in
            self?.setupWindow = nil
            // A feature chosen during setup that needs Accessibility asks now, if setup didn't.
            self?.updateInputTaps()
        }
        setupWindow = window
        window.present()
    }

    /// Opening Tuck again while it runs (Finder, Spotlight, the Dock) opens Settings: the way back when
    /// the menu-bar item is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    private func applyOverlayOptions() {
        guard let settings, let coordinator else { return }
        coordinator.apply(OverlayCoordinator.Options(displays: settings.surfaceDisplays, notchless: settings.notchlessStyle,
                                                     showInFullScreen: settings.showInFullScreen,
                                                     showInScreenshots: settings.showInScreenshots,
                                                     dropInvitation: settings.dropInvitation))
    }

    private func updateClipboardCapture() {
        clipboardCapture?.isEnabled = settings?.clipboardHistoryEnabled ?? false
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardCapture?.stop()
        if !uninstalling, let model { clipboardPersistence?.save(model.clipboard) }
        model?.wakeAllRestedApps()
        // No window is left off screen, out of reach, while Tuck isn't running: they wait in the Dock.
        model?.minimiseOffScreenWindows()
        guard !uninstalling else { return }
        persistence?.flush()
        clipboardPersistence?.flush()
    }

    // MARK: Uninstall

    /// Gives back every rested app and tucked window first; if any won't come back, it stops there and
    /// says so, with nothing deleted. Then Tuck stops everything it runs, removes itself and quits.
    private func uninstall() {
        guard !uninstalling, !model.isRestoringAll else { return }
        model.wakeAllRestedApps()
        model.restoreEveryWindow { [weak self] summary in
            guard let self else { return }
            let resting = self.model.restingBundleIDs.sorted().map(TuckModel.appName(for:))
            guard summary.kept == 0, resting.isEmpty else {
                return Uninstaller.explainStop(kept: summary.kept, resting: resting)
            }
            self.uninstalling = true
            self.settingsWindow.close()
            // Nothing may run or save from here on: a save would bring back the folder being removed.
            self.settings.onChange = nil
            self.clipboardCapture.stop()
            self.persistence.close()
            self.clipboardPersistence.close()
            _ = self.hotKeys.apply(nil)
            _ = self.windowDrag.update(enabled: false, modifiers: self.settings.windowDragModifiers)
            _ = self.scrolling.update(smoothness: nil, reverseWheel: false)
            if let item = self.statusItem { NSStatusBar.system.removeStatusItem(item) }
            self.statusItem = nil
            let leftovers = Uninstaller.removeEverything(supportFolder: self.support)
            Uninstaller.showFinished(leftovers: leftovers)
            NSApp.terminate(nil)
        }
    }

    /// While any app is resting, it is woken before sleep and power-off, and when the person deliberately
    /// switches to it (Dock, Command-Tab). With nothing resting (nil) these observers don't exist, so
    /// switching apps never wakes Tuck.
    private func observeWorkspaceForRest(_ model: TuckModel?) {
        let center = NSWorkspace.shared.notificationCenter
        guard let model else {
            restObservers.forEach(center.removeObserver)
            restObservers.removeAll()
            return
        }
        guard restObservers.isEmpty else { return }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.willPowerOffNotification] {
            restObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak model] _ in
                model?.wakeAllRestedApps()
            })
        }
        restObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                queue: .main) { [weak model] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            model?.wakeIfResting(bundleID: bundleID)
        })
    }

    private static func supportDirectory() -> URL {
        #if DEBUG
        // Testing and demo aid: `Tuck -TuckSupportDirectory /some/folder` keeps a separate library there,
        // so screenshots and checks never touch the person's own.
        if let folder = UserDefaults.standard.string(forKey: "TuckSupportDirectory"), folder.hasPrefix("/") {
            return URL(fileURLWithPath: folder, isDirectory: true)
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Tuck", isDirectory: true)
    }

    /// The system posts this when any app's Accessibility permission changes, so Tuck learns about a
    /// newly granted permission without polling. The trust value settles a moment after the post.
    private func observeAccessibility() {
        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.model.accessibilityChanged(trusted: AX.isTrusted)
                self?.updateInputTaps()
            }
        }
    }

    /// Matches the optional event taps (modifier-drag, mouse wheel) to the settings. Each tap exists only
    /// while its feature is on; a feature switched on without Accessibility shows the system prompt once,
    /// though not while setup is open, since its permission step asks.
    private func updateInputTaps() {
        guard let settings, !uninstalling else { return }
        let dragReady = windowDrag.update(enabled: settings.windowDragEnabled, modifiers: settings.windowDragModifiers)
        let scrollReady = scrolling.update(smoothness: settings.smoothScrollingEnabled ? settings.scrollSmoothness : nil,
                                           reverseWheel: settings.reverseMouseWheel)
        let wantsPermission = settings.windowDragEnabled || settings.smoothScrollingEnabled || settings.reverseMouseWheel
        if !(dragReady && scrollReady), wantsPermission, !AX.isTrusted, !promptedForTaps, setupWindow == nil {
            promptedForTaps = true
            AX.promptForTrust()
        }
    }

    /// Registers the global shortcuts while they are on (and not being typed in Settings), and shows them
    /// in the menu-bar menu.
    private func updateShortcuts() {
        guard let settings else { return }
        let active = settings.shortcutsEnabled && settings.recordingShortcut == nil
        let refused = hotKeys.apply(active ? settings.shortcuts : nil)
        if settings.recordingShortcut == nil, settings.refusedShortcuts != refused { settings.refusedShortcuts = refused }
        for (action, item) in shortcutMenuItems {
            let shortcut = settings.shortcutsEnabled ? settings.shortcuts.shortcut(for: action) : nil
            // Only keys that type a character can be shown as a menu key equivalent.
            if let shortcut, shortcut.key.count == 1 {
                item.keyEquivalent = shortcut.key.lowercased()
                item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
            } else {
                item.keyEquivalent = ""
            }
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .tuckFrontWindow: model.tuckFrontWindow()
        case .restoreLastTucked: model.restoreLastTuckedWindow()
        case .togglePanel: coordinator.togglePanelFromKeyboard()
        }
    }

    /// Shows or removes the menu-bar item to match Settings → General.
    private func updateStatusItem() {
        guard let settings else { return }
        if settings.menuBarIconShown, statusItem == nil {
            installStatusItem()
        } else if !settings.menuBarIconShown, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            shortcutMenuItems = [:]
        }
    }

    // A small secondary entry point. Primary use is the notch or bubble itself.
    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = TuckLogo.menuBarImage()
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Tuck", action: #selector(openPanel), keyEquivalent: "")
        let tuck = menu.addItem(withTitle: "Tuck Front Window", action: #selector(tuckFrontWindow), keyEquivalent: "")
        let restore = menu.addItem(withTitle: "Restore Last Tucked Window", action: #selector(restoreLastTucked), keyEquivalent: "")
        [open, tuck, restore].forEach { $0.target = self }
        shortcutMenuItems = [.togglePanel: open, .tuckFrontWindow: tuck, .restoreLastTucked: restore]
        // Swiping up tucks Tuck away and swiping down brings it back; these do the same without a swipe.
        menu.addItem(withTitle: "Tuck Away", action: #selector(tuckAwaySurfaces), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Bring Tuck Back", action: #selector(revealSurfaces), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tuck", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        // Turned on while collapsed into Line Apps' line, it waits there until the line lets it out.
        item.isVisible = !MainActor.assumeIsolated { lineFold.isFolded }
        statusItem = item
    }

    @objc private func openPanel() { coordinator.expandOnPreferredScreen() }
    @objc private func tuckFrontWindow() { model.tuckFrontWindow() }
    @objc private func restoreLastTucked() { model.restoreLastTuckedWindow() }
    @objc private func revealSurfaces() { model.revealEverywhere() }
    @objc private func tuckAwaySurfaces() { model.tuckAwayEverywhere(coordinator.screenIDs) }
    @objc private func openSettings() { settingsWindow.show() }
    /// Quitting moves windows parked off screen to the Dock, which takes Accessibility. Without it they
    /// would stay out of sight until Tuck is allowed again and reopened, so that is said first. Only this
    /// menu item asks: a logout or shutdown quits Tuck without a question in its way.
    @objc private func quit() {
        let offScreen = model?.library.windows.filter(\.isOffScreen).count ?? 0
        if offScreen > 0, !AX.isTrusted, !confirmQuitWithoutAccessibility(offScreen) { return }
        NSApp.terminate(nil)
    }

    private func confirmQuitWithoutAccessibility(_ count: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = count == 1 ? "A tucked window will stay out of sight" : "\(count) tucked windows will stay out of sight"
        alert.informativeText = "Without \(AX.paneName), Tuck can't bring them back, or move them to the Dock as it quits. "
            + "Once Tuck is allowed in \(AX.paneName) and opened again, it can bring them back."
        alert.addButton(withTitle: "Open System Settings…")
        alert.addButton(withTitle: "Quit Anyway").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            AX.openAccessibilitySettings()
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(revealSurfaces): return !model.tuckedAwayScreenIDs.isEmpty
        case #selector(tuckAwaySurfaces): return !Set(coordinator.screenIDs).isSubset(of: model.tuckedAwayScreenIDs)
        case #selector(restoreLastTucked): return model.canRestoreLastTucked
        default: return true
        }
    }
}
