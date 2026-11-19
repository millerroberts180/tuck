import AppKit
import Carbon.HIToolbox
import SwiftUI
import TuckCore

/// Click, then type the new shortcut. Escape cancels and Delete clears. Keys are read only from Tuck's
/// own Settings window, and only while it is recording.
struct ShortcutRecorder: View {
    @ObservedObject var settings: SettingsStore
    let action: ShortcutAction
    @State private var monitor: Any?
    @State private var message: String?

    private var isRecording: Bool { settings.recordingShortcut == action }

    private var title: String {
        if isRecording { return "Type shortcut…" }
        return settings.shortcuts.shortcut(for: action)?.title ?? "None"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button(action: { isRecording ? stop() : start() }) {
                Text(title)
                    .frame(minWidth: 96)
            }
            .help(isRecording ? "Escape cancels, Delete clears" : "Click, then type a new shortcut")
            .accessibilityLabel("\(action.title) shortcut")
            .accessibilityValue(isRecording ? "Recording" : title)
            if let message {
                warning(message)
            } else if settings.refusedShortcuts.contains(action), !isRecording {
                warning("macOS or another app already uses this; choose another.")
            }
        }
        .onChange(of: settings.recordingShortcut) { _, recording in
            if recording != action { removeMonitor() }
        }
        .onDisappear(perform: stop)
    }

    /// A refusal, readable in light and dark: secondary text marked with an orange warning symbol.
    private func warning(_ text: String) -> some View {
        Label {
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.caption)
    }

    private func start() {
        message = nil
        settings.recordingShortcut = action
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        let modifiers = KeyShortcut.Modifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let code = UInt32(event.keyCode)
        if modifiers.isEmpty, code == UInt32(kVK_Escape) { return stop() }
        if modifiers.isEmpty, code == UInt32(kVK_Delete) || code == UInt32(kVK_ForwardDelete) {
            settings.assign(nil, to: action)
            return stop()
        }
        let shortcut = KeyShortcut(keyCode: code,
                                   key: KeyShortcut.label(forKeyCode: code, characters: event.charactersIgnoringModifiers),
                                   modifiers: modifiers)
        switch settings.assign(shortcut, to: action) {
        case .assigned: stop()
        case .rejected(let reason): message = reason
        }
    }

    private func stop() {
        removeMonitor()
        message = nil
        if settings.recordingShortcut == action { settings.recordingShortcut = nil }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
