import AppKit
import SwiftUI
import TuckCore

/// Where the person is in setup, and what they've tried. Choices write straight to `SettingsStore`, so
/// every one is a real setting from the moment it's made.
final class SetupModel: ObservableObject {
    /// In order: what Tuck is, the loop on a pretend desktop, the extras to choose right after, the
    /// notch's gestures to try, then the permissions (windows and files), then where Tuck lives. Value
    /// before the ask.
    enum Step: Int, CaseIterable {
        case welcome, tour, choose, gestures, permission, done
    }

    static let completedKey = "setup.completed"

    /// This run's steps: everything the first time, only the teaching steps as a tutorial.
    let steps: [Step]
    let isTutorial: Bool
    @Published var step: Step
    /// The pretend screen, shared by the tour and the gesture step.
    @Published var desk = TourDesk()
    @Published var openAtLogin: Bool
    /// Files: whether Full Disk Access is on, and each protected folder's answer once asked for.
    @Published var hasFullDiskAccess = FileAccess.hasFullDiskAccess
    @Published var folderAnswers: [FileAccess.Folder: Bool] = [:]
    @Published var isAskingForFolders = false

    let settings: SettingsStore
    let app: TuckModel
    var onFinish: (() -> Void)?

    init(settings: SettingsStore, app: TuckModel, tutorialOnly: Bool) {
        self.settings = settings
        self.app = app
        isTutorial = tutorialOnly
        steps = tutorialOnly ? [.tour, .choose, .gestures] : Step.allCases
        step = steps[0]
        // On by default the first time; afterwards, whatever the system's login items say.
        openAtLogin = LoginItem.isAvailable
            && (LoginItem.isEnabled || !UserDefaults.standard.bool(forKey: Self.completedKey))
    }

    var isFirst: Bool { step == steps.first }
    var isLast: Bool { step == steps.last }
    var stepNumber: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    func next() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return finish() }
        step = steps[index + 1]
        if step == .permission {
            app.accessibilityChanged(trusted: AX.isTrusted)
            refreshFileAccess()
        }
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

    /// Back from System Settings, Full Disk Access may have been switched on; checking never prompts.
    func refreshFileAccess() {
        hasFullDiskAccess = FileAccess.hasFullDiskAccess
    }

    /// macOS's own prompts for the Desktop, Documents, Downloads and iCloud Drive, one after another, now
    /// rather than at the first drop from each.
    func askForFolders() {
        guard !isAskingForFolders else { return }
        isAskingForFolders = true
        FileAccess.request(FileAccess.Folder.present, answered: { [weak self] folder, allowed in
            self?.folderAnswers[folder] = allowed
        }, finished: { [weak self] in
            self?.isAskingForFolders = false
        })
    }
}

/// Tuck's first-run setup, and the tutorial it becomes when reopened from Settings. Created when shown
/// and released, with its SwiftUI tree, when closed, like Settings.
final class SetupWindowController: NSObject, NSWindowDelegate {
    /// Wide enough for the pretend desktop and a row of tiles; reading steps are narrowed inside it.
    static let size = CGSize(width: 840, height: 600)

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
        guard setup.step == .permission else { return }
        setup.app.accessibilityChanged(trusted: AX.isTrusted)
        setup.refreshFileAccess()
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onClose?() }
    }
}
