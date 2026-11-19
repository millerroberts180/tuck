import AppKit
import SwiftUI
import TuckCore
import UniformTypeIdentifiers

/// The tour: Tuck's loop on a pretend screen. Open the notch, tuck the window, hold the file, and bring
/// them back. The haptics choice sits above it, where a drop can be felt.
struct TourStep: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var settings: SettingsStore

    init(setup: SetupModel) {
        self.setup = setup
        settings = setup.settings
    }

    static let chips: [ExperiencedChips.Item] = [
        .init(id: TourDesk.Move.open.rawValue, title: "Open the notch", symbol: "cursorarrow.click"),
        .init(id: TourDesk.Move.tuck.rawValue, title: "Tuck a window", symbol: "arrow.up.to.line"),
        .init(id: TourDesk.Move.hold.rawValue, title: "Hold a file", symbol: "tray.and.arrow.down"),
        .init(id: TourDesk.Move.bringBack.rawValue, title: "Bring it back", symbol: "arrow.uturn.backward")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "How Tuck works", detail: instruction)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haptic feedback").font(.system(size: 13, weight: .medium))
                    Text("A light tap on Force Touch trackpads as a drag reaches Tuck and as something lands in it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.bottom, 12)
            PretendScreen(setup: setup, marksSwipeArea: false,
                          dropInvitation: settings.dropInvitation, haptic: setup.app.performHaptic)
            ExperiencedChips(items: Self.chips, done: Set(setup.desk.done.map(\.rawValue)), latest: meaning,
                             placeholder: "Each step is ticked off as you do it, on this pretend screen only.")
                .padding(.top, 12)
        }
    }

    /// What to do next, in one or two sentences.
    private var instruction: String {
        let desk = setup.desk
        switch desk.next {
        case .open?:
            return "This is a pretend screen. Click the notch at the top to open Tuck, or swipe down on it with two fingers."
        case .tuck?:
            guard desk.isOpen else { return "Open the notch, then press Tuck, left of the notch, to put the Notes window away." }
            return desk.isFull ? "Fold back with the chevron at the top right, then press Tuck to put the Notes window away."
                               : "Press Tuck, left of the notch, to put the Notes window away."
        case .hold?:
            return settings.dropInvitation
                ? "Now drag the PDF up to the notch, and let go when it says “\(DropKind.file.label)”."
                : "Now drag the PDF onto the notch, and let go."
        case .bringBack?:
            return bringBackInstruction(desk)
        case nil:
            return "That's Tuck: put things in the notch while you do something else, and take them back when you need them."
        }
    }

    private func bringBackInstruction(_ desk: TourDesk) -> String {
        if desk.isWindowTucked {
            guard desk.isOpen else { return "Open the notch, then click Notes to bring the window back." }
            if let lens = desk.lens, lens != .windows {
                return "Click \(lens.title) again to show everything, then click Notes to bring the window back."
            }
            return "Click Notes in Tuck to bring the window back."
        }
        guard desk.isOpen else { return "Open the notch, then drag the PDF out into the Notes window." }
        if let lens = desk.lens, lens != .files {
            return "Click \(lens.title) again to show everything, then drag the PDF into the Notes window."
        }
        return "Drag Itinerary.pdf from Tuck into the Notes window."
    }

    private var meaning: String? {
        switch setup.desk.latest {
        case .open?: "Open: the fold drops from the notch, with what Tuck holds, newest first, and Tuck for the window in front."
        case .tuck?: "Tuck: the window rises into Tuck instead of going to the Dock, and waits at the top of the list."
        case .hold?: "Hold: the PDF waits in Tuck. Tuck keeps a reference, so the file itself stays where it is."
        case .bringBack?: "Bring back: a window returns exactly where it was; a held file drags out into whatever you're working on."
        case nil: nil
        }
    }
}

// MARK: - The pretend screen

private extension CGPoint {
    /// From `TourLayout`'s y-up points to the screen view's y-down ones, and back.
    var deskFlipped: CGPoint { CGPoint(x: x, y: TourLayout.size.height - y) }

    func offset(by size: CGSize) -> CGPoint { CGPoint(x: x - size.width, y: y - size.height) }
}

private extension CGRect {
    var deskFlipped: CGRect { CGRect(x: minX, y: TourLayout.size.height - maxY, width: width, height: height) }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension Animation {
    /// One of the surface's springs (`SurfaceMotion`), for setup's pretend notch: the same stiffness and
    /// damping the real one uses. With Reduce Motion, a quick ease.
    static func surface(_ spring: SpringParameters) -> Animation {
        Theme.reduceMotion ? Theme.quick : .interpolatingSpring(stiffness: spring.stiffness, damping: spring.damping)
    }
}

/// A value along piecewise-linear keyframes, `(time, value)` in order, as Core Animation runs a keyframe
/// animation's values: the real deposit's card is keyframed this way, so its copy here follows the same
/// timings.
private func ramp(_ t: CGFloat, _ frames: [(CGFloat, CGFloat)]) -> CGFloat {
    guard let first = frames.first, t > first.0 else { return frames.first?.1 ?? 0 }
    for (a, b) in zip(frames, frames.dropFirst()) where t <= b.0 {
        return a.1 + (b.1 - a.1) * (t - a.0) / max(b.0 - a.0, .ulpOfOne)
    }
    return frames.last?.1 ?? 0
}

/// A pretend MacBook screen top inside its bezel: the notch, a Notes window and a PDF. The tour and the
/// gesture step both show it, on the same `TourDesk`, and everything on it works: clicks, the fold's
/// Tuck button and lenses, dropping the PDF in and dragging it out, and swipes. Tuck's own drop
/// invitation, swipe tracker, flight path and springs run on its geometry (`TourLayout`), so nothing real
/// is touched and no permission is needed. The notch and fold are drawn as the real ones are, at about
/// seven tenths of their size, and black, closed or open.
struct PretendScreen: View {
    /// Changed through the model itself rather than a binding, so changes made after an animation (a
    /// drop landing) reach the step's text and chips at once.
    @ObservedObject var setup: SetupModel
    /// The gesture step marks where swipes count.
    let marksSwipeArea: Bool
    /// The gesture step's closed notch only opens: a swipe up (tucking Tuck away) does nothing, and the
    /// notch doesn't start drawing in as one goes up.
    var closedNotchOnlyOpens = false
    let dropInvitation: Bool
    let haptic: (HapticEvent) -> Void

    static let bezel: CGFloat = 8
    static var outerSize: CGSize {
        CGSize(width: TourLayout.size.width + bezel * 2, height: TourLayout.size.height + bezel * 2)
    }

    fileprivate static let space = "pretendScreen"
    fileprivate static let notes = AppIcons.icon(for: "com.apple.Notes")
    fileprivate static let pdf = NSWorkspace.shared.icon(for: .pdf)

    private struct Flight {
        var progress: CGFloat
        /// Into the fold, or back out of it to where the window was.
        let outbound: Bool
        let path: DepositFlight
        /// Arrived: the dot merges into the row it opens out into.
        var merging = false
    }

    /// The see-through copy that follows the pointer while the PDF is dragged, then goes where it was let go.
    private struct FileCopy {
        var center: CGPoint
        var scale: CGFloat
        var opacity: Double
        let fromDesk: Bool
        /// Over somewhere that takes it, the copy draws itself in a little and lets go of its name.
        var isOver = false
    }

