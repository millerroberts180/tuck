import AppKit
import ServiceManagement
import SwiftUI
import TuckCore

// Each pane is a grouped form. Settings that depend on a switch dim while it's off; they never disappear.

struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: TuckModel
    let onOpenTutorial: () -> Void
    /// Read from the system's login-item list, never stored: the list is the truth.
    @State private var login = LoginItem.status

    private var openAtLogin: Binding<Bool> {
        Binding(get: { login == .enabled || login == .requiresApproval },
                set: { on in
                    LoginItem.set(on)
                    login = LoginItem.status
                })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: openAtLogin) {
                    Text("Open at login")
                    Text(LoginItem.isAvailable ? "Starts Tuck when you log in." : "Available when Tuck runs as an app.")
                }
                .disabled(!LoginItem.isAvailable)
                if login == .requiresApproval {
                    LabeledContent {
                        Button { SMAppService.openSystemSettingsLoginItems() } label: {
                            ActionLabel(title: "Open Login Items…", symbol: "arrow.up.forward.app")
                        }
                        .buttonStyle(ActionButtonStyle())
                    } label: {
                        Text("Waiting for your approval")
                        Text("Allow Tuck in System Settings › General › Login Items.")
                    }
                }
                Toggle(isOn: $settings.menuBarIconShown) {
                    Text("Show in menu bar")
                    Text("While it's hidden, open Settings with a secondary click along the top of Tuck's open fold, or by opening Tuck again.")
                }
                Toggle(isOn: $settings.hapticsEnabled) {
                    Text("Haptic feedback")
                    Text("A light tap on Force Touch trackpads when a drag reaches Tuck, when it lands, and when a window snaps into place.")
                }
            }

            Section("Permissions") {
                AccessibilityRow(trusted: model.accessibilityTrusted,
                                 detail: "Needed to tuck, restore and arrange windows, and for modifier-drag and the mouse wheel. Tuck asks during setup or the first time you use one, never at launch.")
            }

            Section {
                LabeledContent {
                    Button(action: onOpenTutorial) {
                        ActionLabel(title: "Open Tutorial…", symbol: "graduationcap")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    Text("Tutorial")
                    Text("The tour from setup: tucking a window, holding a file, the extras, and the notch's swipes.")
                }
            }

            Section {
                LabeledContent {
                    Button { NSApp.terminate(nil) } label: {
                        ActionLabel(title: "Quit Tuck", symbol: "power")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    Text("Leave the notch and menu bar")
                    Text("Any rested app wakes first.")
                }
            }
        }
        .formStyle(.grouped)
        // Login items can also be changed in System Settings while this window is closed.
        .onAppear { login = LoginItem.status }
    }
}

struct NotchPane: View {
    @ObservedObject var settings: SettingsStore

    private var styleDetail: String {
        switch settings.notchlessStyle {
        case .bubble: "A small bubble floats in the middle of the menu bar."
        case .notch: "A black notch hangs from the top edge, over the middle of the menu bar."
        }
    }

