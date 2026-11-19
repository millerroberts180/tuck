import AppKit
import SwiftUI
import TuckCore

/// Choose: Tuck's optional behaviours in one line. Pointing at a pad plays what it does; its switch is
/// the real setting, under the same name as in Settings.
struct ChooseStep: View {
    @ObservedObject var settings: SettingsStore
    let model: TuckModel
    @State private var described: SetupChoice?
    @State private var confirmingClipboardOff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "Choose what you want",
                      detail: "Tuck does only what you ask. Point at each one to see what it does, and switch on the ones you want. You can change these later in Settings.")
            HStack(alignment: .top, spacing: 8) {
                ForEach(SetupChoice.allCases) { choice in
                    TryTile(choice: choice, isOn: binding(for: choice)) { described = choice }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let described {
                    Text(described.title).fontWeight(.semibold)
                    Text(described.meaning).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Point at a pad to see it work.").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            .padding(.top, 18)
            .accessibilityElement(children: .combine)
            Text("More in Settings: which displays show Tuck, reversing the mouse wheel, and Rest, an experiment that pauses apps whose windows are all tucked.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .clipboardTurnOffPrompt(isPresented: $confirmingClipboardOff, settings: settings, model: model,
                                onDelete: model.clearClipboard)
    }

    private func binding(for choice: SetupChoice) -> Binding<Bool> {
        switch choice {
        case .dropInvitation: $settings.dropInvitation
        case .menuBar: $settings.menuBarIconShown
        case .shortcuts: $settings.shortcutsEnabled
        case .modifierDrag: $settings.windowDragEnabled
        case .smoothScrolling: $settings.smoothScrollingEnabled
        case .clipboard: ClipboardHistorySwitch.binding(settings: settings, model: model, asking: $confirmingClipboardOff)
        }
    }
}

/// The choices, named as Settings names them. The first two are on by default; the rest are opt-in.
enum SetupChoice: String, CaseIterable, Identifiable {
    case dropInvitation, menuBar, shortcuts, modifierDrag, smoothScrolling, clipboard

    var id: Self { self }

    var title: String {
        switch self {
        case .dropInvitation: "Widen when a drag comes near"
        case .menuBar: "Show in menu bar"
        case .shortcuts: "Use keyboard shortcuts"
        case .modifierDrag: "Modifier-drag"
        case .smoothScrolling: "Smooth scrolling"
        case .clipboard: "Clipboard history"
        }
    }

    /// What it's like, under the title.
    var detail: String {
        switch self {
        case .dropInvitation: "Grows as a drag heads its way"
        case .menuBar: "Tuck's menu, beside the clock"
        case .shortcuts: "⌃⌥⌘T tucks, from any app"
        case .modifierDrag: "Hold ⌃⌥ and drag a window"
        case .smoothScrolling: "A mouse wheel glides"
        case .clipboard: "Find what you copied again later"
        }
    }

    /// What it means, once tried.
    var meaning: String {
        switch self {
        case .dropInvitation:
            "While you drag files, links or text toward the notch, Tuck widens into one target that says what it will hold. Off, you can still drop straight onto the notch."
        case .menuBar:
            "Open Tuck, tuck the window in front, restore the last one, and Settings. Off, open Settings with a secondary click along the top of Tuck's open fold."
        case .shortcuts:
            "⌃⌥⌘T tucks the window in front, ⌃⌥⌘R restores the last one, and ⌃⌥⌘O opens Tuck. Tuck hears only these keys."
        case .modifierDrag:
            "Hold ⌃⌥ and drag anywhere in a window to move it; right-drag to resize. Needs \(AX.paneName), next."
        case .smoothScrolling:
            "Each notch of a mouse wheel becomes a short glide. Trackpads are left alone. Needs \(AX.paneName), next."
        case .clipboard:
            "Text, links, images and files you copy wait under Copied, each shown as what it is, and a search finds them by kind or day. It skips anything marked private, and goes online only to preview a link's page or an address's map."
        }
    }
}

/// One choice: a pad that plays what it does when the pointer moves onto it (or on a click), its name
/// and feel, and the real switch.
private struct TryTile: View {
    let choice: SetupChoice
    @Binding var isOn: Bool
    let onTry: () -> Void
    /// How far the pad's little demo has played, 0 to 1.
    @State private var progress: Double = 1
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 7) {
            pad
            Text(choice.title)
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32, alignment: .top)
            Text(choice.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 26, alignment: .top)
            Toggle(choice.title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
        .frame(width: 116)
    }

    private var pad: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let wash = LinearGradient(colors: [Color.accentColor.opacity(isOn ? 0.26 : 0.09),
                                           Color.accentColor.opacity(isOn ? 0.10 : 0.03)],
                                  startPoint: .top, endPoint: .bottom)
        let edge: Double = lit ? 0.9 : (isOn ? 0.35 : 0.15)
        return shape
            .fill(wash)
            .overlay(shape.strokeBorder(Color.accentColor.opacity(edge), lineWidth: lit ? 2 : 1))
            .overlay(ChoiceArt(choice: choice, progress: progress, highlighted: isOn).padding(8))
            .frame(width: 72, height: 96)
            .scaleEffect(lit && !reduceMotion ? 1.04 : 1)
            .contentShape(shape)
            .onHover { if $0 { play() } }
            .onTapGesture(perform: play)
            .help("Point at it to see what it does")
            .accessibilityElement()
            .accessibilityLabel("Try \(choice.title)")
            .accessibilityHint(choice.meaning)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { play() }
    }

    /// Once per entry: the demo plays from the start, and the pad lights.
    private func play() {
        onTry()
        withAnimation(.easeOut(duration: 0.08)) { lit = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.35)) { lit = false }
        }
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        DispatchQueue.main.async {
            let animation: Animation = choice == .smoothScrolling ? .linear(duration: GlideArt.duration) : .easeInOut(duration: 0.9)
            withAnimation(animation) { progress = 1 }
        }
    }
}