    @State private var flight: Flight?
    /// The window is on its way into the fold: its row keeps its place empty until it lands.
    @State private var arriving = false
    /// The window has just landed: its row opens out in the blue tint, then clears.
    @State private var landed = false
    /// A drop on the closed notch is drawing into the mark: the card waits for it.
    @State private var depositing = false
    @State private var copy: FileCopy?
    /// Where the pointer took hold of the copy, from its centre, while a drag is in progress, and where
    /// the pointer is.
    @State private var grab: CGSize?
    @State private var pointer: CGPoint = .zero
    @State private var invitation: Int?
    /// Counts the drops on the closed notch, each drawing the drop's words into the mark.
    @State private var compressions = 0
    /// Counts the deposits that land in the mark, to pulse it once, as the real one pulses.
    @State private var pulses = 0
    @State private var pull: CGFloat = 0
    @State private var notchHover = false
    @State private var status: MiniStatus?
    @State private var statuses = 0
    @Environment(\.colorScheme) private var scheme

    private var desk: TourDesk { setup.desk }
    private var lenses: [StreamLens] { StreamLens.available(includingCopied: setup.settings.clipboardHistoryEnabled) }
    private var panelRect: CGRect {
        TourLayout.panel(height: MiniPanel.height(for: desk, hasStatus: status != nil)).deskFlipped
    }
    private var fileHome: CGPoint { TourLayout.file.deskFlipped }
    private var windowRect: CGRect { TourLayout.window.deskFlipped }
    /// How much Tuck holds, as the notch shows it: its card drops into the mark, and VoiceOver counts,
    /// only once what was deposited has landed (the window in its row, the drop in the mark).
    private var shownCount: Int { desk.count - (arriving ? 1 : 0) - (depositing ? 1 : 0) }
    /// The one drop target under the closed notch: a drag's invitation, or, pointing at an empty Tuck,
    /// the cue (level 0).
    private var bandLevel: Int? {
        if let invitation { return invitation }
        return notchHover && desk.count == 0 && !desk.isOpen && grab == nil ? 0 : nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            wallpaper
            swipeArea
            if marksSwipeArea && !desk.isOpen { swipeMark }
            menuBar
            if !desk.isWindowTucked && flight == nil {
                window
            }
            deskFile
            if desk.isOpen {
                panel
                    .transition(.asymmetric(insertion: .scale(scale: 0.5, anchor: .top).combined(with: .opacity),
                                            removal: .scale(scale: 0.6, anchor: .top).combined(with: .opacity)))
            }
            notch
            if let flight {
                FlyingWindow(progress: flight.progress, outbound: flight.outbound, path: flight.path,
                             attached: desk.isAttached)
                    .opacity(flight.merging ? 0 : 1)
            }
            if let copy {
                FileIcon(image: Self.pdf, name: "Itinerary.pdf", nameOpacity: copy.isOver ? 0 : 1)
                    .shadow(color: .black.opacity(grab == nil ? 0 : 0.25), radius: 6, y: 3)
                    .scaleEffect(copy.scale)
                    .opacity(copy.opacity)
                    .position(copy.center)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: TourLayout.size.width, height: TourLayout.size.height)
        .coordinateSpace(name: Self.space)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // The screen sits in its bezel, which the notch hangs from, as on a MacBook.
        .padding(Self.bezel)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.14 : 0.0)))
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.12), radius: 4, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pretend screen")
    }

    // MARK: Desktop

    private var wallpaper: some View {
        let colors: [Color] = scheme == .dark
            ? [Color(red: 0.17, green: 0.21, blue: 0.28), Color(red: 0.11, green: 0.13, blue: 0.18)]
            : [Color(red: 0.80, green: 0.86, blue: 0.93), Color(red: 0.90, green: 0.87, blue: 0.92)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(width: TourLayout.size.width, height: TourLayout.size.height)
            // Clicking elsewhere closes the fold, as on the real screen.
            .contentShape(Rectangle())
            .wrappedInButton(pressing: false, action: closeIfOpen)
            .accessibilityHidden(true)
    }

    private var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: 11))
            Text("Notes").font(.system(size: 11, weight: .bold))
            ForEach(["File", "Edit", "View"], id: \.self) { Text($0).font(.system(size: 11)) }
            Spacer()
            Image(systemName: "wifi").font(.system(size: 10, weight: .semibold))
            Text("9:41").font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(Color.primary.opacity(0.8))
        .padding(.horizontal, 14)
        .frame(width: TourLayout.size.width, height: TourLayout.menuBarHeight)
        .background(scheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.45))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A soft glow where swipes count, inside the screen, under the notch.
    private var swipeMark: some View {
        VStack(spacing: 4) {
            Ellipse()
                .fill(RadialGradient(colors: [Color.accentColor.opacity(0.24), Color.accentColor.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: 130))
                .frame(width: 280, height: 64)
            Text("swipe here")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.accentColor)
        }
        .position(x: TourLayout.size.width / 2, y: 44)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var window: some View {
        DeskWindowContent(attached: desk.isAttached)
            .modifier(WindowChrome(radius: 9))
            .frame(width: windowRect.width, height: windowRect.height)
            .position(windowRect.center)
            .transition(.opacity)
            // Clicks fall through to the desktop under it, which closes the fold.
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(desk.isAttached ? "Notes window, Trip Plan, with Itinerary.pdf attached" : "Notes window, Trip Plan")
    }

    /// The PDF stays on the desk: Tuck holds a reference to it. Dragging it lifts a copy, as Finder does.
    private var deskFile: some View {
        FileIcon(image: Self.pdf, name: "Itinerary.pdf")
            .opacity(copy?.fromDesk == true ? 0.45 : 1)
            .position(fileHome)
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    let start = grab ?? CGSize(width: value.startLocation.x - fileHome.x,
                                               height: value.startLocation.y - fileHome.y)
                    drag(from: true, to: value.location, grab: start)
                }
                .onEnded { value in dropFromDesk(at: value.location) })
            .help("Drag the PDF up to the notch")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Itinerary.pdf, on the desktop")
            .accessibilityHint("Drag it onto the notch to hold it in Tuck.")
            .accessibilityAction(named: "Drop onto the notch") { dropFromDesk(at: TourLayout.surface.deskFlipped.center) }
    }

    // MARK: The notch

    private var notch: some View {
        let surface = TourLayout.surface.deskFlipped
        return MiniNotch(notchWidth: TourLayout.notchSize.width, height: TourLayout.notchSize.height,
                         wing: TourLayout.wing, holds: desk.count > 0, showsCard: shownCount > 0, isHovering: notchHover,
                         pulse: pulses, compressions: compressions, isOpen: desk.isOpen,
                         isTuckedAway: desk.isTuckedAway, pull: desk.isOpen ? 0 : pull, invitation: bandLevel,
                         isDragging: invitation != nil, onClick: clickNotch)
            .onHover(perform: hoverNotch)
            .frame(width: surface.width + 200, height: 90, alignment: .top)
            .position(x: surface.midX, y: 45)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tuck's notch")
            .accessibilityValue(notchDescription)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens or closes Tuck. You can also swipe on it with two fingers.")
            .accessibilityAction { desk.isOpen ? closeIfOpen() : clickNotch() }
    }

    private var notchDescription: String {
        switch desk.stage {
        case .tucked: "Tucked away"
        case .collapsed: shownCount == 0 ? "Closed, empty" : "Closed, \(shownCount) in Tuck"
        case .expanded: "Open"
        case .full: "Unfolded, showing everything in Tuck"
        }
    }

    private func clickNotch() {
        guard !desk.isOpen else { return }
        clearStatus()
        withAnimation(.surface(desk.isTuckedAway ? SurfaceMotion.settle : SurfaceMotion.open)) { setup.desk.toggle() }
    }

    private func closeIfOpen() {
        guard desk.isOpen else { return }
        clearStatus()
        withAnimation(.surface(SurfaceMotion.close)) { setup.desk.close() }
    }

    /// Two-finger swipes over the notch (or the open fold) go to the real tracker.
    private var swipeArea: some View {
        let area = desk.isOpen ? panelRect.insetBy(dx: -6, dy: -6) : TourLayout.surface.deskFlipped.insetBy(dx: -70, dy: -50)
        return SwipeArea(stage: { desk.stage },
                         onPull: { pull = closedNotchOnlyOpens && desk.stage == .collapsed ? max($0, 0) : $0 },
                         onAction: swiped)
            .frame(width: area.width, height: area.height)
            .position(area.center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// As on the real notch, a swipe plays no haptic.
    private func swiped(_ action: SwipeGestureTracker.Action) {
        pull = 0
        if closedNotchOnlyOpens, action == .tuckAway { return }
        clearStatus()
        let animation: Animation = switch action {
        case .expand: .surface(SurfaceMotion.open)
        case .collapse: .surface(SurfaceMotion.close)
        case .unfold, .fold: Theme.fold
        default: .surface(SurfaceMotion.settle)
        }
        withAnimation(animation) { _ = setup.desk.apply(action) }
    }

    // MARK: Pointing

    /// Pointing at the closed notch opens nothing: one that holds something greets the pointer, lights
    /// its mark and offers its Tuck button; an empty one shows "Drop into Tuck".
    private func hoverNotch(_ inside: Bool) {
        withAnimation(.surface(SurfaceMotion.settle)) { notchHover = inside }
    }

    // MARK: The fold

    private var panel: some View {
        MiniPanel(desk: desk, lenses: lenses, hidesWindowRow: arriving, landed: landed,
                  dimsFileRow: copy?.fromDesk == false, status: status,
                  isDropTarget: grab != nil && copy?.fromDesk == true && panelRect.contains(pointer),
                  onTuck: tuck, onRestore: restore,
                  onLens: { lens in
                      clearStatus()
                      withAnimation(Theme.fold) { setup.desk.toggleLens(lens) }
                  },
                  onFold: {
                      clearStatus()
                      withAnimation(Theme.fold) { _ = setup.desk.apply(.fold) }
                  },
                  onExplain: { text, symbol in show(text, symbol: symbol) },
                  onOpenFile: {
                      show("A click opens it · drag it out to use it", symbol: "arrow.up.forward.app")
                  },
                  onDragFile: { location in drag(from: false, to: location, grab: .zero) },
                  onDropFile: dropFromPanel)
            .frame(width: panelRect.width, height: panelRect.height)
            .position(panelRect.center)
    }

    /// The fold's status line, as the real one says what an action did, and lets go after a while.
    private func show(_ text: String, symbol: String) {
        statuses += 1
        let mine = statuses
        withAnimation(Theme.quick) { status = MiniStatus(text: text, symbol: symbol) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            guard mine == statuses else { return }
            withAnimation(Theme.quick) { status = nil }
        }
    }

    private func clearStatus() {
        statuses += 1
        withAnimation(Theme.quick) { status = nil }
    }

    // MARK: Tucking and restoring: the window itself flies

    /// Tuck, on the band: the window flies up into the fold, onto its row's icon at the top of the list,
    /// as `DepositAnimator` flies the real card.
    private func tuck() {
        guard desk.isOpen, !desk.isWindowTucked, flight == nil else { return }
        show("Notes tucked", symbol: "arrow.down.to.line")
        guard !Theme.reduceMotion else {
            withAnimation(Theme.quick) { _ = setup.desk.tuckWindow() }
            return
        }
        // The window becomes its own flight in the same frame, so nothing jumps; its row opens at the top
        // and keeps its place empty until it lands there.
        arriving = true
        withAnimation(Theme.deposit) { _ = setup.desk.tuckWindow() }
        flight = Flight(progress: 0, outbound: true, path: TourLayout.flight(open: true))
        let duration = DepositFlight.duration
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.2, 0, 0.2, 1, duration: duration)) { flight?.progress = 1 }
        }
        // Once it's the icon's size it is a blue dot, which opens out into its row in the blue tint, on
        // the clock, as the real card lands on an open fold; the tint then clears.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * Self.arrival) {
            withAnimation(.linear(duration: duration * (1 - Self.arrival))) { flight?.merging = true }
            arriving = false
            withAnimation(.timingCurve(0.2, 0.9, 0.25, 1, duration: 0.12)) { landed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.easeInOut(duration: 0.1)) { landed = false }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { flight = nil }
    }

    /// The window comes back out of its row's icon, along the same path, to exactly where it was.
    private func restore() {
        guard desk.isOpen, desk.isWindowTucked, flight == nil else { return }
        show("Notes restored to \(Placement.original.restoreDescription)", symbol: Theme.symbol(for: .original))
        let row = desk.rows.firstIndex(of: .window) ?? 0
        withAnimation(Theme.deposit) { _ = setup.desk.restoreWindow() }
        guard !Theme.reduceMotion else { return }
        flight = Flight(progress: 0, outbound: false, path: TourLayout.flight(open: true, row: row))
        let duration = DepositFlight.duration
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.2, 0, 0, 1, duration: duration)) { flight?.progress = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { flight = nil }
    }

    /// How far through a flight the window has become the dot, as `DepositAnimator` times it.
    private static let arrival = 0.85
    /// How long a drop on the closed notch takes to draw into the mark, before its card drops in.
    private static let compression = 0.4

    // MARK: Dragging the PDF, with the real invitation

    /// The copy follows the pointer from where it was taken hold of. From the desk, the notch invites it
    /// as Tuck invites a real drag; the cursor shows the copy badge wherever letting go would be taken.
    private func drag(from desktop: Bool, to location: CGPoint, grab start: CGSize) {
        grab = start
        pointer = location
        let accepting = desktop ? followDesk(location) : takesNote(at: location)
        // Crossing into Tuck's drop target plays one tick, as a real drag does.
        if desktop, accepting, copy?.isOver != true { haptic(.dropTargetEntered) }
        let center = location.offset(by: start)
        if copy?.isOver != accepting {
            // Moves stay under the pointer; only the change of state eases.
            copy = FileCopy(center: center, scale: copy?.scale ?? 1.04, opacity: 0.8, fromDesk: desktop, isOver: copy?.isOver ?? false)
            withAnimation(.easeOut(duration: 0.12)) {
                copy = FileCopy(center: center, scale: accepting ? 0.85 : 1.04, opacity: 0.8, fromDesk: desktop, isOver: accepting)
            }
        } else {
            copy = FileCopy(center: center, scale: accepting ? 0.85 : 1.04, opacity: 0.8, fromDesk: desktop, isOver: accepting)
        }
        (accepting ? NSCursor.dragCopy : NSCursor.arrow).set()
    }

    /// The closed notch's band follows the drag: with the drop invitation on, it widens as the drag nears,
    /// as Tuck's real invitation does; off, it shows only while the drag is over the notch. Either way it
    /// opens nothing. Returns whether letting go here would be taken.
    private func followDesk(_ location: CGPoint) -> Bool {
        let accepting = acceptsFromDesk(at: location)
        let level: Int?
        if desk.isOpen {
            level = nil
        } else if dropInvitation {
            level = DropApproach.invitation(pointer: location.deskFlipped, zone: TourLayout.zone, wasInviting: invitation != nil)
        } else {
            level = accepting ? DropApproach.levels : nil
        }
        if level != invitation {
            withAnimation(.surface(SurfaceMotion.pop)) { invitation = level }
        }
        return accepting
    }

    private func acceptsFromDesk(at location: CGPoint) -> Bool {
        let zone = TourLayout.zone
        let target = dropInvitation ? zone.target : zone.surface.insetBy(dx: -4, dy: -4)
        return target.contains(location.deskFlipped) || (desk.isOpen && panelRect.contains(location))
    }

    private func takesNote(at location: CGPoint) -> Bool {
        !desk.isWindowTucked && windowRect.contains(location) && !panelRect.contains(location)
    }

    private func dropFromDesk(at location: CGPoint) {
        NSCursor.arrow.set()
        let start = grab ?? .zero
        grab = nil
        let from = copy?.center ?? location.offset(by: start)
        guard acceptsFromDesk(at: location) else {
            // Refused: the copy slides back onto the file, and the band lets go.
            withAnimation(.surface(SurfaceMotion.pop)) { invitation = nil }
            settle(copyFrom: from, to: fileHome, scale: 1, desktop: true,
                   animation: .surface(SurfaceMotion.release), duration: 0.35)
            return
        }
        // Taken, with one tick: the drag's picture goes at once, as a real drop's does. Closed, the drop's
        // words draw into the mark as the band folds back, and its card drops in as they arrive; open,
        // its row arrives at the top of the list.
        let closed = !desk.isOpen
        haptic(.deposited)
        settle(copyFrom: from, to: from, scale: (copy?.scale ?? 1) * 0.9, desktop: true,
               animation: .easeOut(duration: 0.12), duration: 0.12)
        let draws = closed && !Theme.reduceMotion
        if draws { compressions += 1 }
        withAnimation(.surface(SurfaceMotion.pop)) { invitation = nil }
        var held = false
        withAnimation(Theme.deposit) { held = setup.desk.holdFile() }
        guard draws else { return }
        depositing = held
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.compression) {
            depositing = false
            pulses += 1
        }
    }

    /// The held row let go: over the Notes window the PDF goes into the note; anywhere else it slides
    /// back to its row, still held.
    private func dropFromPanel(at location: CGPoint) {
        NSCursor.arrow.set()
        grab = nil
        let from = copy?.center ?? location
        guard takesNote(at: location) else {
            let row = desk.rows.firstIndex(of: .file) ?? 0
            settle(copyFrom: from, to: TourLayout.rowIcon(row).deskFlipped, scale: TourLayout.rowIconSize / FileIcon.size,
                   desktop: false, animation: .surface(SurfaceMotion.release), duration: 0.35)
            return
        }
        let spot = DeskWindowContent.attachmentPoint(in: windowRect)
        settle(copyFrom: from, to: spot, scale: 0.4, desktop: false, animation: .easeIn(duration: 0.22), duration: 0.22) {
            withAnimation(.surface(SurfaceMotion.pop)) { _ = setup.desk.attachFile() }
        }
    }

    /// Animates the copy from where it was let go to where it's going, fading, then removes it.
    private func settle(copyFrom start: CGPoint, to end: CGPoint, scale: CGFloat, desktop: Bool,
                        animation: Animation, duration: TimeInterval, then finish: (() -> Void)? = nil) {
        guard !Theme.reduceMotion else {
            copy = nil
            finish?()
            return
        }
        let over = copy?.isOver ?? false
        copy = FileCopy(center: start, scale: copy?.scale ?? 1.04, opacity: 0.8, fromDesk: desktop, isOver: over)
        DispatchQueue.main.async {
            withAnimation(animation) { copy = FileCopy(center: end, scale: scale, opacity: 0, fromDesk: desktop, isOver: over) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if grab == nil { copy = nil }
            finish?()
        }
    }
}

