import AppKit

@main
enum TuckMain {
    @MainActor
    static func main() {
        #if DEBUG
        // `Tuck --snapshot-ui <folder>` renders every Settings pane to PNGs off screen, then quits.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot-ui"), arguments.indices.contains(index + 1) {
            SettingsSnapshots.render(to: arguments[index + 1])
            return
        }
        // `Tuck --snapshot-panel <folder>` renders the open panel in each of its states, then quits.
        if let index = arguments.firstIndex(of: "--snapshot-panel"), arguments.indices.contains(index + 1) {
            PanelSnapshots.render(to: arguments[index + 1])
            return
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Agent app: no Dock icon, never steals focus from the app the person is using.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