    var body: some View {
        Form {
            Section {
                ChoiceRow("Show Tuck on") {
                    VisualChoice(options: SurfaceDisplays.allCases.map { .init(value: $0, title: $0.title) },
                                 selection: $settings.surfaceDisplays) { displays, selected in
                        DisplaysArt(symbols: displays.symbols, highlighted: selected)
                    }
                }
            } header: {
                Text("Displays")
            } footer: {
                FooterNote("When no display matches, for example with the lid closed, Tuck uses the one with the menu bar.")
            }

            Section {
                ChoiceRow("Displays without a notch") {
                    VisualChoice(options: NotchlessStyle.allCases.map { .init(value: $0, title: $0.title) },
                                 selection: $settings.notchlessStyle) { style, selected in
                        NotchStyleArt(drawsNotch: style == .notch, highlighted: selected)
                    }
                    Text(styleDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Style")
            }

            Section {
                ChoiceRow("Cards in a row") {
                    VisualChoice(options: CardLayout.columnChoices.map { .init(value: $0, title: "\($0)") },
                                 selection: $settings.cardColumns) { columns, selected in
                        CardsArt(columns: columns, size: settings.cardSize, highlighted: selected)
                    }
                }
                ChoiceRow("Card size") {
                    VisualChoice(options: CardSize.allCases.map { .init(value: $0, title: $0.title) },
                                 selection: $settings.cardSize) { size, selected in
                        CardsArt(columns: settings.cardColumns, size: size, highlighted: selected)
                    }
                }
            } header: {
                Text("Cards")
            } footer: {
                FooterNote("The fold opens on one row of cards; swipe sideways along it for the rest, or down to see them all. On a smaller display the cards shrink to fit.")
            }

            Section {
                Toggle(isOn: $settings.showInFullScreen) {
                    Text("Show beside full-screen apps")
                    Text("Stays at the top of the screen while an app is full screen.")
                }
                Toggle(isOn: $settings.showInScreenshots) {
                    Text("Show in screenshots and recordings")
                    Text("Turn off to leave Tuck, and windows flying into it, out of them.")
                }
            } header: {
                Text("Visibility")
            }

            Section("Always") {
                AlwaysLabel("On every Space", systemImage: "square.on.square")
                AlwaysLabel("Never in Mission Control, the Dock or the app switcher", systemImage: "rectangle.3.group")
            }
        }
        .formStyle(.grouped)
    }
}

/// The fold drawn small for the Cards choices: a row of cards hanging from the menu bar as the fold does,
/// as many and as big as the choice, in the accent colour when chosen.
struct CardsArt: View {
    let columns: Int
    let size: CardSize
    let highlighted: Bool

    var body: some View {
        let ink = highlighted ? Color.accentColor : Color.secondary
        let card = CGSize(width: 12 * size.scale, height: 5 * size.scale)
        ZStack(alignment: .top) {
            Color.primary.opacity(0.07)
                .frame(height: 9)
            HStack(spacing: 2) {
                ForEach(0..<columns, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5 * size.scale, style: .continuous)
                        .fill(ink)
                        .frame(width: card.width, height: card.height)
                }
            }
            .padding(.horizontal, 3)
            .padding(.top, 8)
            .padding(.bottom, 3)
            .background(UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4, style: .continuous)
                .fill(ink.opacity(0.22)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct WindowsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: TuckModel

    var body: some View {
        Form {
            if !model.accessibilityTrusted {
                Section {
                    AccessibilityRow(trusted: false, detail: "Modifier-drag needs it to move and resize other apps' windows.")
                }
            }

            Section {
                Toggle(isOn: $settings.windowDragEnabled) {
                    Text("Move and resize with a modifier-drag")
                    Text("Hold \(settings.windowDragModifiers.title) and drag anywhere in a window, not just its title bar.")
                }
                ChoiceRow("Keys") {
                    VisualChoice(options: WindowDragModifiers.allCases.map { .init(value: $0, title: $0.name) },
                                 selection: $settings.windowDragModifiers) { keys, selected in
                        KeycapsArt(symbols: keys.symbols, highlighted: selected)
                    }
                }
                .disabled(!settings.windowDragEnabled)
            } header: {
                Text("Move and resize")
            } footer: {
                FooterNote("While modifier-drag is off, Tuck doesn't watch the mouse at all.")
            }

            Section("How it works") {
                AlwaysLabel("Drag to move the window.", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                AlwaysLabel("Right-drag, or add ⇧, to resize from the nearest corner.", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyboardPane: View {
    @ObservedObject var settings: SettingsStore

    private var defaultsList: String {
        let titles = ShortcutAction.allCases.map(\.defaultShortcut.title)
        return titles.dropLast().joined(separator: ", ") + " and " + (titles.last ?? "")
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.shortcutsEnabled) {
                    Text("Use keyboard shortcuts")
                    Text("They work from any app. While they're off, Tuck registers none.")
                }
            }

            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(settings: settings, action: action)
                    }
                }
                LabeledContent {
                    Button(action: settings.resetShortcuts) {
                        ActionLabel(title: "Restore Defaults", symbol: "arrow.counterclockwise")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(settings.shortcuts == .defaults)
                } label: {
                    Text("Default shortcuts")
                    Text(defaultsList)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                FooterNote("Click a shortcut, then type a new one; Escape cancels and Delete clears it. Each uses at least two of ⌃ ⌥ ⌘, so none takes over an app's own shortcut.")
            }
            .disabled(!settings.shortcutsEnabled)
        }
        .formStyle(.grouped)
    }
}

struct MousePane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: TuckModel
    /// Where the chosen Feel tile's dot is along its glide; animated when a Feel is picked.
    @State private var glide: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            if !model.accessibilityTrusted {
                Section {
                    AccessibilityRow(trusted: false, detail: "Smooth scrolling and reversing the wheel need it to adjust scrolling in other apps.")
                }
            }

            Section {
                Toggle(isOn: $settings.smoothScrollingEnabled) {
                    Text("Smooth scrolling")
                    Text("Turns each notch of a mouse wheel into a short glide.")
                }
                ChoiceRow("Feel") {
                    VisualChoice(options: ScrollSmoothness.allCases.map { .init(value: $0, title: $0.title) },
                                 selection: $settings.scrollSmoothness, onPick: { _ in playGlide() }) { smoothness, selected in
                        GlideArt(timeConstant: smoothness.timeConstant, highlighted: selected, progress: selected ? glide : 1)
                    }
                }
                .disabled(!settings.smoothScrollingEnabled)
            } header: {
                Text("Mouse wheel")
            }

            Section {
                Toggle(isOn: $settings.reverseMouseWheel) {
                    Text("Reverse mouse wheel direction")
                    Text("Flips the wheel only, so a trackpad can keep natural scrolling.")
                }
            } header: {
                Text("Direction")
            } footer: {
                FooterNote("Trackpads, Magic Mouse and scrolling with a modifier held are left alone. While both options are off, Tuck doesn't see scrolling at all.")
            }
        }
        .formStyle(.grouped)
    }

    /// Plays the picked glide once, at its real speed.
    private func playGlide() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { glide = 0 }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: GlideArt.duration)) { glide = 1 }
        }
    }
}

