import AppKit
import SwiftUI
import TuckCore

/// Setup's content: the step showing, then a footer with progress dots, Back and Continue. Reading
/// steps sit at a comfortable width; the steps you do things in use the whole window, and the welcome,
/// Tuck's lockup alone, is centred in it.
struct SetupView: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch setup.step {
                case .welcome: WelcomeStep()
                case .tour: TourStep(setup: setup)
                case .choose: ChooseStep(settings: setup.settings, model: setup.app)
                case .gestures: GesturesStep(setup: setup, settings: setup.settings)
                case .permission: narrow { PermissionStep(setup: setup, app: setup.app) }
                case .done: narrow { DoneStep(setup: setup, settings: setup.settings) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 32)
            .padding(.top, setup.step == .welcome ? 0 : 34)

            Divider()
            HStack(spacing: 8) {
                progress
                Spacer()
                if !setup.isFirst {
                    Button("Back", action: setup.back)
                }
                Button(primaryTitle, action: setup.next)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: SetupWindowController.size.width, height: SetupWindowController.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var primaryTitle: String {
        guard setup.isLast else { return "Continue" }
        return setup.isTutorial ? "Done" : "Start Using Tuck"
    }

    private func narrow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(maxWidth: 600, alignment: .leading)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(setup.steps, id: \.self) { step in
                Circle()
                    .fill(step == setup.step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(setup.stepNumber) of \(setup.steps.count)")
    }
}

/// A step's title, then one or two sentences that say what to do.
struct StepTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
    }
}

/// Under a demo: one chip per thing to try, ticked as it happens, and a line saying what the latest
/// one means.
struct ExperiencedChips: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
    }

    let items: [Item]
    let done: Set<String>
    let latest: String?
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    let seen = done.contains(item.id)
                    HStack(spacing: 4) {
                        Image(systemName: seen ? "checkmark.circle.fill" : item.symbol)
                            .font(.system(size: 10, weight: .semibold))
                        Text(item.title).font(.system(size: 11, weight: seen ? .semibold : .regular))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(seen ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08)))
                    .foregroundStyle(seen ? Color.accentColor : Color.secondary)
                    .animation(.easeOut(duration: 0.2), value: seen)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.title), \(seen ? "done" : "not yet")")
                }
            }
            Text(latest ?? placeholder)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// MARK: - Reading steps

/// The first page: Tuck's lockup, the line above the wordmark, and nothing else. As it appears the line
/// draws itself out from the floor of its dip to its tails and greets as the notch does, and the
/// wordmark rises in under it; pointing at it greets again. Under Reduce Motion it is simply there.
struct WelcomeStep: View {
    @State private var drawn: CGFloat = Theme.reduceMotion ? 1 : 0
    @State private var isWordShown = Theme.reduceMotion
    @State private var greetings = 0
    @State private var lastGreeting = Date.distantPast

    /// The lockup's grid units per point: 285 pt wide, its line 16 pt thick.
    private static let scale: CGFloat = 0.66
    private static let wordInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? TuckLogo.paper : TuckLogo.ink
    })

    var body: some View {
        let scale = Self.scale
        let side = 256 * scale
        let style = StrokeStyle(lineWidth: TuckLogo.lineWidth(side: side), lineCap: .round, lineJoin: .round)
        let reach = TuckLogo.greetingReach
        ZStack(alignment: .topLeading) {
            KeyframeAnimator(initialValue: CGFloat(0), trigger: greetings) { greeting in
                LogoLine(reach: greeting)
                    .trim(from: 0.5 - drawn / 2, to: 0.5 + drawn / 2)
                    .stroke(Color(nsColor: TuckLogo.blue), style: style)
                    .frame(width: side, height: side)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(reach[1], duration: TuckLogo.greetingLeg(1))
                    CubicKeyframe(reach[2], duration: TuckLogo.greetingLeg(2))
                    CubicKeyframe(reach[3], duration: TuckLogo.greetingLeg(3))
                    CubicKeyframe(reach[4], duration: TuckLogo.greetingLeg(4))
                }
            }
            .offset(x: TuckLogo.stackedLineOrigin.x * scale, y: TuckLogo.stackedLineOrigin.y * scale)
            Path(TuckLogo.wordmarkPath(scale: scale))
                .stroke(Self.wordInk, style: style)
                .offset(x: TuckLogo.stackedWordOrigin.x * scale,
                        y: TuckLogo.stackedWordOrigin.y * scale + (isWordShown ? 0 : 10))
                .opacity(isWordShown ? 1 : 0)
        }
        .frame(width: TuckLogo.stackedSize.width * scale, height: TuckLogo.stackedSize.height * scale,
               alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { inside in if inside { greet() } }
        // A touch above the middle, where the eye puts the centre.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 44)
        .accessibilityElement()
        .accessibilityLabel("Welcome to Tuck")
        .accessibilityAddTraits(.isImage)
        .task {
            guard !Theme.reduceMotion else { return }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.9)) { drawn = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) { isWordShown = true }
            try? await Task.sleep(for: .milliseconds(420))
            greet()
        }
    }

    /// Once per arrival, as on the notch: a greeting under way is left to finish.
    private func greet() {
        guard !Theme.reduceMotion, Date().timeIntervalSince(lastGreeting) >= TuckLogo.greetingDuration else { return }
        lastGreeting = Date()
        greetings += 1
    }
}