// MARK: - Pieces of the screen

private extension View {
    /// The view as a plain button: a real control, so a first click in a window that isn't key still
    /// counts, and VoiceOver can press it. `pressing` gives a little as it's pressed.
    func wrappedInButton(pressing: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { self }.buttonStyle(PressableButtonStyle(scale: pressing ? 0.97 : 1))
    }
}

/// The fold's type scale (`Font.panelTitle` and the rest) at the pretend fold's size, a little over
/// three quarters of the real one so it stays readable.
private enum MiniType {
    /// `panelTitle`: a row's title.
    static let title = Font.system(size: 10, weight: .medium)
    /// `panelHeadline`: the drop target's words.
    static let headline = Font.system(size: 10, weight: .semibold)
    /// `panelSubtitle`: the line beside a title, the empty cue, the status line.
    static let subtitle = Font.system(size: 9.5)
    /// `panelControl`: buttons, and the full fold's title.
    static let control = Font.system(size: 9.5, weight: .medium)
    /// The lenses' `subheadline`.
    static let lens = Font.system(size: 9, weight: .medium)
    /// The closed notch's drop words, semibold as the real ones are.
    static let prompt = Font.system(size: 10, weight: .semibold)
}

/// What the fold's status line says.
private struct MiniStatus: Equatable {
    let text: String
    let symbol: String
}

