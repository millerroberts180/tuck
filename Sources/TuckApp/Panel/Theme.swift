import SwiftUI
import TuckCore

/// A colour for light and dark, each with a stronger variant for Increase Contrast.
private func tone(light: UInt32, dark: UInt32, lightContrast: UInt32? = nil, darkContrast: UInt32? = nil) -> NSColor {
    NSColor(name: nil) { appearance in
        switch variant(of: appearance) {
        case .darkAqua: return srgb(dark)
        case .accessibilityHighContrastDarkAqua: return srgb(darkContrast ?? dark)
        case .accessibilityHighContrastAqua: return srgb(lightContrast ?? light)
        default: return srgb(light)
        }
    }
}

private func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Which of the four appearances a colour is being drawn in.
private func variant(of appearance: NSAppearance) -> NSAppearance.Name? {
    let match = appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                            .accessibilityHighContrastDarkAqua])
    #if DEBUG
    if snapshotsIncreaseContrast {
        return match == .darkAqua ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua
    }
    #endif
    return match
}

#if DEBUG
/// Set while the snapshots draw their Increase Contrast shots: AppKit hands back the plain appearance
/// for `NSAppearance(named: .accessibilityHighContrastDarkAqua)`, and takes Increase Contrast only from
/// the system's setting, so without this those shots would show the ordinary colours.
nonisolated(unsafe) var snapshotsIncreaseContrast = false
#endif

/// One colour seen through at a different strength in each appearance.
private func wash(_ color: NSColor, light: CGFloat, dark: CGFloat, lightContrast: CGFloat, darkContrast: CGFloat) -> NSColor {
    NSColor(name: nil) { appearance in
        let alpha: CGFloat = switch variant(of: appearance) {
        case .darkAqua: dark
        case .accessibilityHighContrastDarkAqua: darkContrast
        case .accessibilityHighContrastAqua: lightContrast
        default: light
        }
        var resolved = color
        appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) ?? color }
        return resolved.withAlphaComponent(alpha)
    }
}

/// `hex` moved `amount` of the way to `target`, channel by channel.
private func mixed(_ hex: UInt32, _ target: UInt32, _ amount: Double) -> UInt32 {
    [16, 8, 0].reduce(0) { result, shift in
        let from = Double((hex >> UInt32(shift)) & 0xff), to = Double((target >> UInt32(shift)) & 0xff)
        return result | UInt32((from + (to - from) * amount).rounded()) << UInt32(shift)
    }
}

/// What a tile holds, told by one small mark at the start of its line of details rather than by its
/// ground: every card is the same light grey, so the stream reads calmly and its pictures keep the only
/// full colour. The twelve hues stay 30° apart round Tuck Blue's own (252° in OKLCH), a wheel that also
/// lands within 3° of Pulse's indigo (279°), Hum's crimson (14°) and Glow's peach (41°), one by kind
/// (code, links, people, numbers, music, dates, emoji, files, pictures, places, keys and windows); text
/// and colours take a plain grey mark. All are deep, at one lightness so no kind shouts over another:
/// OKLCH 0.53 at chroma 0.13, or less where a hue would leave sRGB (0.09 for teal), and 0.43 with
/// Increase Contrast.
///
/// The card is light in both appearances (0.93 on paper, 0.89 on black, chroma 0.005 or less), so what
/// is drawn on it takes the card's inks (`OnCard`): ink and a warm dark grey for text, a deep Tuck Blue
/// for the ring and the capsule. On the card and its hover, in all four appearances, primary text is at
/// 12.4:1 or better, secondary text at 4.60:1, code's keywords and strings at 4.60:1, a kind's mark at
/// 3.31:1 (5.17:1 with Increase Contrast), and the ring and the capsule stand at 3.31:1 off the ground.
private enum TileTint: CaseIterable {
    case grey, blue, violet, orchid, rose, red, orange, gold, olive, leaf, green, teal, sky

    init(_ category: ContentCategory) {
        switch category {
        case .text, .richText, .color: self = .grey
        case .link: self = .blue
        case .code: self = .violet
        // Music takes the hue of Hum, Line's music app, and keys the orchid it leaves.
        case .music, .audio: self = .red
        case .email, .contact: self = .rose
        case .secret: self = .orchid
        case .date: self = .orange
        case .emoji: self = .gold
        case .image, .screenshot, .video: self = .olive
        case .address: self = .leaf
        case .file, .folder, .path, .stack: self = .green
        case .phone: self = .teal
        case .window: self = .sky
        }
    }

