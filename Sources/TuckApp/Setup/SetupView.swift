import AppKit
import SwiftUI
import TuckCore

/// Setup's content: the step showing, then a footer with progress dots, Back and Continue. The tutorial
/// is one step, so it has no dots.
struct SetupView: View {
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch setup.step {
                case .accessibility: AccessibilityStep(setup: setup, app: setup.app)
                case .practice: PracticeStep(setup: setup, app: setup.app)
                case .done: DoneStep(setup: setup, settings: setup.settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32)
            .padding(.top, 34)

            Divider()
            HStack(spacing: 8) {
                if setup.steps.count > 1 { progress }
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

/// Tuck's line as a shape (see `TuckLogo.linePath`), for a square frame.
struct LogoLine: Shape {
    func path(in rect: CGRect) -> Path { Path(TuckLogo.linePath(side: rect.width)) }
}

// MARK: - Steps

/// The first page: Tuck's mark and what Tuck is, in a line, then the one permission tucking needs.
struct AccessibilityStep: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var app: TuckModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: TuckLogo.markImage(side: 40))
                .accessibilityHidden(true)
            Text("Tuck holds windows, files, links and text at the top of the screen until you need them.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 28)
            StepTitle(title: "Allow \(AX.paneName)",
                      detail: "To tuck, restore and arrange windows, Tuck reads which window is in front, and each window's app, title, position and size. Never what's inside, or anything you type.")
            VStack(alignment: .leading, spacing: 8) {
                if app.accessibilityTrusted {
                    Label("Access is on.", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Button(action: setup.requestAccessibility) {
                        ActionLabel(title: "Open System Settings…", symbol: "lock.open")
                    }
                    .buttonStyle(ActionButtonStyle())
                    Text("Turn Tuck on in Privacy & Security › \(AX.paneName). This page notices when you do.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.accessibilityTrusted)
    }
}

/// Tuck's core moves, done with the real Tuck on the real notch or bubble: each ticks off when Tuck
/// reports it (`SetupPractice`), whatever way it was done.
struct PracticeStep: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var app: TuckModel

    var body: some View {
        let place = setup.hasNotch ? "the notch" : "the bubble"
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: setup.hasNotch ? "Try it on the notch" : "Try it in the menu bar",
                      detail: setup.hasNotch ? "Tuck lives in the notch at the top of the screen. Each of these ticks off as you do it."
                                             : "Tuck lives in the small bubble in the middle of the menu bar. Each of these ticks off as you do it.")
            VStack(alignment: .leading, spacing: 14) {
                row(.open, title: "Open Tuck", symbol: "cursorarrow.click",
                    detail: setup.hasNotch ? "Click the notch." : "Click either end of the bubble, beside its arrow.")
                row(.tuck, title: "Tuck a window", symbol: "arrow.up",
                    detail: app.accessibilityTrusted
                        ? "Click another app's window so it's in front, then open Tuck and press Tuck on the left. No other window open? Click Finder in the Dock."
                        : "Tuck needs \(AX.paneName) for this. Press Allow Tuck in the open fold to turn it on.")
                row(.bringBack, title: "Bring it back", symbol: "macwindow",
                    detail: "Click the window's tile in the fold. It goes back where it was.")
                row(.drop, title: "Drop something", symbol: "tray.and.arrow.down",
                    detail: "Drag a file, link or text onto \(place). Files stay where they are; macOS may ask once before Tuck can read a folder.")
            }
            Spacer(minLength: 12)
            Label("With two fingers on a trackpad, swipe down on \(place) to open Tuck, down again to see everything, and up to go back.",
                  systemImage: "hand.draw")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
        }
    }

    private func row(_ move: SetupPractice.Move, title: String, symbol: String, detail: String) -> some View {
        let done = setup.practice.done.contains(move)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(done ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeOut(duration: 0.2), value: done)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : "not yet")
    }
}

/// The finish: where Settings and the tutorial are, and open at login.
struct DoneStep: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "You're set",
                      detail: settings.menuBarIconShown
                        ? "Open Settings from Tuck's menu-bar item. To practise again, choose Open Tutorial… in Settings › General."
                        : "Open Settings with a secondary click along the top of Tuck's open fold. To practise again, choose Open Tutorial… in Settings › General.")
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
}