/// Tuck's notch outline, as the real surface draws it: flowing out of the top edge through a quarter
/// circle either side (its shoulders), with rounded lower corners. The top edge is left open, so a
/// stroke traces only the sides and bottom.
private struct NotchOutline: Shape {
    var shoulder: CGFloat
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.width / 2, rect.height)
        let r = max(min(radius, rect.height - s, (rect.width - 2 * s) / 2), 0)
        let k = s * 0.5523
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s),
                      control1: CGPoint(x: rect.minX + k, y: rect.minY),
                      control2: CGPoint(x: rect.minX + s, y: rect.minY + s - k))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s + r, y: rect.maxY), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                      control1: CGPoint(x: rect.maxX - s, y: rect.minY + s - k),
                      control2: CGPoint(x: rect.maxX - k, y: rect.minY))
        return path
    }
}

/// Tuck's closed surface, drawn small for setup, black like the notch it continues. Pointing at it opens
/// nothing. Empty, it is the bare notch, and pointed at it shows "Drop into Tuck" in a band under the
/// notch. While Tuck holds something its wings come out: the mark on the left, faint with its card in the
/// dip, and a grey dot on the right. Pointed at, the mark greets the pointer and lights up in Tuck blue,
/// and the dot gives way to the Tuck button's arrow; a deposit swells the mark once it lands. A drag
/// widens it into one drop target that says what it will hold, rimmed in blue as the drag nears, and a
/// drop draws those words into the mark. It stretches with a swipe, and draws its wings in when tucked away.
struct MiniNotch: View {
    let notchWidth: CGFloat
    let height: CGFloat
    let wing: CGFloat
    /// Tuck holds something: the wings are out, with the mark and the dot.
    var holds = false
    /// What was deposited has landed: the card rests in the mark's dip.
    var showsCard = false
    var isHovering = false
    /// Changes with each deposit that lands, to pulse the mark once.
    var pulse = 0
    /// Changes with each drop on the closed notch, to draw its words into the mark.
    var compressions = 0
    /// The open fold replaces the surface: only the hardware notch shows, over the fold.
    var isOpen = false
    var isTuckedAway = false
    /// A swipe in progress: up to 1 pulling down, down to -1 pulling up.
    var pull: CGFloat = 0
    /// The band under the notch: nil without one, 0 (the empty cue, or a drag just in range) up to
    /// `DropApproach.levels` (a drag over the drop target).
    var invitation: Int?
    /// The band is for a drag, and says what it will hold, rather than the empty cue.
    var isDragging = false
    var onClick: () -> Void = {}
    /// Counts the pointer's arrivals, so the mark greets each one.
    @State private var greetings = 0