    /// The mark's ink, then with Increase Contrast; from 252° round the wheel. The card is light in both
    /// appearances, so each is the same on paper and on black.
    var inks: [UInt32] {
        switch self {
        case .grey: [0x6C6C6C, 0x505050]
        case .blue: [0x296EB4, 0x015093]
        case .violet: [0x6160B4, 0x474294]
        case .orchid: [0x8553A1, 0x673682]
        case .rose: [0x9D4981, 0x7D2C63]
        case .red: [0xA94657, 0x88283C]
        case .orange: [0xA84D27, 0x863002]
        case .gold: [0x935F05, 0x6E4600]
        case .olive: [0x796D03, 0x5A5100]
        case .leaf: [0x4E7B1E, 0x365C02]
        case .green: [0x018057, 0x015F3F]
        case .teal: [0x057C79, 0x065C5A]
        case .sky: [0x007894, 0x04596E]
        }
    }

    var mark: NSColor {
        let inks = inks
        return tone(light: inks[0], dark: inks[0], lightContrast: inks[1], darkContrast: inks[1])
    }

    /// The card: light, dark, then each with Increase Contrast.
    static let card: [UInt32] = [0xE6E8EA, 0xD9DBDD, 0xDCDEE1, 0xDFE1E4]
    static let fill = Color(nsColor: tone(light: card[0], dark: card[1], lightContrast: card[2], darkContrast: card[3]))
    /// Under the pointer: a step darker on paper and a step lighter on black, so the card's ink only
    /// gains on black, and on paper secondary text still reads at 4.5:1.
    static let hover = Color(nsColor: tone(light: mixed(card[0], 0x000000, 0.03), dark: mixed(card[1], 0xFFFFFF, 0.08),
                                           lightContrast: mixed(card[2], 0x000000, 0.05),
                                           darkContrast: mixed(card[3], 0xFFFFFF, 0.1)))
    static let marks = Dictionary(uniqueKeysWithValues: allCases.map { ($0, Color(nsColor: $0.mark)) })
}

/// A colour that is `card` on a tile's card and `base` everywhere else. The fold is black but its cards
/// are light, so the fold's own text tokens turn to ink on them, and a face drawn with
/// `Theme.primaryText` reads wherever it is put. `TileChrome` marks the card (`isOnTileCard`); its
/// ground, a `TileTint`, takes no part.
private struct OnCard: ShapeStyle, Hashable {
    let base: Color
    let card: Color

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        (environment.isOnTileCard ? card : base).resolve(in: environment)
    }
}

private func onCard(_ base: NSColor, card: NSColor) -> Color {
    Color(OnCard(base: Color(nsColor: base), card: Color(nsColor: card)))
}

private struct OnTileCardKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Inside a tile's card, where text and marks take the card's inks (see `OnCard`).
    var isOnTileCard: Bool {
        get { self[OnTileCardKey.self] }
        set { self[OnTileCardKey.self] = newValue }
    }
}

/// Tuck's colours: warm paper and stone in light, black in dark (the notch's own black, so the fold
/// reads as the notch opening), ink for text and one accent, Tuck Blue. Tiles are one light grey card in
/// both appearances that carries ink, and each kind marks itself with a small symbol in one of twelve
/// deep hues (`TileTint`). Apps and clipboard formats have no colour of their own.
enum Theme {
    /// The open fold: warm paper in light, black in dark.
    static let paperNSColor = tone(light: 0xF8F6F1, dark: 0x000000, lightContrast: 0xFFFFFF, darkContrast: 0x000000)
    static var paper: Color { Color(nsColor: paperNSColor) }
    /// A field raised off the paper: the search field, and the card a window becomes as it is tucked.
    static let raisedNSColor = tone(light: 0xFFFEFB, dark: 0x1C1F24, lightContrast: 0xFFFFFF, darkContrast: 0x23272D)
    static var raised: Color { Color(nsColor: raisedNSColor) }
    /// Quiet fills: a hovered row, a resting button, a lens. Cool in dark.
    static let stone = Color(nsColor: tone(light: 0xEFEBE4, dark: 0x2A2E35, lightContrast: 0xE2DDD4,
                                           darkContrast: 0x3A3F47))
    /// Rules and edges; on a card, ink seen through.
    static let hairlineNSColor = tone(light: 0xDED9D0, dark: 0x30343B, lightContrast: 0x8F8A80, darkContrast: 0x7A7F88)
    static let hairline = onCard(hairlineNSColor, card: wash(srgb(0x111316), light: 0.12, dark: 0.16, lightContrast: 0.45,
                                                             darkContrast: 0.5))
    /// Text in three tones. On a card, ink and two warm dark greys, a step darker than paper's so they
    /// read on its colour.
    static let primaryText = onCard(tone(light: 0x111316, dark: 0xF2F1EE, lightContrast: 0x000000, darkContrast: 0xFFFFFF),
                                    card: tone(light: 0x111316, dark: 0x111316, lightContrast: 0x000000, darkContrast: 0x000000))
    static let secondaryText = onCard(tone(light: 0x676862, dark: 0xA4A49E, lightContrast: 0x3F403B, darkContrast: 0xD0D0CA),
                                      card: tone(light: 0x60615B, dark: 0x454540, lightContrast: 0x3D3D38, darkContrast: 0x2E2E29))
    static let faint = onCard(tone(light: 0x989891, dark: 0x75756F, lightContrast: 0x5E5E58, darkContrast: 0xA8A8A2),
                              card: tone(light: 0x7E7E78, dark: 0x60615B, lightContrast: 0x595954, darkContrast: 0x4B4B46))
    static var tertiaryText: Color { faint }