struct RestPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: TuckModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.restEnabled) {
                    Text("Allow resting tucked apps")
                    Text(RestSafetyPolicy.firstUseExplanation)
                }
            }

            Section {
                if RestApp.installed.isEmpty {
                    Text("None of them is on this Mac.")
                        .foregroundStyle(.secondary)
                }
                ForEach(RestApp.installed) { app in
                    LabeledContent {
                        if model.restingBundleIDs.contains(app.id) {
                            Label("Resting", systemImage: "moon.zzz")
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            // A fixed square, so icons of every shape line up in a column.
                            AppIconView(bundleID: app.id)
                                .frame(width: 22, height: 22)
                            Text(app.name)
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Only offline document apps can rest for now, once all their windows are tucked.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Apps that can rest")
                }
                .textCase(nil)
            } footer: {
                FooterNote("Restoring a window wakes its app. Turning Rest off wakes every rested app.")
            }
        }
        .formStyle(.grouped)
    }
}

struct HeldPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: TuckModel
    let onClear: () -> Void
    @State private var confirmingTurnOff = false

    private var kept: String {
        switch model.clipboard.entries.count {
        case 0: "Nothing kept yet"
        case 1: "1 item kept"
        case let count: "\(count) items kept"
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.dropInvitation) {
                    Text("Widen when a drag comes near")
                    Text("While you drag files, links or text toward the notch, Tuck widens into one target that says what it will hold. While this is off, Tuck doesn't watch drags; you can still drop straight onto it.")
                }
            } header: {
                Text("Drops")
            }

            Section {
                Toggle(isOn: $settings.showsCopyTimes) {
                    Text("Show when each was copied")
                    Text("Each tile shows the time it was copied or dropped in: the hour today, the day before that. Search finds times either way, as “3pm” or “this morning”.")
                }
            } header: {
                Text("Tiles")
            }

            FileAccessSection()

            Section {
                Toggle(isOn: ClipboardHistorySwitch.binding(settings: settings, model: model, asking: $confirmingTurnOff)) {
                    Text("Clipboard history")
                    Text("Text, links, images, files and colours you copy on this Mac appear in Tuck under Copied, each shown as what it is, ready to copy again. To preview a link, Tuck opens its page once for the title, icon and picture; for an address, it asks Apple Maps for the map. Capture is off until you turn this on.")
                }
                if settings.clipboardHistoryEnabled && model.clipboardAccessHeldBack {
                    LabeledContent {
                        Button(action: ClipboardCaptureService.openPasteSettings) {
                            ActionLabel(title: "Open Settings…", symbol: "lock.open")
                        }
                        .buttonStyle(ActionButtonStyle())
                    } label: {
                        Text("Paste from Other Apps")
                        Text("macOS is holding back what other apps copy. Set Tuck to Allow there, and capture resumes with your next copy.")
                    }
                }
                Toggle(isOn: $settings.clipboardReadsImageText) {
                    Text("Read text in copied images")
                    Text("Words in images and screenshots are read on this Mac, once, so a search finds them and you can copy them out.")
                }
                .disabled(!settings.clipboardHistoryEnabled)
                ChoiceRow("Keep items for") {
                    VisualChoice(options: ClipboardRetention.allCases.map { .init(value: $0, title: $0.title) },
                                 selection: $settings.clipboardRetention) { retention, selected in
                        RetentionArt(reach: retention.reach, highlighted: selected)
                    }
                }
                .disabled(!settings.clipboardHistoryEnabled)
                LabeledContent {
                    Button(action: onClear) {
                        ActionLabel(title: "Clear Clipboard History", symbol: "trash")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(!settings.clipboardHistoryEnabled || model.clipboard.entries.isEmpty)
                } label: {
                    Text(kept)
                    Text("Clearing can't be undone.")
                }
            } header: {
                Text("Clipboard")
            }

            Section("Always") {
                AlwaysLabel("Knows links, code, colours, contacts, dates and more by what they are", systemImage: "sparkles")
                AlwaysLabel("Skips anything apps mark as private", systemImage: "eye.slash")
                AlwaysLabel("Shows keys and tokens masked", systemImage: "key")
                AlwaysLabel("Keeps history on this Mac only", systemImage: "lock")
            }
        }
        .formStyle(.grouped)
        .clipboardTurnOffPrompt(isPresented: $confirmingTurnOff, settings: settings, model: model, onDelete: onClear)
    }
}