    /// `SurfaceMetrics.shoulder` and `notchCornerRadius`, at this size.
    static let shoulder: CGFloat = 6
    static let cornerRadius: CGFloat = 9
    /// The band at its fullest, where the words a drop draws into the mark start from.
    private static let bandHeight: CGFloat = 21

    /// How far the words a drop draws into the mark have gone, and how they shrink and fade on the way.
    private struct Compression {
        var travel: CGFloat = 0
        var scale: CGFloat = 1
        var opacity: Double = 0
    }

    private var closeness: CGFloat { CGFloat(invitation ?? 0) / CGFloat(DropApproach.levels) }
    /// Empty, or swiped away, the closed surface rests in the notch.
    private var restsInNotch: Bool { !holds || isTuckedAway }
    private var isPointedAt: Bool { isHovering && !isOpen && !restsInNotch && invitation == nil }
    private var contentOpacity: CGFloat {
        if isOpen || !holds { return 0 }
        if isTuckedAway { return max(pull, 0) }
        return pull < 0 ? 1 + pull : 1
    }

    var body: some View {
        Button(action: onClick) { surface }
            .buttonStyle(PressableButtonStyle(scale: 0.97))
            // The notch is always black, so what's on it is drawn for the dark appearance.
            .environment(\.colorScheme, .dark)
            .onChange(of: isHovering) {
                if isPointedAt, !Theme.reduceMotion { greetings += 1 }
            }
    }