    /// Tuck Blue, the logo's #7299C5, in dark; deepened to #4570A2 on paper so it reads as text there
    /// (4.7:1), and stronger again with Increase Contrast. It marks the Tuck mark and dot, keyboard focus,
    /// the active drop target, a selected or expanded control and the deposit and restore cue, and
    /// nothing else. On a card, which is light on black too, it is the deeper blue in both: #325C8D on
    /// black, which stands 3.31:1 off the ground where the logo's blue would stand as little as 1.4:1.
    static let accentNSColor = tone(light: 0x4570A2, dark: 0x7299C5, lightContrast: 0x2C5687, darkContrast: 0x9CBEE3)
    static let accent = onCard(accentNSColor, card: tone(light: 0x4570A2, dark: 0x325C8D, lightContrast: 0x2C5687,
                                                         darkContrast: 0x224C7B))
    /// The blue seen through, for the active drop target and a selection only: a tenth on paper, a fifth
    /// on black, where a tenth would not show.
    static let accentTint = Color(nsColor: wash(accentNSColor, light: 0.1, dark: 0.2, lightContrast: 0.16, darkContrast: 0.3))
    /// Text and symbols on a filled blue: white on the deep blue of paper and of a card, ink on the
    /// lighter blue of dark, where white would read at only 3:1.
    static let onAccent = onCard(tone(light: 0xFFFFFF, dark: 0x1D2430, lightContrast: 0xFFFFFF, darkContrast: 0x1D2430),
                                 card: srgb(0xFFFFFF))
    /// Keywords in code, which is only drawn on its card: the blue, deep enough to read on the card.
    static let codeKeyword = Color(nsColor: tone(light: 0x396394, dark: 0x1D4876, lightContrast: 0x133E6C,
                                                 darkContrast: 0x03305D))
    /// Strings and numbers in code: a deep amber, so code reads as code without a palette per language.
    static let codeString = Color(nsColor: tone(light: 0x895519, dark: 0x683C00, lightContrast: 0x5C3400,
                                                darkContrast: 0x482800))
    static var rowHover: Color { stone }
    static var rowActive: Color { accentTint }
    static var chip: Color { stone }

    /// A tile's ground, the same card whatever it holds, and under the pointer; see `TileTint`.
    static var tileFill: Color { TileTint.fill }
    static var tileHover: Color { TileTint.hover }
    /// The small mark of what a tile holds, its kind's symbol, in that kind's deep hue.
    static func kindMark(for category: ContentCategory) -> Color { TileTint.marks[TileTint(category)] ?? secondaryText }
    /// A small surface set on a tile, a badge, a calendar page or a placeholder: near white on paper, and
    /// white about half seen through on black, so it reads as a label laid on the card.
    static let tileInset = Color(nsColor: wash(.white, light: 0.85, dark: 0.45, lightContrast: 1, darkContrast: 0.6))
    /// A tile's edge, drawn only with Increase Contrast, where the tile must stand off the paper by more
    /// than its fill.
    static let tileEdge = Color(nsColor: wash(hairlineNSColor, light: 0, dark: 0, lightContrast: 1, darkContrast: 1))

    /// The fold's corners, and a control's.
    static let foldRadius: CGFloat = 20
    static let controlRadius: CGFloat = 10