/// Tuck's line as a shape, its dip at a reach (see `TuckLogo.linePath`), for a square frame.
struct LogoLine: Shape {
    var reach: CGFloat = 0

    func path(in rect: CGRect) -> Path { Path(TuckLogo.linePath(side: rect.width, reach: reach)) }
}

struct PermissionStep: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var app: TuckModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "Two permissions",
                      detail: "Allow access to your windows, then choose how broadly Tuck can read dropped files. Both stay on this Mac.")
            windows
                .padding(.bottom, 22)
            files
        }
        .animation(.easeOut(duration: 0.2), value: app.accessibilityTrusted)
        .animation(.easeOut(duration: 0.2), value: setup.hasFullDiskAccess)
        .animation(.easeOut(duration: 0.2), value: setup.folderAnswers)
    }

    private var windows: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Windows: \(AX.paneName)", symbol: "macwindow")
            check("To tuck, restore and arrange windows, Tuck reads which window is in front, and each window's app, title, position and size. Never what's inside, or anything you type.")
            if app.accessibilityTrusted {
                allowed("Access is on.")
            } else {
                Button(action: setup.requestAccessibility) {
                    ActionLabel(title: "Open System Settings…", symbol: "lock.open")
                }
                .buttonStyle(ActionButtonStyle())
                note("Turn Tuck on in Privacy & Security › \(AX.paneName). This page notices when you do.")
            }
        }
    }

    /// Full Disk Access covers every place at once, external drives included; the usual folders can
    /// instead be asked for now, one prompt each.
    private var files: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Files: from anywhere you drop them", symbol: "folder")
            check("Files stay where they are. Tuck keeps where each one is, and reads it to show its thumbnail, kind and size and to follow it if it moves. macOS asks the first time Tuck touches the Desktop, Documents, Downloads, iCloud Drive or an external drive.")
            if setup.hasFullDiskAccess {
                allowed("Full Disk Access is on: files from anywhere, external drives included.")
            } else {
                HStack(spacing: 8) {
                    Button(action: FileAccess.openFullDiskAccessSettings) {
                        ActionLabel(title: "Allow Full Disk Access…", symbol: "externaldrive.badge.checkmark")
                    }
                    .buttonStyle(ActionButtonStyle())
                    Button(action: setup.askForFolders) {
                        ActionLabel(title: setup.folderAnswers.isEmpty ? "Just the Usual Folders" : "Ask Again",
                                    symbol: "folder.badge.questionmark")
                    }
                    .buttonStyle(ActionButtonStyle())
                    .disabled(setup.isAskingForFolders)
                }
                if !setup.folderAnswers.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(FileAccess.Folder.present) { folder in
                            if let allowed = setup.folderAnswers[folder] {
                                Label(folder.title, systemImage: allowed ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(allowed ? Color.green : Color.secondary)
                                    .accessibilityLabel("\(folder.title), \(allowed ? "allowed" : "not allowed")")
                            }
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                note("For no later file-access prompts, turn Tuck on in Privacy & Security › Full Disk Access; macOS requires you to switch this on yourself, and this page notices when you return. Or ask now for Desktop, Documents, Downloads and iCloud Drive. That choice does not cover other folders or drives, which macOS may ask about when first used.")
            }
        }
    }

    private func header(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private func allowed(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.green)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func check(_ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle").foregroundStyle(Color.accentColor)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

struct DoneStep: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var settings: SettingsStore

    /// On a Mac without a notch, Tuck is a small bubble in the middle of the menu bar.
    private var hasNotch: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "You're set",
                      detail: hasNotch ? "Tuck lives in the notch at the top of your screen. While it holds nothing, the notch looks as it always has."
                                       : "Tuck lives in the middle of the menu bar, as a small bubble. It stays quiet until you use it.")
            VStack(alignment: .leading, spacing: 12) {
                line("Click it, or swipe down on it, to open Tuck.", symbol: "cursorarrow.click")
                line("Drag files, links or text onto it to hold them.", symbol: "tray.and.arrow.down")
                if settings.shortcutsEnabled {
                    line("Press \(settings.shortcuts.shortcut(for: .tuckFrontWindow)?.title ?? "your shortcut") to tuck the window in front, from any app.",
                         symbol: "keyboard")
                } else if settings.menuBarIconShown {
                    line("Tuck's menu-bar item can tuck the window in front, too.", symbol: "menubar.arrow.up.rectangle")
                }
                line("Change any of this in Settings, where you can also take this tour again.", symbol: "slider.horizontal.3")
            }
            .font(.system(size: 13))
            .padding(.bottom, 24)

            Toggle("Open Tuck at login", isOn: $setup.openAtLogin)
                .toggleStyle(.checkbox)
                .disabled(!LoginItem.isAvailable)
            if !LoginItem.isAvailable {
                Text("Available when Tuck runs as an app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func line(_ text: String, symbol: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
        }
    }
}