    private var surface: some View {
        let banded = invitation != nil && !isOpen
        let wings: CGFloat
        if isOpen {
            wings = 0
        } else if banded {
            wings = wing
        } else if restsInNotch {
            wings = isTuckedAway ? wing * max(pull, 0) * 0.5 : 0
        } else {
            wings = wing * (pull < 0 ? 1 + pull * 0.8 : 1)
        }
        // The real band's growth, at this size: room for the words, a little more as a drag nears.
        let grow = banded ? CGSize(width: 3 + 4.5 * closeness, height: 18 + 3 * closeness) : .zero
        // Pointed at, the surface grows a touch, as the real one does.
        let hover = isPointedAt ? CGSize(width: 3, height: 1.5) : .zero
        let stretch = isOpen || isTuckedAway ? 0 : max(pull, 0) * 6
        let width = notchWidth + (wings + grow.width + hover.width) * 2 + Self.shoulder * 2
        let shapeHeight = height + grow.height + hover.height + stretch
        let shape = NotchOutline(shoulder: Self.shoulder, radius: Self.cornerRadius)

        // What's on the surface rides over it, so the wings' content never sizes the shape.
        return shape.fill(Color.black)
            .overlay {
                if banded, isDragging {
                    shape.stroke(Theme.accent.opacity(0.3 + 0.7 * closeness),
                                 lineWidth: invitation == DropApproach.levels ? 2 : 1.5)
                        .mask {
                            // Faded out up the shoulders, as on the real notch, so none runs along the top.
                            VStack(spacing: 0) {
                                Color.clear.frame(height: 1.5)
                                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                                    .frame(height: Self.shoulder)
                                Color.black
                            }
                        }
                }
            }
            .frame(width: width, height: shapeHeight)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if banded {
                        words(dragging: isDragging)
                            .opacity(isDragging ? 0.8 + 0.2 * closeness : 1)
                            .frame(height: grow.height)
                            .offset(y: height)
                            .transition(.opacity)
                    }
                    HStack(spacing: 0) {
                        MiniMark(greetings: greetings, isLit: isPointedAt, showsCard: showsCard)
                            .modifier(Pulse(trigger: pulse))
                            .frame(width: wing)
                        Spacer(minLength: 0)
                        MiniTuckButton(isShown: isPointedAt)
                            .frame(width: wing)
                    }
                    .frame(width: notchWidth + wing * 2, height: height)
                    .opacity(contentOpacity)
                    compression
                }
            }
            // Open, only the notch itself takes the pointer, so the band's lenses and Tuck button beside it
            // keep theirs.
            .contentShape(Rectangle().inset(by: isOpen ? Self.shoulder : -8))
    }

    /// The one drop target's glyph and words: what the drag carries, or, with nothing dragged, the cue.
    private func words(dragging: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: dragging ? SurfaceView.dropSymbol(.file) : "tray.and.arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(dragging ? Theme.accent : Theme.secondaryText)
            Text(dragging ? DropKind.file.label : DropKind.invitation)
                .font(MiniType.prompt)
                .foregroundStyle(dragging ? Theme.primaryText : Theme.secondaryText)
        }
        .fixedSize()
    }

    /// A drop on the closed notch: its words draw together into the mark, shrinking and fading as the
    /// band folds back, with the real surface's spring and timings. Under Reduce Motion nothing is drawn
    /// in; the words simply fade with the band.
    private var compression: some View {
        let toMark = CGSize(width: -(notchWidth + wing) / 2, height: -(height + Self.bandHeight) / 2)
        return KeyframeAnimator(initialValue: Compression(), trigger: compressions) { value in
            words(dragging: true)
                .frame(height: Self.bandHeight)
                .scaleEffect(value.scale)
                .offset(x: toMark.width * value.travel, y: height + toMark.height * value.travel)
                .opacity(value.opacity)
        } keyframes: { _ in
            KeyframeTrack(\.travel) {
                MoveKeyframe(0)
                SpringKeyframe(1, duration: 0.48, spring: Spring(mass: 1, stiffness: 170, damping: 24))
            }
            KeyframeTrack(\.scale) {
                MoveKeyframe(1)
                LinearKeyframe(0.15, duration: 0.42, timingCurve: .easeIn)
            }
            KeyframeTrack(\.opacity) {
                MoveKeyframe(1)
                LinearKeyframe(0, duration: 0.42, timingCurve: .easeIn)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Tuck's mark for the closed notch's left wing, the line `TuckLogo` draws: faint at rest, lit in Tuck blue
/// while pointed at, with the card in its dip once something has landed, dropping in from above. Each
/// greeting (the pointer arriving) runs the real mark's: the dip reaches down, springs back a little past
/// rest and settles, and the card rides it. Under Reduce Motion the mark only lights, and the card fades in.
private struct MiniMark: View {
    var greetings = 0
    var isLit = false
    var showsCard = false

    var body: some View {
        let side = TourLayout.notchMarkSize
        let style = StrokeStyle(lineWidth: TuckLogo.lineWidth(side: side), lineCap: .round, lineJoin: .round)
        let reach = TuckLogo.greetingReach
        let drop = Theme.reduceMotion ? 0 : TuckLogo.cardDrop(side: side)
        KeyframeAnimator(initialValue: CGFloat(0), trigger: greetings) { value in
            ZStack {
                LogoLine(reach: value)
                    .stroke(Color(nsColor: .labelColor), style: style)
                    .opacity(TuckLogo.restingOpacity)
                LogoLine(reach: value)
                    .stroke(Theme.accent, style: style)
                    .opacity(isLit ? 1 : 0)
                LogoCard()
                    .stroke(Theme.accent, style: style)
                    .offset(y: TuckLogo.reachDrop(side: side) * value - (showsCard ? 0 : drop))
                    .opacity(showsCard ? 1 : 0)
                    .animation(Theme.reduceMotion ? Theme.quick : .interpolatingSpring(stiffness: 385, damping: 28),
                               value: showsCard)
            }
            .frame(width: side, height: side)
        } keyframes: { _ in
            CubicKeyframe(reach[1], duration: TuckLogo.greetingLeg(1))
            CubicKeyframe(reach[2], duration: TuckLogo.greetingLeg(2))
            CubicKeyframe(reach[3], duration: TuckLogo.greetingLeg(3))
            CubicKeyframe(reach[4], duration: TuckLogo.greetingLeg(4))
        }
        .accessibilityHidden(true)
    }
}

/// The card that rests in the mark's dip while Tuck holds something.
private struct LogoCard: Shape {
    func path(in rect: CGRect) -> Path { Path(TuckLogo.cardPath(side: rect.width)) }
}

/// The closed notch's right wing: a grey dot at rest that, pointed at, shrinks away as the Tuck button's
/// arrow rises in Tuck blue. Under Reduce Motion one simply fades into the other.
private struct MiniTuckButton: View {
    var isShown = false

    var body: some View {
        let side = TourLayout.notchMarkSize
        let lineWidth = TuckLogo.lineWidth(side: side)
        let moves = !Theme.reduceMotion
        ZStack {
            Circle()
                .fill(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 4.5, height: 4.5)
                .scaleEffect(isShown && moves ? 0.4 : 1)
                .opacity(isShown ? 0 : 1)
            LogoArrow()
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .frame(width: side, height: side)
                .scaleEffect(isShown || !moves ? 1 : 0.6)
                .offset(y: isShown || !moves ? 0 : lineWidth)
                .opacity(isShown ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}

/// The Tuck button's arrow, in the logo's own line.
private struct LogoArrow: Shape {
    func path(in rect: CGRect) -> Path { Path(TuckLogo.arrowPath(side: rect.width)) }
}

/// A deposit landing in the mark: the mark swells once, as the real one does.
private struct Pulse: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            LinearKeyframe(1.12, duration: 0.1)
            LinearKeyframe(1, duration: 0.14)
        }
    }
}

/// The open fold, drawn small, as the real one is laid out: black, as the notch it hangs from is, and so
/// drawn dark whatever the Light or Dark setting. Its band sits level with the notch: in the shallow
/// fold, Tuck for the window in front on the left and the lenses right beside the notch; in the full
/// fold, "Everything in Tuck" with search and fold. Under it, one line per thing Tuck holds, newest
/// first, with hairlines between; Arrange windows at the foot of the full fold; and the status line, only
/// while it has something to say. Every part has a set height, so the fold's height, and where each row
/// is, are known.
private struct MiniPanel: View {
    static let footerHeight: CGFloat = 18
    /// Under the list, and under everything.
    static let listPadding: CGFloat = 2
    static let bottomPadding: CGFloat = 3
    /// `Theme.foldRadius` at this size.
    static let cornerRadius: CGFloat = 14

    let desk: TourDesk
    let lenses: [StreamLens]
    let hidesWindowRow: Bool
    let landed: Bool
    let dimsFileRow: Bool
    let status: MiniStatus?
    let isDropTarget: Bool
    let onTuck: () -> Void
    let onRestore: () -> Void
    let onLens: (StreamLens) -> Void
    let onFold: () -> Void
    /// A control that does something only in the real Tuck explains itself on the status line.
    let onExplain: (String, String) -> Void
    let onOpenFile: () -> Void
    let onDragFile: (CGPoint) -> Void
    let onDropFile: (CGPoint) -> Void

    /// Arrange windows, at the foot of the full fold, while there's a window in front.
    private static func showsArrange(_ desk: TourDesk) -> Bool { desk.isFull && !desk.isWindowTucked }

    /// The whole fold, notch included: the band, the rows or the one-line cue in their place, Arrange
    /// windows and the status line. It grows and shrinks with them, as the real fold sizes itself.
    static func height(for desk: TourDesk, hasStatus: Bool) -> CGFloat {
        let rows = CGFloat(max(desk.rows.count, 1))
        return TourLayout.listTop + TourLayout.rowHeight * rows + listPadding
            + (showsArrange(desk) ? TourLayout.rowHeight : 0) + (hasStatus ? footerHeight : 0) + bottomPadding
    }

    private var wingWidth: CGFloat { (TourLayout.panelWidth - TourLayout.notchSize.width) / 2 }

    var body: some View {
        let shape = NotchOutline(shoulder: MiniNotch.shoulder, radius: Self.cornerRadius)
        VStack(spacing: 0) {
            band.frame(height: TourLayout.notchSize.height)
            list
                .padding(.horizontal, TourLayout.rowIconInset - 7)
                .padding(.top, TourLayout.listTop - TourLayout.notchSize.height)
                .padding(.bottom, Self.listPadding)
            if Self.showsArrange(desk) {
                ArrangeRow(action: { onExplain("Arrange places the window in front without tucking it", "rectangle.split.2x1") })
                    .overlay(alignment: .top) { MiniSeparator() }
                    .padding(.horizontal, TourLayout.rowIconInset - 7)
                    .transition(.opacity)
            }
            if let status {
                footer(status)
            }
        }
        .frame(width: TourLayout.panelWidth, height: Self.height(for: desk, hasStatus: status != nil), alignment: .top)
        // The surface reaches past the fold's content by its shoulders, where it meets the top edge.
        .background(shape.fill(Color.black).padding(.horizontal, -MiniNotch.shoulder))
        .overlay {
            if isDropTarget { dropTarget }
        }
        // One shadow, under the whole fold, not one under each thing on it.
        .compositingGroup()
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tuck's fold")
    }

    // MARK: Band

    /// The wings are set widths whether or not they hold anything, so the notch's gap stays over the notch.
    private var band: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: wingWidth)
                .overlay(alignment: .leading) {
                    leading
                        .padding(.leading, 9)
                        .padding(.trailing, 4)
                }
            Color.clear
                .frame(width: TourLayout.notchSize.width)
            Color.clear
                .frame(width: wingWidth)
                .overlay(alignment: desk.isFull ? .trailing : .leading) {
                    trailing
                        .padding(.leading, 4)
                        .padding(.trailing, 7)
                }
        }
    }

    @ViewBuilder private var leading: some View {
        if desk.isFull {
            Text("Everything in Tuck")
                .font(MiniType.control)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .transition(.opacity)
        } else if !desk.isWindowTucked {
            Button(action: onTuck) {
                HStack(spacing: 4) {
                    Image(nsImage: PretendScreen.notes).resizable().interpolation(.high)
                        .frame(width: 11, height: 11)
                    Text("Tuck")
                    // The window flies up into Tuck, so the glyph points up.
                    Image(systemName: "arrow.up")
                        .font(.system(size: 7.5, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(MiniButtonStyle())
            .help("Tuck “Trip Plan” from Notes")
            .accessibilityLabel("Tuck Trip Plan, Notes")
            .accessibilityHint("Puts the Notes window away into Tuck.")
            .transition(.opacity)
        }
    }

    @ViewBuilder private var trailing: some View {
        if desk.isFull {
            HStack(spacing: 1) {
                Button("Search", systemImage: "magnifyingglass") {
                    onExplain("In Tuck, search narrows the list as you type", "magnifyingglass")
                }
                .help("Search everything in Tuck")
                Button("Fold", systemImage: "chevron.up", action: onFold)
                    .help("Fold back · or swipe up")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(MiniIconButtonStyle())
            .transition(.opacity)
        } else if desk.count > 0 {
            MiniLensCluster(lenses: lenses, desk: desk, onLens: onLens)
                .transition(.opacity)
        }
    }

    // MARK: List

    /// The stream's rows, or a one-line cue in their place: an empty Tuck never opens into an empty fold.
    @ViewBuilder private var list: some View {
        if desk.stream.isEmpty {
            MiniCue(symbol: "tray.and.arrow.down", text: DropKind.invitation)
        } else if desk.rows.isEmpty {
            MiniCue(symbol: "line.3.horizontal.decrease", text: "Nothing here yet")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(desk.rows.enumerated()), id: \.element) { index, item in
                    row(item)
                        // Between rows, over them, so every row keeps its height.
                        .overlay(alignment: .top) {
                            if index > 0 { MiniSeparator() }
                        }
                        .transition(.opacity)
                }
            }
        }
    }

    @ViewBuilder private func row(_ item: TourDesk.Item) -> some View {
        switch item {
        case .window:
            // A window still on its way up keeps its place empty until it lands in it.
            WindowRow(isLanding: landed, action: onRestore)
                .opacity(hidesWindowRow ? 0 : 1)
        case .file:
            HeldFileRow(onOpen: onOpenFile, onDrag: onDragFile, onDrop: onDropFile)
                .opacity(dimsFileRow ? 0.5 : 1)
        }
    }

    // MARK: Foot

    /// What the last action did, in a short line at the foot of the fold, there only while it has
    /// something to say.
    private func footer(_ status: MiniStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol).accessibilityHidden(true)
            Text(status.text).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(MiniType.subtitle)
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: Self.footerHeight)
        .transition(.opacity)
    }

    /// The open fold as a drop target: one blue-tinted field with the drop's glyph and what it will do.
    private var dropTarget: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: TourLayout.notchSize.height)
            Label(DropKind.file.label, systemImage: SurfaceView.dropSymbol(.file))
                .font(MiniType.headline)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    // Opaque under the tint, so the rows beneath don't show through the words.
                    RoundedRectangle(cornerRadius: Self.cornerRadius - 4, style: .continuous).fill(Color.black)
                    RoundedRectangle(cornerRadius: Self.cornerRadius - 4, style: .continuous).fill(Theme.accentTint)
                }
                .padding(4)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// The lenses, one small cluster right beside the notch, as `LensCluster` draws them: Windows, Files and