    /// How a prompt or an opened list appears: sliding in from its edge, or with Reduce Motion a fade.
    static func reveal(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: edge))
    }

    static let panelSpace = "tuckPanel"

    /// Reduce Motion (System Settings → Accessibility → Display): the fold changes depth with a fade,
    /// springs settle without overshoot, and drops don't fly.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Hover and focus.
    static let quick = Animation.easeOut(duration: 0.16)
    /// A control pressed in and let go: fast, so it confirms the click without delaying it.
    static let press = Animation.easeOut(duration: 0.12)
    /// A state change inside the fold: a row opening, a prompt arriving.
    static var settle: Animation { reduceMotion ? quick : .easeOut(duration: 0.24) }
    /// The fold deepening or folding back, or a lens narrowing the stream.
    static var fold: Animation { reduceMotion ? quick : .easeOut(duration: 0.26) }
    /// Something arriving in the stream or leaving it: a soft spring that barely passes its rest.
    static var deposit: Animation { reduceMotion ? quick : .spring(response: 0.48, dampingFraction: 0.86) }

    static func symbol(for kind: HeldItemKind) -> String {
        switch kind {
        case .file: return "doc"
        case .link: return "link"
        case .music: return "music.note"
        case .text: return "text.alignleft"
        case .stack: return "square.stack.3d.up"
        }
    }

    static func symbol(for placement: Placement) -> String {
        switch placement {
        case .original: return "macwindow"
        case .leftHalf, .leftThird, .leftTwoThirds: return "rectangle.lefthalf.filled"
        case .rightHalf, .rightThird, .rightTwoThirds: return "rectangle.righthalf.filled"
        case .fullScreen: return "rectangle.fill"
        case .centerThird, .center: return "rectangle.center.inset.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .nextDisplay: return "rectangle.on.rectangle"
        }
    }

    /// How VoiceOver says a time: "5 minutes ago" rather than "5m".
    static func spokenRelative(_ date: Date) -> String {
        if Date.now.timeIntervalSince(date) < 60 { return "just now" }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .wide))
    }

    /// The closed notch is always black, so what is drawn on it resolves in the dark appearance whatever
    /// the person's Light or Dark setting.
    static let notchAppearance = NSAppearance(named: .darkAqua)!
}

/// The panel's type scale, built on the system text styles so the font's own optical sizes and tracking
/// apply. Rows are compact: a 13 pt title over a 12 pt secondary line. Nothing is smaller than 12 pt
/// but the 11 pt badges and code's line numbers on tiles.
/// Counts and times use tabular digits so they line up down a list.
extension Font {
    /// Row titles, prompt titles.
    static let panelTitle = Font.system(.body).weight(.medium)
    /// Window titles inside an app, a search as it is typed.
    static let panelBody = Font.system(.body)
    /// The metadata line under a title, explanations, the status line.
    static let panelSubtitle = Font.system(.callout)
    /// Counts and times on their own.
    static let panelMeta = Font.system(.callout).monospacedDigit()
    /// Button and lens labels.
    static let panelControl = Font.system(.callout).weight(.medium)
    /// Large prompt buttons and the quiet line's title.
    static let panelHeadline = Font.system(.body).weight(.semibold)
    /// Placement names and small tags.
    static let panelCaption = Font.system(.callout).weight(.medium)
    /// Copied code, a line to a row.
    static let panelCode = Font.system(.callout, design: .monospaced)
    /// The line numbers down code's gutter, a step under the code, as small as a tile's line of details.
    static let panelCodeGutter = Font.system(.subheadline, design: .monospaced)
    /// Copied words on a text card and while they are edited, in the rounded face: softer than the panel's
    /// own labels, which stay in the plain one.
    static let panelWords = Font.system(.body, design: .rounded)
}

/// Shared row treatment: nothing at rest, a stone highlight under the pointer, and the blue tint while
/// pressed or while the row is opened out (an app's windows, a window's placements).
struct RowChrome: ViewModifier {
    var isHovering: Bool
    var isActive: Bool = false
    var isPressed: Bool = false

    /// The highlight's corners, and how far a row's content sits in from its sides; a tucked window's
    /// card lands on the row's icon and opens out to this shape.
    static let cornerRadius: CGFloat = 10
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(isActive || isPressed ? Theme.rowActive : (isHovering ? Theme.rowHover : .clear))
            )
            .contentShape(Rectangle())
    }
}

/// A whole row that restores, opens or toggles on a click, with the row's own hover and pressed states.
struct RowButtonStyle: ButtonStyle {
    var isHovering: Bool
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(RowChrome(isHovering: isHovering, isActive: isActive, isPressed: configuration.isPressed))
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// Tuck's buttons: a rounded rectangle on stone that darkens on hover, presses in, and dims when
/// disabled. One prominent button at most per prompt, filled blue; destructive choices are plain, their
/// label saying what they do. Regular buttons are 24 pt tall; large ones, for a prompt's choices, are
/// 30 pt and share the width between them.
struct PanelButtonStyle: ButtonStyle {
    /// A quiet button (the fold's toolbar) has no ground until the pointer is on it, and quieter ink.
    enum Role { case normal, prominent, destructive, quiet }
    enum Size { case regular, large }
    var role: Role = .normal
    /// A button whose chooser is open stays lit.
    var isSelected = false
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        PanelButton(configuration: configuration, role: role, isSelected: isSelected, size: size)
    }

