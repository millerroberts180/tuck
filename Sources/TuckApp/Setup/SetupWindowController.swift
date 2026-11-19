import AppKit
import SwiftUI
import TuckCore

/// Where the person is in setup, and which of Tuck's moves they have done with the real Tuck.
final class SetupModel: ObservableObject {
    static let completedKey = "setup.completed"

    /// This run's steps: all of them the first time, only the practice as a tutorial (see `SetupStep`).
    let steps: [SetupStep]
    let isTutorial: Bool
    @Published var step: SetupStep
    /// The moves done on the real notch, as TuckModel reports them.
    @Published var practice = SetupPractice()
    @Published var openAtLogin: Bool
    /// On a Mac without a notch, Tuck is a small bubble in the middle of the menu bar, unless Settings ›
    /// Notch draws a notch there instead.
    var hasNotch: Bool

    let settings: SettingsStore
    let app: TuckModel
    var onFinish: (() -> Void)?

    init(settings: SettingsStore, app: TuckModel, tutorialOnly: Bool) {
        self.settings = settings
        self.app = app
        isTutorial = tutorialOnly
        steps = SetupStep.steps(tutorialOnly: tutorialOnly)
        step = steps[0]
        hasNotch = settings.notchlessStyle == .notch || NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        // On by default the first time; afterwards, whatever the system's login items say.
        openAtLogin = LoginItem.isAvailable
            && (LoginItem.isEnabled || !UserDefaults.standard.bool(forKey: Self.completedKey))
        // Ticked off as the real Tuck does each move, and published only when one is new.
        app.onPractice = { [weak self] event in
            guard let self else { return }
            var practice = self.practice
            if practice.record(event) { self.practice = practice }
        }
    }

    var isFirst: Bool { step == steps.first }
    var isLast: Bool { step == steps.last }
    var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    func next() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return finish() }
        step = steps[index + 1]
    }

    func back() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
    }

    func finish() {
        if steps.contains(.done), LoginItem.isAvailable, openAtLogin != LoginItem.isEnabled { LoginItem.set(openAtLogin) }
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        onFinish?()
    }

    /// The system's prompt the first time, which adds Tuck to the Accessibility list; after that it can
    /// only open the list. The page notices the switch through the observer Tuck already has.
    func requestAccessibility() {
        if AX.hasPrompted { AX.openAccessibilitySettings() } else { AX.promptForTrust() }
    }
}

/// Tuck's first-run setup, and the tutorial it becomes when reopened from Settings. Created when shown
/// and released, with its SwiftUI tree, when closed, like Settings.
final class SetupWindowController: NSObject, NSWindowDelegate {
    /// Small, so the notch and the windows the practice uses stay in view beside it.
    static let size = CGSize(width: 600, height: 440)

    private let window: NSWindow
    private let setup: SetupModel
    var onClose: (() -> Void)?

    init(settings: SettingsStore, model: TuckModel, tutorialOnly: Bool, onFinish: @escaping () -> Void) {
        setup = SetupModel(settings: settings, app: model, tutorialOnly: tutorialOnly)
        window = TuckWindow(contentRect: CGRect(origin: .zero, size: Self.size),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = tutorialOnly ? "Tuck Tutorial" : "Set Up Tuck"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SetupView(setup: setup))
        window.delegate = self
        window.center()
        setup.onFinish = { [weak self] in
            self?.window.close()
            onFinish()
        }
    }

    func present() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // An agent app's activation can be declined while another app is in use; the window still
        // comes to the front.
        window.orderFrontRegardless()
    }

    /// Back from System Settings: look again, in case the permission's notice hasn't arrived yet.
    func windowDidBecomeKey(_ notification: Notification) {
        guard setup.step == .accessibility else { return }
        setup.app.accessibilityChanged(trusted: AX.isTrusted)
    }

    func windowWillClose(_ notification: Notification) {
        setup.app.onPractice = nil
        DispatchQueue.main.async { [weak self] in self?.onClose?() }
    }
}
