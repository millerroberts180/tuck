#if DEBUG
import AppKit
import SwiftUI
import TuckCore

/// `Tuck --snapshot-ui <folder>` (debug builds): renders every Settings pane, in Light, Dark and both
/// Increase Contrast appearances, with the switches off and on, and every setup step and its states, to
/// PNGs off screen, so layouts can be checked without opening a window. Uses a throwaway defaults suite
/// and library, both removed afterwards; the person's own are never read. About is also rendered at full
/// length (`settings-about-full-…`), and the prompt for turning clipboard history off with two items
/// saved (`settings-held-turn-off-…`).
///
/// Known artifact: the transparent title-bar strip renders white off screen, so a dark pane header can
/// look blank here. Check that in a real window.
@MainActor
enum SettingsSnapshots {
    private static let suiteName = "app.tuck.snapshots"

    static func render(to folder: String) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("tuck-snapshots-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: scratch)
        }

        for state in ["off", "on"] {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            guard let defaults = UserDefaults(suiteName: suiteName) else { return }
            let settings = SettingsStore(defaults: defaults)
            var clipboard = ClipboardHistory(isEnabled: true)
            if state == "on" {
                clipboard.record(text: "Meeting notes for Thursday")
                clipboard.record(text: "https://example.com/report")
            }
            let model = makeModel(library: scratch.appendingPathComponent("library-\(state).json"), clipboard: clipboard)
            if state == "on" {
                settings.hapticsEnabled = true
                settings.windowDragEnabled = true
                settings.shortcutsEnabled = true
                settings.smoothScrollingEnabled = true
                settings.restEnabled = true
                settings.clipboardHistoryEnabled = true
                settings.showsCopyTimes = true
                settings.surfaceDisplays = .builtIn
                settings.notchlessStyle = .notch
                settings.cardColumns = 5
                settings.cardSize = .large
                settings.showInScreenshots = false
                model.accessibilityChanged(trusted: true)
            } else {
                model.accessibilityChanged(trusted: false)
            }
            let appearances: [(NSAppearance.Name, String)] = [(.aqua, "light"), (.darkAqua, "dark"),
                                                              (.accessibilityHighContrastAqua, "contrast-light"),
                                                              (.accessibilityHighContrastDarkAqua, "contrast-dark")]
            for (appearance, suffix) in appearances {
                for pane in SettingsPane.allCases {
                    save(view(settings: settings, model: model, folder: scratch, pane: pane), appearance: appearance,
                         to: output.appendingPathComponent("settings-\(pane.rawValue)-\(state)-\(suffix).png"))
                }
                if state == "off" {
                    renderSetup(settings: settings, model: model, appearance: appearance, suffix: suffix, to: output)
                    // About at full length, without the window, so the Data section and Uninstall show.
                    let about = CGSize(width: SettingsView.size.width - 150, height: 980)
                    save(AboutPane(supportFolder: scratch, onUninstall: {}).frame(width: about.width, height: about.height),
                         size: about, settingsTitleBar: false, appearance: appearance,
                         to: output.appendingPathComponent("settings-about-full-\(suffix).png"))
                }
                // Notch at full length, without the window, so the Cards section shows.
                let notch = CGSize(width: SettingsView.size.width - 150, height: 960)
                save(NotchPane(settings: settings).frame(width: notch.width, height: notch.height),
                     size: notch, settingsTitleBar: false, appearance: appearance,
                     to: output.appendingPathComponent("settings-notch-full-\(state)-\(suffix).png"))
                if state == "on" {
                    saveAlert(title: ClipboardHistorySwitch.title,
                              message: ClipboardHistorySwitch.message(saved: model.clipboard.entries.count),
                              buttons: [ClipboardHistorySwitch.keep, ClipboardHistorySwitch.delete, "Cancel"], destructive: 1,
                              appearance: appearance, to: output.appendingPathComponent("settings-held-turn-off-\(suffix).png"))
                }
            }
        }
    }

    /// A SwiftUI alert doesn't render off screen, so a prompt is drawn as an NSAlert with the same text and
    /// buttons. That is what macOS shows, though in the app it hangs from the window as a sheet, with
    /// Tuck's icon where this has the bare executable's. Its material renders clear off screen, so the
    /// window background is painted behind it.
    private static func saveAlert(title: String, message: String, buttons: [String], destructive: Int?,
                                  appearance: NSAppearance.Name, to url: URL) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        if let destructive { alert.buttons[destructive].hasDestructiveAction = true }
        alert.window.appearance = NSAppearance(named: appearance)
        alert.layout()
        let window = alert.window
        window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        defer { window.orderOut(nil) }
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let canvas = bitmap.copy() as? NSBitmapImageRep,
              let context = NSGraphicsContext(bitmapImageRep: canvas) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let bounds = CGRect(origin: .zero, size: bitmap.size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
        bitmap.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        try? canvas.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func view(settings: SettingsStore, model: TuckModel, folder: URL, pane: SettingsPane) -> SettingsView {
        SettingsView(settings: settings, model: model, supportFolder: folder, onClearClipboard: {}, onOpenTutorial: {},
                     onUninstall: {}, navigation: SettingsNavigation(pane: pane))
    }

    private static func makeModel(library: URL, clipboard: ClipboardHistory) -> TuckModel {
        TuckModel(
            parking: AccessibilityParkingService(),
            rest: ProcessRestService(),
            opener: WorkspaceItemOpener(),
            pasteboard: SystemPasteboard(),
            haptics: SystemHaptics(isEnabled: false),
            persistence: FileLibraryPersistence(fileURL: library),
            clipboard: clipboard,
            receivedFiles: nil
        )
    }

    /// Every setup step, numbered in order, then each state a step can show: Accessibility allowed; the
    /// practice with nothing, some and everything done, and on a bubble; the finish with the menu-bar item
    /// hidden; and the tutorial. Steps show the notch unless a shot says otherwise.
    private static func renderSetup(settings: SettingsStore, model: TuckModel, appearance: NSAppearance.Name,
                                    suffix: String, to output: URL) {
        func shot(_ name: String, tutorial: Bool = false, trusted: Bool = false, _ configure: (SetupModel) -> Void) {
            model.accessibilityChanged(trusted: trusted)
            defer { model.accessibilityChanged(trusted: false) }
            let setup = SetupModel(settings: settings, app: model, tutorialOnly: tutorial)
            setup.hasNotch = true
            configure(setup)
            save(SetupView(setup: setup), size: SetupWindowController.size, settingsTitleBar: false,
                 appearance: appearance, to: output.appendingPathComponent("setup-\(name)-\(suffix).png"))
        }
        for step in SetupStep.allCases {
            shot("\(step.rawValue)-\(step)") { $0.step = step }
        }
        shot("accessibility-allowed", trusted: true) { $0.step = .accessibility }
        shot("practice-start", trusted: true) { $0.step = .practice }
        shot("practice-part", trusted: true) { setup in
            setup.step = .practice
            setup.practice.record(.opened)
            setup.practice.record(.tucked(count: 1))
        }
        shot("practice-all", trusted: true) { setup in
            setup.step = .practice
            for event in [SetupPractice.Event.opened, .tucked(count: 1), .restored(.moved), .dropped(count: 1)] {
                setup.practice.record(event)
            }
        }
        shot("practice-bubble", trusted: true) { setup in
            setup.step = .practice
            setup.hasNotch = false
            setup.practice.record(.opened)
        }
        shot("done-no-menu-bar") { setup in
            setup.step = .done
            settings.menuBarIconShown = false
        }
        settings.menuBarIconShown = true
        shot("tutorial", tutorial: true, trusted: true) { _ in }
    }

    private static func save<V: View>(_ view: V, size: CGSize? = nil, settingsTitleBar: Bool = true,
                                      settle: TimeInterval = 0.3, appearance: NSAppearance.Name, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size ?? SettingsView.size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        if settingsTitleBar {
            SettingsWindowController.styleTitleBar(of: window)
        } else {
            window.titlebarAppearsTransparent = true
        }
        window.appearance = NSAppearance(named: appearance)
        let controller = NSHostingController(rootView: view)
        window.contentViewController = controller
        window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        let hosting = controller.view
        window.orderBack(nil)
        for _ in 0..<Int((settle / 0.05).rounded()) {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
#endif
