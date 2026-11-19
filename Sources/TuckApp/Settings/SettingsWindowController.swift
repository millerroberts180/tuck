import AppKit
import SwiftUI

/// Creates the Settings window on demand and releases it (and its SwiftUI tree) when closed.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let model: TuckModel
    private let supportFolder: URL
    private let onClearClipboard: () -> Void
    private let onOpenTutorial: () -> Void
    private let onUninstall: () -> Void
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(settings: SettingsStore, model: TuckModel, supportFolder: URL, onClearClipboard: @escaping () -> Void,
         onOpenTutorial: @escaping () -> Void, onUninstall: @escaping () -> Void) {
        self.settings = settings
        self.model = model
        self.supportFolder = supportFolder
        self.onClearClipboard = onClearClipboard
        self.onOpenTutorial = onOpenTutorial
        self.onUninstall = onUninstall
    }

    /// `activating: false` brings the window forward without taking focus from the app in use. A pane
    /// turns Settings to it, open or not; without one, an open window stays where it is and a new one
    /// opens at General.
    func show(pane: SettingsPane? = nil, activating: Bool = true) {
        if let pane {
            navigation.pane = pane
        } else if window == nil {
            navigation.pane = .general
        }
        if window == nil {
            let view = SettingsView(settings: settings, model: model, supportFolder: supportFolder,
                                    onClearClipboard: onClearClipboard, onOpenTutorial: onOpenTutorial,
                                    onUninstall: onUninstall, navigation: navigation)
            let window = TuckWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size),
                                    styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Tuck Settings"
            Self.styleTitleBar(of: window)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: view)
            window.delegate = self
            window.center()
            self.window = window
        }
        if activating {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
        // An agent app's activation can be declined while another app is in use; the window still
        // comes to the front.
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // A shortcut being typed ends with the window, so its key monitor goes and the shortcuts return.
        settings.recordingShortcut = nil
        DispatchQueue.main.async { [weak self] in self?.window = nil }
    }

    /// The sidebar runs up under a transparent title bar, as in System Settings. An empty unified toolbar
    /// makes the bar as tall as the pane header, so the header sits level with the window buttons.
    static func styleTitleBar(of window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "TuckSettings")
        window.toolbarStyle = .unified
    }
}

/// Settings and setup. Tuck has no main menu, so ⌘W, which a menu would supply, is handled here.
final class TuckWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