/// The clipboard history switch, here and in setup's Choose step. Turning it off with something saved asks
/// first whether to keep that or delete it, since what was copied may be private and the person may want
/// it gone with the switch. With nothing saved there is nothing to ask.
enum ClipboardHistorySwitch {
    static let title = "Turn off clipboard history?"
    static let keep = "Keep History"
    static let delete = "Delete History"

    static func message(saved count: Int) -> String {
        let saved = count == 1 ? "the item it has saved" : "the \(count) items it has saved"
        return "Tuck stops saving what you copy. Keep \(saved) for when you turn it on again, or delete "
            + (count == 1 ? "it now." : "them now.")
    }

    /// The setting, except that turning it off with history saved asks instead, leaving it on until answered.
    static func binding(settings: SettingsStore, model: TuckModel, asking: Binding<Bool>) -> Binding<Bool> {
        Binding {
            settings.clipboardHistoryEnabled
        } set: { on in
            if !on, !model.clipboard.entries.isEmpty {
                asking.wrappedValue = true
            } else {
                settings.clipboardHistoryEnabled = on
            }
        }
    }
}

extension View {
    /// Keep leaves the history as turning off always has: saved, and expiring as chosen in Settings. Delete
    /// is Clear Clipboard History, set-aside files and all. Cancel leaves history on.
    func clipboardTurnOffPrompt(isPresented: Binding<Bool>, settings: SettingsStore, model: TuckModel,
                                onDelete: @escaping () -> Void) -> some View {
        alert(ClipboardHistorySwitch.title, isPresented: isPresented) {
            Button(ClipboardHistorySwitch.keep) { settings.clipboardHistoryEnabled = false }
                .keyboardShortcut(.defaultAction)
            Button(ClipboardHistorySwitch.delete, role: .destructive) {
                onDelete()
                settings.clipboardHistoryEnabled = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ClipboardHistorySwitch.message(saved: model.clipboard.entries.count))
        }
    }
}