/// Copied (while clipboard history is on), each with how many it holds. Where there's too little room
/// for the counts, the names stand alone and the counts move to the tooltip.
private struct MiniLensCluster: View {
    let lenses: [StreamLens]
    let desk: TourDesk
    let onLens: (StreamLens) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            cluster(showsCounts: true)
            cluster(showsCounts: false)
        }
    }

    private func cluster(showsCounts: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(lenses, id: \.self) { lens in
                MiniLensChip(lens: lens, count: desk.stream.filter { $0.lens == lens }.count, showsCount: showsCounts,
                             isSelected: desk.lens == lens) { onLens(lens) }
            }
        }
        .padding(1.5)
        .background(Theme.stone, in: .capsule)
        .fixedSize()
    }
}

private struct MiniLensChip: View {
    let lens: StreamLens
    let count: Int
    let showsCount: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(lens.title)
                if showsCount {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                }
            }
            .font(MiniType.lens)
            .foregroundStyle(isSelected ? Theme.accent : Theme.primaryText)
            .padding(.horizontal, 4.5)
            .frame(height: 14)
            .background(Capsule().fill(isSelected ? Theme.accentTint : (isHovering ? Theme.primaryText.opacity(0.07) : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(count == 0 && !isSelected)
        .opacity(count == 0 && !isSelected ? 0.45 : 1)
        .onHover { isHovering = $0 }
        .animation(Theme.quick, value: isHovering)
        .help(isSelected ? "Show everything again" : "Show only \(lens.title.lowercased()) · \(count)")
        .accessibilityLabel("\(lens.title), \(count)")
        .accessibilityHint(isSelected ? "Shows everything again" : "Shows only \(lens.title.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row's icon and title on one line, with the line beside it in the secondary colour.
private struct RowContent: View {
    let image: NSImage
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: TourLayout.rowIconSize, height: TourLayout.rowIconSize)
            Text(title).font(MiniType.title).foregroundStyle(Theme.primaryText)
            if let detail {
                Text(detail).font(MiniType.subtitle).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .frame(height: TourLayout.rowHeight - MiniRowChrome.verticalPadding * 2)
    }
}

/// The tucked window: its app and title on one line, restored with a click. Just landed, it opens out
/// in the blue tint.
private struct WindowRow: View {
    let isLanding: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RowContent(image: PretendScreen.notes, title: "Notes", detail: "Trip Plan")
        }
        .buttonStyle(MiniRowButtonStyle(isHovering: hovering, isActive: isLanding))
        .onHover { hovering = $0 }
        .help("Trip Plan, tucked just now · click to restore")
        .accessibilityLabel("Notes, Trip Plan, tucked just now")
        .accessibilityHint("Restores the window where it was.")
    }
}

private struct HeldFileRow: View {
    let onOpen: () -> Void
    let onDrag: (CGPoint) -> Void
    let onDrop: (CGPoint) -> Void
    @State private var hovering = false

    var body: some View {
        RowContent(image: PretendScreen.pdf, title: "Itinerary.pdf")
            .modifier(MiniRowChrome(isHovering: hovering))
            .onHover { hovering = $0 }
            .onTapGesture(perform: onOpen)
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named(PretendScreen.space))
                .onChanged { onDrag($0.location) }
                .onEnded { onDrop($0.location) })
            .help("PDF document, held just now · click to open · drag it out to use it")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("File, Itinerary.pdf, held just now")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Drag into the Notes window") {
                onDrop(DeskWindowContent.attachmentPoint(in: TourLayout.window.deskFlipped))
            }
    }
}

