import SwiftUI

// Building blocks shared by the Settings panes. They follow the system's grouped-form look and add only
// what a plain control can't say: what a choice does, and what an action is for.

/// A grouped-form footer that reads as a note: left-aligned, caption, secondary.
struct FooterNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Something that is always true and can't be switched, shown so people know: a quiet symbol and line.
struct AlwaysLabel: View {
    let text: String
    let symbol: String
    init(_ text: String, systemImage: String) {
        self.text = text
        self.symbol = systemImage
    }

    var body: some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            // One width for every symbol, so the lines start together.
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
        }
    }
}

/// A titled row holding a row of choice tiles.
struct ChoiceRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            content
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The Accessibility permission: allowed, or a way to allow it. The system is asked only when a feature
/// needs it, never from here.
struct AccessibilityRow: View {
    let trusted: Bool
    let detail: String

    var body: some View {
        LabeledContent {
            if trusted {
                Label {
                    Text("Allowed").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } else {
                Button(action: AX.openAccessibilitySettings) {
                    ActionLabel(title: "Open Settings…", symbol: "lock.open")
                }
                .buttonStyle(ActionButtonStyle())
            }
        } label: {
            Text(AX.paneName)
            Text(detail)
        }
    }
}

// MARK: - Choice tiles

/// A row of illustrated tiles for choosing one of a few ordered settings, in place of a segmented
/// control. Each tile draws what its choice does and the chosen one glows. `onPick` runs after a
/// choice, to demonstrate it.
struct VisualChoice<Value: Hashable, Art: View>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value
    var onPick: (Value) -> Void = { _ in }
    /// The tile's drawing for a value; the Bool is whether it's chosen.
    @ViewBuilder let art: (Value, Bool) -> Art

    var body: some View {
        // Disabled tiles dim with the rest of the form; plain buttons already fade their labels.
        HStack(spacing: 8) {
            ForEach(options) { option in
                tile(option)
            }
        }
    }