/// A pad's drawing of its choice; `progress` plays it, and at 1 it rests showing the end.
private struct ChoiceArt: View, Animatable {
    let choice: SetupChoice
    var progress: Double
    let highlighted: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var ink: Color { highlighted ? Color.accentColor : Color.secondary }

    var body: some View {
        Group {
            switch choice {
            case .dropInvitation: drop
            case .menuBar: menuBar
            case .shortcuts: shortcuts
            case .modifierDrag: modifierDrag
            case .smoothScrolling: smooth
            case .clipboard: clipboard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    /// A file rising to the notch, which widens to meet it, more as it nears, and takes it in. At rest,
    /// the file waits at the bottom.
    private var drop: some View {
        let rise = min(progress / 0.8, 1)
        let taken = progress >= 0.8 && progress < 0.9
        let back = progress >= 0.9
        let near = back ? rise * rise * max(0, 1 - (progress - 0.9) / 0.1) : rise * rise
        let docOpacity = taken ? max(0, 1 - (progress - 0.8) / 0.06) : (back ? (progress - 0.9) / 0.1 : 1)
        return ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5, style: .continuous)
                .fill(Color.black)
                .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5, style: .continuous)
                    .strokeBorder(ink.opacity(0.3 + 0.7 * near), lineWidth: 1))
                .frame(width: 30 + 14 * near, height: 9 + 8 * near)
            Image(systemName: "doc.fill")
                .font(.system(size: 14))
                .foregroundStyle(ink)
                .offset(y: back ? 62 : 62 - 46 * rise)
                .opacity(docOpacity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The menu bar with Tuck's mark, and its menu dropping open.
    private var menuBar: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<2, id: \.self) { _ in Capsule().fill(Color.primary.opacity(0.18)).frame(width: 6, height: 3) }
                Spacer(minLength: 0)
                Image(nsImage: TuckLogo.menuBarImage())
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 11, height: 11)
                    .foregroundStyle(ink)
            }
            .padding(.horizontal, 5)
            .frame(height: 15)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            VStack(alignment: .leading, spacing: 4) {
                ForEach([0.9, 0.7, 0.8], id: \.self) { width in
                    Capsule().fill(Color.primary.opacity(0.22)).frame(width: 30 * width, height: 3)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(ink.opacity(0.4)))
            .scaleEffect(0.85 + 0.15 * progress, anchor: .topTrailing)
            .opacity(progress)
            Spacer(minLength: 0)
        }
    }

    /// ⌃ ⌥ ⌘ T, lighting one after another.
    private var shortcuts: some View {
        let keys: [(symbol: String?, text: String?)] = [("control", nil), ("option", nil), ("command", nil), (nil, "T")]
        return LazyVGrid(columns: [GridItem(.fixed(24), spacing: 4), GridItem(.fixed(24), spacing: 4)], spacing: 4) {
            ForEach(keys.indices, id: \.self) { index in
                let down = progress >= Double(index + 1) * 0.2
                let cap = RoundedRectangle(cornerRadius: 5, style: .continuous)
                Group {
                    if let symbol = keys[index].symbol {
                        Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                    } else if let text = keys[index].text {
                        Text(text).font(.system(size: 11, weight: .semibold))
                    }
                }
                .foregroundStyle(down ? ink : Color.secondary)
                .frame(width: 24, height: 22)
                .background(cap.fill(down ? ink.opacity(0.2) : Color.primary.opacity(0.06)))
                .overlay(cap.strokeBorder(down ? ink : Color.primary.opacity(0.12)))
                .offset(y: down && progress < 1 ? 1 : 0)
            }
        }
    }

    /// A window moving with the pointer while ⌃⌥ are held.
    private var modifierDrag: some View {
        let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
        let holding = progress > 0 && progress < 1
        return VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 5) }
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ink.opacity(0.6)))
                    .frame(width: 34, height: 26)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary)
                    .offset(x: -6, y: -3)
            }
            .offset(x: -9 + 18 * eased, y: 4 - 8 * eased)
            KeycapsArt(symbols: ["control", "option"], highlighted: holding || highlighted)
        }
    }

    /// The glide a wheel notch becomes, as Settings draws it.
    private var smooth: some View {
        VStack(spacing: 6) {
            GlideArt(timeConstant: ScrollSmoothness.balanced.timeConstant, highlighted: highlighted, progress: progress)
                .frame(height: 44)
            Image(systemName: "computermouse")
                .font(.system(size: 13))
                .foregroundStyle(ink)
        }
    }

    /// A copy arriving as the first of the tiles, two to a row.
    private var clipboard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(ink.opacity(0.75))
                    .frame(width: 21, height: 13)
                    .offset(y: -10 * (1 - progress))
                    .opacity(progress)
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.primary.opacity(0.18))
                    .frame(width: 21, height: 13)
            }
            HStack(spacing: 4) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.primary.opacity(0.18))
                        .frame(width: 21, height: 13)
                }
            }
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13))
                .foregroundStyle(ink)
                .padding(.top, 6)
        }
    }
}