/// Arrange windows, at the foot of the full fold, as `ArrangeWindowsButton` lays it out: what it does, and
/// the window in front it would place.
private struct ArrangeRow: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: TourLayout.rowIconSize)
                    .accessibilityHidden(true)
                Text("Arrange windows").font(MiniType.control)
                Spacer(minLength: 4)
                Image(nsImage: PretendScreen.notes).resizable().interpolation(.high)
                    .frame(width: 11, height: 11)
                Text("Notes").font(MiniType.subtitle).foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)
            .lineLimit(1)
            .frame(height: TourLayout.rowHeight - MiniRowChrome.verticalPadding * 2)
        }
        .buttonStyle(MiniRowButtonStyle(isHovering: hovering))
        .onHover { hovering = $0 }
        .help("Place the window in front on screen")
        .accessibilityLabel("Arrange windows, Notes")
    }
}

/// A short line in place of the list: the empty cue, or a lens with nothing in it. Faint, centred, one line.
private struct MiniCue: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(MiniType.subtitle)
            .foregroundStyle(Theme.tertiaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: TourLayout.rowHeight)
    }
}

/// The thin line between rows, starting under their text, as a source list has it.
private struct MiniSeparator: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1 / displayScale)
            .padding(.leading, MiniRowChrome.horizontalPadding + TourLayout.rowIconSize + 7)
            .padding(.trailing, MiniRowChrome.horizontalPadding)
            .accessibilityHidden(true)
    }
}

// MARK: - The fold's controls, at the pretend fold's size

/// `RowChrome`: nothing at rest, a stone highlight under the pointer, the blue tint while pressed or
/// just landed.
private struct MiniRowChrome: ViewModifier {
    static let horizontalPadding: CGFloat = 7
    static let verticalPadding: CGFloat = 4

    var isHovering: Bool
    var isActive = false
    var isPressed = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive || isPressed ? Theme.rowActive : (isHovering ? Theme.rowHover : .clear))
            )
            .contentShape(Rectangle())
    }
}

/// `RowButtonStyle`: a whole row that acts on a click.
private struct MiniRowButtonStyle: ButtonStyle {
    var isHovering: Bool
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(MiniRowChrome(isHovering: isHovering, isActive: isActive, isPressed: configuration.isPressed))
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// `PanelButtonStyle`: a rounded rectangle on stone that darkens on hover and presses in.
private struct MiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MiniButton(configuration: configuration)
    }

    private struct MiniButton: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(MiniType.control)
                .lineLimit(1)
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 6)
                .frame(minHeight: 17)
                .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(configuration.isPressed || isHovering ? Theme.primaryText.opacity(0.1) : Theme.stone))
                .contentShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                .scaleEffect(configuration.isPressed && !Theme.reduceMotion ? 0.97 : 1)
                .onHover { isHovering = $0 }
                .animation(Theme.press, value: configuration.isPressed)
                .animation(Theme.quick, value: isHovering)
        }
    }
}

/// `PanelIconButtonStyle`: a symbol alone, with stone under it on hover.
private struct MiniIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MiniIconButton(configuration: configuration)
    }

    private struct MiniIconButton: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 17, height: 17)
                .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(configuration.isPressed || isHovering ? Theme.stone : .clear))
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .animation(Theme.press, value: configuration.isPressed)
                .animation(Theme.quick, value: isHovering)
        }
    }
}

// MARK: - The desk

/// A file on the desk, as Finder shows one: its icon, and its name under it.
private struct FileIcon: View {
    static let size: CGFloat = 40

    let image: NSImage
    let name: String?
    var nameOpacity: Double = 1

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: image).resizable().frame(width: Self.size, height: Self.size)
            if let name {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .windowBackgroundColor).opacity(0.55)))
                    .opacity(nameOpacity)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The Notes window's title bar and a few lines of a note, with the PDF attached once it's dragged in.
/// An ordinary window, in the person's Light or Dark appearance.
private struct DeskWindowContent: View {
    let attached: Bool

    static let background = Color(nsColor: .textBackgroundColor)
    /// The note's longest line, inside its margins.
    private static let lineWidth = TourLayout.window.width - 28

    /// Where an attachment lands in the note, in the screen's space.
    static func attachmentPoint(in window: CGRect) -> CGPoint {
        CGPoint(x: window.minX + 62, y: window.maxY - 26)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in
                        Circle().fill(color.opacity(0.75)).frame(width: 8, height: 8)
                    }
                }
                Spacer(minLength: 4)
                Text("Trip Plan").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    .fixedSize()
                Spacer(minLength: 4)
                Color.clear.frame(width: 34, height: 8)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color(nsColor: .windowBackgroundColor))
            Rectangle().fill(Theme.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("Lisbon in May").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primaryText)
                ForEach(Array([0.92, 0.78, 0.86, 0.5].enumerated()), id: \.offset) { _, fraction in
                    Capsule().fill(Theme.faint).frame(width: Self.lineWidth * fraction, height: 5)
                }
                Text("Day one").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    .padding(.top, 2)
                Capsule().fill(Theme.faint).frame(width: Self.lineWidth * 0.7, height: 5)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            Spacer(minLength: 0)
            if attached {
                HStack(spacing: 5) {
                    Image(nsImage: PretendScreen.pdf).resizable().frame(width: 16, height: 16)
                    Text("Itinerary.pdf").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.primaryText)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
                .padding(.leading, 14)
                .padding(.bottom, 12)
                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
            }
        }
    }
}

/// The window's frame on the desk: its background, edge and shadow.
private struct WindowChrome: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(DeskWindowContent.background))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
    }
}

/// The Notes window flying up into the fold, or back out of it, as `DepositAnimator` flies the real
/// card: along `DepositFlight`'s curve, up from the window and then straight up onto its row's icon, its
/// frame shrinking to the icon's size and rounding into a circle. On the way it lets go of its contents
/// and takes on Tuck blue, so it arrives as the dot that opens out into the row. Out of the row, the same
/// happens in reverse.
private struct FlyingWindow: View, Animatable {
    var progress: CGFloat
    let outbound: Bool
    let path: DepositFlight
    let attached: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        // 0 at the window's place, 1 at the row, whichever way it's going.
        let t = outbound ? progress : 1 - progress
        let start = TourLayout.window.size
        let end = path.endSize
        let width = start.width + (end - start.width) * t
        let height = start.height + (end - start.height) * t
        // Its corners round off until, a little past halfway, it's a capsule, then a circle.
        let shorter = min(start.width, start.height)
        let capsule: CGFloat = 0.55
        let radius = ramp(t, [(0, 9), (capsule, max(9, (shorter + (end - shorter) * capsule) / 2)), (1, end / 2)])
        // The same timings as the real card: contents go early, the blue comes late.
        let warm = ramp(t, [(0, 0), (0.45, 0), (0.85, 1)])
        let contents = ramp(t, [(0, 1), (0.3, 1), (0.6, 0)])
        let contentScale = 1 + (end / max(start.width, start.height) - 1) * t
        let shape = RoundedRectangle(cornerRadius: min(radius, min(width, height) / 2), style: .circular)
        ZStack {
            shape.fill(DeskWindowContent.background)
            shape.fill(Theme.accent).opacity(warm)
            DeskWindowContent(attached: attached)
                .frame(width: start.width, height: start.height)
                .scaleEffect(contentScale)
                .opacity(contents)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.12 * (1 - warm))))
        .shadow(color: .black.opacity(0.2 * (1 - warm)), radius: 10, y: 4)
        .position(path.point(at: t).deskFlipped)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