    private func tile(_ option: Option) -> some View {
        let selected = option.value == selection
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            selection = option.value
            onPick(option.value)
        } label: {
            VStack(spacing: 6) {
                art(option.value, selected)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(shape.fill(Color.primary.opacity(selected ? 0.10 : 0.05)))
                    .overlay(shape.strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.10),
                                                lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? Color.accentColor.opacity(0.45) : .clear, radius: 5)
                Text(option.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The modifier keys a choice needs, drawn as keycaps around their symbols.
struct KeycapsArt: View {
    let symbols: [String]
    let highlighted: Bool

    var body: some View {
        let ink = highlighted ? Color.accentColor : Color.secondary
        let cap = RoundedRectangle(cornerRadius: 5, style: .continuous)
        HStack(spacing: 4) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 22, height: 20)
                    .background(cap.fill(Color.primary.opacity(0.06)))
                    .overlay(cap.strokeBorder(ink.opacity(0.6)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The displays a choice covers, as their symbols.
struct DisplaysArt: View {
    let symbols: [String]
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
            }
        }
        .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
        .accessibilityHidden(true)
    }
}

/// The top of a screen without a notch: its menu bar, with Tuck as a bubble in the middle of it, its mark
/// alone in the middle as the real one shows it, or as a drawn notch hanging from the edge, bare as an
/// empty notch is.
struct NotchStyleArt: View {
    let drawsNotch: Bool
    let highlighted: Bool

    var body: some View {
        let ink = highlighted ? Color.accentColor : Color.secondary
        let item = Color.primary.opacity(0.18)
        ZStack(alignment: .top) {
            // The menu bar, with menu titles on the left and status items on the right.
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(item).frame(width: 7, height: 3) }
                Spacer()
                ForEach(0..<2, id: \.self) { _ in Capsule().fill(item).frame(width: 4, height: 3) }
            }
            .padding(.horizontal, 10)
            .frame(height: 11)
            .background(Color.primary.opacity(0.07))
            if drawsNotch {
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5, style: .continuous)
                    .fill(ink)
                    .frame(width: 34, height: 13)
            } else {
                // The mark is cut out of the bubble, so it reads in either appearance, selected or not.
                Capsule()
                    .fill(ink)
                    .mask {
                        Capsule()
                            .overlay {
                                LogoLine()
                                    .stroke(style: StrokeStyle(lineWidth: TuckLogo.lineWidth(side: 7), lineCap: .round,
                                                               lineJoin: .round))
                                    .frame(width: 7, height: 7)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                    .frame(width: 30, height: 9)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Tuck's logo on its app-icon tile: the line (`TuckLogo`) in white on Tuck Blue, sized and lifted as the
/// app icon places it.
struct TuckMark: View {
    let size: CGFloat

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
        tile.fill(Color(nsColor: TuckLogo.blue))
            .overlay(Image(nsImage: TuckLogo.markImage(side: size * 0.77, color: .white)).offset(y: -size * 0.013))
            .frame(width: size, height: size)
            .overlay(tile.strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

/// How a smoothed wheel scroll settles: distance against time, an exponential ease with the choice's
/// time constant. A dot rides the curve; `progress` (0...1 of the drawn time) moves it, so animating it
/// linearly over `duration` plays the glide at its real speed.
struct GlideArt: View {
    /// The drawn stretch of time, long enough for the slowest choice to settle.
    static let duration: TimeInterval = 0.55

    let timeConstant: TimeInterval
    let highlighted: Bool
    var progress: Double = 1

    var body: some View {
        let ink = highlighted ? Color.accentColor : Color.secondary.opacity(0.75)
        ZStack {
            GlideCurve(timeConstant: timeConstant)
                .stroke(ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            GlideDot(timeConstant: timeConstant, progress: progress)
                .fill(ink)
        }
        .accessibilityHidden(true)
    }

    fileprivate static func point(at progress: Double, timeConstant: TimeInterval, in rect: CGRect) -> CGPoint {
        let area = rect.insetBy(dx: 14, dy: 9)
        let covered = 1 - exp(-progress * duration / timeConstant)
        return CGPoint(x: area.minX + area.width * progress, y: area.maxY - area.height * covered)
    }
}

private struct GlideCurve: Shape {
    let timeConstant: TimeInterval

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 0...40 {
            let point = GlideArt.point(at: Double(step) / 40, timeConstant: timeConstant, in: rect)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

private struct GlideDot: Shape {
    let timeConstant: TimeInterval
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let point = GlideArt.point(at: progress, timeConstant: timeConstant, in: rect)
        return Path(ellipseIn: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
    }
}

/// How far back clipboard history reaches from now (the right end). `reach` is nil for no limit,
/// drawn as a bar that fades out to the left.
struct RetentionArt: View {
    let reach: Double?
    let highlighted: Bool

    var body: some View {
        let ink = highlighted ? Color.accentColor : Color.secondary.opacity(0.75)
        GeometryReader { proxy in
            let track = proxy.size.width - 28
            ZStack(alignment: .trailing) {
                Capsule().fill(Color.primary.opacity(0.08))
                    .frame(width: track, height: 6)
                if let reach {
                    Capsule().fill(ink)
                        .frame(width: max(8, track * reach), height: 6)
                } else {
                    Capsule().fill(LinearGradient(colors: [ink.opacity(0), ink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: track, height: 6)
                }
                Circle().fill(ink)
                    .frame(width: 10, height: 10)
                    .offset(x: 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Action buttons

/// Settings' action buttons in the same family as the choice tiles: a soft tile with an accent symbol
/// that lights on hover and glows while pressed.
struct ActionButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, compact: compact)
    }

    // Not named `Button`: it would shadow SwiftUI's inside this style.
    private struct StyledButton: View {
        let configuration: Configuration
        let compact: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed
            let shape = RoundedRectangle(cornerRadius: compact ? 7 : 9, style: .continuous)
            configuration.label
                .font(.system(size: compact ? 11 : 12, weight: .medium))
                .padding(.horizontal, compact ? 9 : 12)
                .padding(.vertical, compact ? 4 : 6)
                .background(shape.fill(pressed ? Color.accentColor.opacity(0.20) : Color.primary.opacity(hovering ? 0.10 : 0.06)))
                .overlay(shape.strokeBorder(pressed ? Color.accentColor
                                                    : (hovering ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.12)),
                                            lineWidth: pressed ? 1.5 : 1))
                .shadow(color: pressed ? Color.accentColor.opacity(0.45) : .clear, radius: 5)
                .scaleEffect(pressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.12), value: pressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .contentShape(Rectangle())
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

/// An action button's label: an accent-coloured symbol, then the title.
struct ActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title).foregroundStyle(.primary)
        }
    }
}