struct AboutPane: View {
    let supportFolder: URL
    let onUninstall: () -> Void
    @State private var confirmingUninstall = false
    /// Counted when Uninstall is chosen, so the confirmation can say how many saved files go with Tuck.
    @State private var savedFiles = 0

    private var received: ReceivedFileStore { SupportFolder(directory: supportFolder).received }

    private var version: String {
        guard let version = ReleaseInfo.version else { return "Development build" }
        return "Version \(version.short)" + (version.build.map { " (\($0))" } ?? "")
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    TuckMark(size: 64)
                    Text("Tuck")
                        .font(.system(size: 20, weight: .semibold))
                    Text(version)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("A quiet holding space in the notch for windows, files, links and text you put there.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if !ReleaseInfo.copyright.isEmpty {
                        Text(ReleaseInfo.copyright)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }

            Section {
                LabeledContent("Website") {
                    Link(ReleaseInfo.websiteURL.host() ?? ReleaseInfo.websiteURL.absoluteString, destination: ReleaseInfo.websiteURL)
                }
                LabeledContent("Support") {
                    Link(ReleaseInfo.supportTitle, destination: ReleaseInfo.supportURL ?? ReleaseInfo.supportMailURL)
                }
                LabeledContent("Privacy policy") {
                    Link("Read", destination: ReleaseInfo.privacyPolicyURL)
                }
                LabeledContent("Licence agreement") {
                    Link("Read", destination: ReleaseInfo.eulaURL)
                }
            } header: {
                Text("Links")
            } footer: {
                FooterNote("They open in your browser or mail app. Tuck itself goes online only to preview a link or address you copy, while clipboard history is on in Held.")
            }

            Section {
                LabeledContent {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([supportFolder])
                    } label: {
                        ActionLabel(title: "Show in Finder", symbol: "folder")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(!FileManager.default.fileExists(atPath: supportFolder.path))
                } label: {
                    Text("Tuck's library")
                    Text("What you've tucked, and files Tuck received, in Application Support.")
                }
                LabeledContent {
                    Button {
                        savedFiles = received.fileCount()
                        confirmingUninstall = true
                    } label: {
                        ActionLabel(title: "Uninstall Tuck…", symbol: "trash")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    Text("Uninstall")
                    Text("Brings back every tucked window first, then removes Tuck and everything it keeps.")
                }
            } header: {
                Text("Data")
            }

            Section("Always") {
                AlwaysLabel("No account; online only to preview what you copy", systemImage: "person.slash")
                AlwaysLabel("Never collects anything on its own", systemImage: "hand.raised")
                AlwaysLabel("What you tuck, hold and copy stays on this Mac", systemImage: "lock")
            }
        }
        .formStyle(.grouped)
        .alert("Uninstall Tuck?", isPresented: $confirmingUninstall) {
            Button("Uninstall", role: .destructive, action: onUninstall)
            if savedFiles > 0 {
                Button("Show Files") { NSWorkspace.shared.open(received.directory) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(uninstallMessage)
        }
    }

    /// Files Tuck saved itself, such as a Mail message or an image dragged from a browser, may exist
    /// nowhere else, so the confirmation counts them and offers to show them first.
    private var uninstallMessage: String {
        let steps = "Tuck brings back every tucked window and wakes any rested app. Then it turns off Open at Login, "
            + "deletes its library and settings, resets its permissions and moves itself to the Trash."
        let kept = "Files you dropped from elsewhere stay where they are."
        guard savedFiles > 0 else { return steps + " " + kept }
        let saved = savedFiles == 1
            ? "It also deletes a file it saved from a drop, such as a Mail message or an image from a browser. It may be the only copy, so choose Show Files to keep it."
            : "It also deletes \(savedFiles) files it saved from drops, such as Mail messages or images from a browser. They may be the only copies, so choose Show Files to keep any you want."
        return steps + "\n\n" + saved + "\n\n" + kept
    }
}

// MARK: - What the panes show

/// An allow-listed app that is on this Mac, for the Rest pane's list. Resolved once.
private struct RestApp: Identifiable {
    let id: String
    let name: String

    static let installed: [RestApp] = RestSafetyPolicy.allowList.compactMap { bundleID in
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        return RestApp(id: bundleID, name: name)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

private extension WindowDragModifiers {
    var name: String {
        switch self {
        case .controlOption: "Control-Option"
        case .controlCommand: "Control-Command"
        case .controlOptionCommand: "Control-Option-Command"
        }
    }

    /// Symbols rather than ⌃ ⌥ ⌘ characters, which sit at different heights in the system font.
    var symbols: [String] {
        switch self {
        case .controlOption: ["control", "option"]
        case .controlCommand: ["control", "command"]
        case .controlOptionCommand: ["control", "option", "command"]
        }
    }
}

private extension SurfaceDisplays {
    var symbols: [String] {
        switch self {
        case .all: ["laptopcomputer", "display"]
        case .builtIn: ["laptopcomputer"]
        case .external: ["display"]
        }
    }
}

private extension ClipboardRetention {
    /// How far back the history reaches, drawn on a track; nil for no limit.
    var reach: Double? {
        switch self {
        case .oneHour: 0.2
        case .oneDay: 0.45
        case .oneWeek: 0.75
        case .untilCleared: nil
        }
    }
}

/// Whether macOS lets Tuck read files dropped from anywhere, with the same two ways as setup: Full Disk
/// Access for every place at once, or the usual folders asked for now. Coming back to the window from
/// System Settings looks again; looking never prompts.
struct FileAccessSection: View {
    @State private var hasFullDiskAccess = FileAccess.hasFullDiskAccess
    @State private var answers: [FileAccess.Folder: Bool] = [:]
    @State private var isAsking = false

    var body: some View {
        Section {
            if hasFullDiskAccess {
                LabeledContent {
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                } label: {
                    Text("Full Disk Access")
                    Text("Files from anywhere, external and network drives included, without a question.")
                }
            } else {
                LabeledContent {
                    Button(action: FileAccess.openFullDiskAccessSettings) {
                        ActionLabel(title: "Open System Settings…", symbol: "externaldrive.badge.checkmark")
                    }
                    .buttonStyle(ActionButtonStyle())
                } label: {
                    Text("Full Disk Access")
                    Text("Covers every place at once, so a drop never stops for a question. Turn Tuck on in Privacy & Security › Full Disk Access.")
                }
                LabeledContent {
                    Button {
                        isAsking = true
                        FileAccess.request(FileAccess.Folder.present, answered: { answers[$0] = $1 },
                                           finished: { isAsking = false })
                    } label: {
                        ActionLabel(title: answers.isEmpty ? "Ask Now" : "Ask Again", symbol: "folder.badge.questionmark")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(isAsking)
                } label: {
                    Text("Or just the usual folders")
                    Text(answers.isEmpty
                         ? "macOS asks about the Desktop, Documents, Downloads and iCloud Drive now, rather than at the first drop from each. An external drive is asked about the first time you drop from it."
                         : FileAccess.Folder.present.compactMap { folder in
                             answers[folder].map { "\(folder.title): \($0 ? "allowed" : "not allowed")" }
                         }.joined(separator: " · "))
                }
            }
        } header: {
            Text("File access")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            hasFullDiskAccess = FileAccess.hasFullDiskAccess
        }
    }
}