    private struct PanelButton: View {
        let configuration: Configuration
        let role: Role
        let isSelected: Bool
        let size: Size
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(size == .large ? .panelHeadline : .panelControl)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, size == .large ? 14 : 9)
                .frame(maxWidth: size == .large ? .infinity : nil, minHeight: size == .large ? 30 : 24)
                .background(RoundedRectangle(cornerRadius: Theme.controlRadius - 2, style: .continuous).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius - 2, style: .continuous))
                .scaleEffect(configuration.isPressed && !Theme.reduceMotion ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { isHovering = $0 && isEnabled }
                .animation(Theme.press, value: configuration.isPressed)
                .animation(Theme.quick, value: isHovering)
        }

        private var foreground: Color {
            switch role {
            case .prominent: return Theme.onAccent
            case .destructive, .normal: return isSelected ? Theme.accent : Theme.primaryText
            case .quiet: return isSelected ? Theme.accent : (isHovering ? Theme.primaryText : Theme.secondaryText)
            }
        }

        private var fill: Color {
            if role == .prominent {
                return Theme.accent.opacity(configuration.isPressed ? 0.82 : (isHovering ? 0.92 : 1))
            }
            if isSelected { return Theme.accentTint }
            if role == .quiet { return configuration.isPressed ? Theme.primaryText.opacity(0.1) : (isHovering ? Theme.stone : .clear) }
            return configuration.isPressed || isHovering ? Theme.primaryText.opacity(0.1) : Theme.stone
        }
    }
}

/// A symbol-only button with a 24 pt target: search, fold, close. Every use names itself for VoiceOver
/// and shows a tooltip.
struct PanelIconButtonStyle: ButtonStyle {
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        PanelIconButton(configuration: configuration, isSelected: isSelected)
    }

    private struct PanelIconButton: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: Theme.controlRadius - 2, style: .continuous)
                    .fill(isSelected ? Theme.accentTint
                          : (configuration.isPressed || isHovering ? Theme.stone : .clear)))
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .animation(Theme.press, value: configuration.isPressed)
                .animation(Theme.quick, value: isHovering)
        }
    }
}

/// Presses its own drawing in slightly (a lens, a placement tile), so a click is felt before anything
/// else changes. Reduce Motion keeps it still.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Theme.reduceMotion ? scale : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// What a click just did, a symbol and a word in a small blue capsule over the tile's corner, so the
/// tile's face never moves to make room for it. It comes and goes with `Theme.quick`.
struct FeedbackBadge: View {
    let feedback: TuckModel.RowFeedback

    var body: some View {
        Label(feedback.message, systemImage: feedback.symbol)
            .font(.panelCaption)
            .foregroundStyle(Theme.onAccent)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Theme.accent, in: Capsule())
            .transition(Theme.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
    }
}

struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The stream's content height, so the fold can size itself to what it holds.
struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PickerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ListFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Where a tucked window's card lands in the open fold: the row or tile that holds the window, and the
/// icon in it that the card's dot sits on before it opens out to the whole frame.
struct WindowLanding: Equatable {
    var frame: CGRect
    var icon: CGRect

    /// A row's icon sits at its leading edge, centred down it.
    static func row(_ frame: CGRect) -> WindowLanding {
        let side = StreamIcon.size
        return WindowLanding(frame: frame, icon: CGRect(x: frame.minX + RowChrome.horizontalPadding,
                                                         y: frame.midY - side / 2, width: side, height: side))
    }

    /// A tile's icon sits at its top leading corner, inside the tile's padding.
    static func tile(_ frame: CGRect) -> WindowLanding {
        let side = Theme.tileLead
        return WindowLanding(frame: frame, icon: CGRect(x: frame.minX + Theme.tilePadding, y: frame.minY + Theme.tilePadding,
                                                         width: side, height: side))
    }
}

/// Where each parked window's row or tile is in the stream. A window inside a closed app row or tile
/// has its frame; an open app's own window rows come after it and take their windows over.
struct WindowRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: WindowLanding] = [:]
    static func reduce(value: inout [UUID: WindowLanding], nextValue: () -> [UUID: WindowLanding]) {
        value.merge(nextValue()) { $1 }
    }
}
