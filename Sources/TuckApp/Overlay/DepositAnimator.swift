import AppKit
import TuckCore

/// A colour as the person's Light or Dark setting draws it: the card is paper, like the open fold.
private func appearanceCGColor(_ color: NSColor) -> CGColor {
    var result: CGColor!
    NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
    return result
}

/// The upward half of tucking a window: a stand-in card (the app's icon and the window's title; no
/// window pixels, so no Screen Recording permission) rises from where the window was into Tuck. On the
/// way it shrinks, lets go of its icon and title, and becomes a blue dot. With the window's row showing
/// in the open panel it comes down on the row's icon, opens out across the row, and clears to show the
/// row drawn underneath. Otherwise it lands in the dip of Tuck's mark and merges into it, and the count
/// beside the mark goes up.
///
/// The window itself is moved off screen, with no system animation, only once its card is drawn over
/// its spot (`covered`), so the window is simply gone as the card takes its place and the only motion
/// seen is the card going up into Tuck (see `AccessibilityParkingService`). Coming back, `flyOut` runs
/// the same path the other way: the card leaves Tuck, lands where the window will be, and the window is
/// put back under it.
///
/// Each flight is a short-lived, click-through panel that is closed when it lands; nothing runs
/// between tucks. With Reduce Motion on, there is no flight, only the count changing.
final class DepositAnimator {
    /// Most windows shown flying at once; the rest of a large set lands with them.
    private static let maximumFlights = 6
    private static let stagger: TimeInterval = 0.035
    /// How long a card is given to reach the screen before its window goes: a frame or so, so the card
    /// is over the spot first and the spot is never seen empty.
    private static let coverDelay: TimeInterval = 0.025
    /// How far through a flight the card has reached the mark, all but the last point or so of its eased
    /// curve: it merges into the mark from here, and the count takes in what arrived as it does.
    private static let arrival = 0.85
    /// Landing in a row: how long the dot takes to open out across it, how long its colour then rests
    /// over the row while the row is drawn underneath, and how long the colour takes to clear.
    private static let opening: TimeInterval = 0.12
    private static let rest: TimeInterval = 0.02
    private static let clearing: TimeInterval = 0.1

    /// Settings → Notch → Show in screenshots and recordings, off: flights are left out as well.
    var isHiddenFromCapture = false

    /// Flies each window's card to where `target` lands it. `covered` is called with the windows whose
    /// cards are now on screen over them, `arrived` as a card fills its row, and `landed` once every card
    /// is in, with whether any landed in the mark rather than a row.
    func fly(_ windows: [ParkedWindow], target: (ParkedWindow) -> DepositLanding?,
             covered: @escaping (Set<UUID>) -> Void,
             arrived: @escaping (UUID) -> Void, landed: @escaping (_ inMark: Bool) -> Void) {
        let flights = windows.prefix(Self.maximumFlights).compactMap { window -> (DepositFlight, DepositLanding, ParkedWindow)? in
            target(window).map { landing in
                let flight = DepositFlight(window: window.originalFrame.cgRect, target: landing.point,
                                           endSize: landing.dot?.diameter ?? DepositFlight.defaultEndSize)
                return (flight, landing, window)
            }
        }
        // A row filling as its card arrives is the confirmation; otherwise the mark pulses as the count goes up.
        let inMark = flights.isEmpty || flights.contains { $0.1.row == nil }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, !flights.isEmpty else {
            covered(Set(windows.map(\.id)))
            return landed(inMark)
        }
        // Windows without a card of their own (more than are shown flying at once) go with the first card.
        let withoutCard = Set(windows.map(\.id)).subtracting(flights.map(\.2.id))
        var remaining = flights.count
        for (index, (flight, landing, window)) in flights.enumerated() {
            let going = index == 0 ? withoutCard.union([window.id]) : [window.id]
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * Self.stagger) { [weak self] in
                guard let self else { return covered(going) }
                self.launch(flight, landing: landing, app: window.app, title: window.displayTitle,
                            covered: { covered(going) }) {
                    if landing.row != nil { arrived(window.id) }
                    remaining -= 1
                    if remaining == 0 { landed(inMark) }
                }
            }
        }
    }

    private func launch(_ flight: DepositFlight, landing: DepositLanding, app: AppIdentity, title: String,
                        covered: @escaping () -> Void, landed: @escaping () -> Void) {
        // Whole points, so the card's coordinates inside the panel are exactly the screen's and it lands
        // on the dot's own pixels.
        var area = flight.startCard.union(flight.endCard)
        if let row = landing.row { area = area.union(row.frame) }
        area = area.insetBy(dx: -40, dy: -40).integral
        let (panel, view, scale) = makePanel(area, overSurface: landing.dot != nil)
        func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - area.minX, y: point.y - area.minY) }

        let start = flight.startCard.size
        let end = flight.endSize
        let (card, content) = Self.card(size: start, app: app, title: title, scale: scale)
        card.position = local(CGPoint(x: flight.startCard.midX, y: flight.startCard.midY))
        view.layer?.addSublayer(card)
        panel.orderFrontRegardless()

        let path = CGMutablePath()
        path.move(to: card.position)
        path.addCurve(to: local(flight.target), control1: local(flight.control1), control2: local(flight.control2))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        // The card's own size shrinks, rather than a scale, so it ends a true circle of the dot's size with
        // an unscaled ring. Its bounds shrink about their centre, which keeps what is inside it centred.
        let shrink = CABasicAnimation(keyPath: "bounds")
        shrink.fromValue = NSValue(rect: card.bounds)
        shrink.toValue = NSValue(rect: CGRect(x: (start.width - end) / 2, y: (start.height - end) / 2, width: end, height: end))
        // A card's corners round off until, halfway, it is a capsule (half its shorter side, which shrinks
        // as steadily as the bounds do), so it closes in on the dot as a circle.
        let shorter = min(start.width, start.height)
        let capsule: CGFloat = 0.55
        let round = Self.keyframes("cornerRadius",
                                   [card.cornerRadius, max(card.cornerRadius, (shorter + (end - shorter) * capsule) / 2), end / 2],
                                   at: [0, NSNumber(value: Double(capsule)), 1])
        var animations: [CAAnimation] = [move, shrink, round,
                                         Self.keyframes("borderWidth", [card.borderWidth, card.borderWidth, 0],
                                                        at: [0, 0.45, 0.85])]
        // Landing on a dot, the card becomes a copy of it and stays visible until it merges; without a
        // dot it simply fades as it slips under the surface.
        if let dot = landing.dot {
            animations += [
                Self.keyframes("backgroundColor", [card.backgroundColor, card.backgroundColor, dot.fill], at: [0, 0.45, 0.85]),
                Self.keyframes("borderColor", [card.borderColor, card.borderColor, dot.fill], at: [0, 0.45, 0.85]),
                Self.keyframes("shadowOpacity", [card.shadowOpacity, card.shadowOpacity, 0], at: [0, 0.45, 0.85])
            ]
        } else {
            animations.append(Self.keyframes("opacity", [0.96, 0.96, 0], at: [0, 0.78, 1]))
        }
        // A quick, continuous ease: decisive at takeoff, then soft as the card settles into its target.
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
        // The icon and title let go early, while the card is still large enough to read them leaving,
        // shrinking with it.
        let contentShrink = CABasicAnimation(keyPath: "transform.scale")
        contentShrink.fromValue = 1
        contentShrink.toValue = end / max(start.width, start.height)
        let letGo = Self.keyframes("opacity", [1, 1, 0], at: [0, 0.3, 0.6])

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            panel.orderOut(nil)
            panel.close()
        }
        if let row = landing.row, let dot = landing.dot {
            // Reaching the row's icon, the dot opens out to the row's shape: added on top of the flight's
            // last stretch, which only creeps the final point or so, so it never stops on the icon. Its
            // blue holds, then settles to the row's faint tint; it rests while the row is drawn
            // underneath, then clears to show it.
            let frame = CGRect(origin: local(row.frame.origin), size: row.frame.size)
            let target = local(flight.target)
            let reached = DepositFlight.duration * Self.arrival
            let opening = CAAnimationGroup()
            opening.animations = [
                Self.change("position", from: NSValue(point: .zero),
                            to: NSValue(point: CGPoint(x: frame.midX - target.x, y: frame.midY - target.y))),
                Self.change("bounds.size", from: NSValue(size: .zero),
                            to: NSValue(size: CGSize(width: frame.width - end, height: frame.height - end))),
                Self.change("cornerRadius", from: 0, to: row.cornerRadius - end / 2)
            ]
            opening.animations?.forEach { ($0 as? CAPropertyAnimation)?.isAdditive = true }
            opening.beginTime = reached
            opening.duration = Self.opening
            opening.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            opening.fillMode = .forwards
            let settle = Self.keyframes("backgroundColor", [dot.fill, dot.fill, row.tint], at: [0, 0.45, 1])
            settle.beginTime = reached
            settle.duration = Self.opening
            settle.fillMode = .forwards
            let clear = Self.change("opacity", from: 1, to: 0)
            clear.beginTime = reached + Self.opening + Self.rest
            clear.duration = Self.clearing
            clear.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clear.fillMode = .forwards
            let whole = CAAnimationGroup()
            whole.animations = [Self.flight(animations, timing: timing), opening, settle, clear]
            whole.duration = clear.beginTime + clear.duration
            whole.fillMode = .forwards
            whole.isRemovedOnCompletion = false
            card.add(whole, forKey: "deposit")
        } else {
            card.add(Self.flight(animations, timing: timing), forKey: "deposit")
        }
        if landing.dot != nil, landing.row == nil {
            // It merges into the mark only once it is the dot's size: this fade runs on the clock, not
            // on the flight's curve, whose last stretch only creeps the final few points.
            let merge = Self.keyframes("opacity", [0.96, 0.96, 0], at: [0, NSNumber(value: Self.arrival), 1])
            card.add(Self.flight([merge], timing: CAMediaTimingFunction(name: .linear)), forKey: "merge")
        }
        content.add(Self.flight([contentShrink, letGo], timing: timing), forKey: "deposit")
        CATransaction.commit()
        // The window goes once the card is on screen over its spot.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coverDelay, execute: covered)
        // A row counts as arrived once the colour covers it, so it is drawn under the colour, not beside it.
        let arrival = DepositFlight.duration * Self.arrival + (landing.row != nil ? Self.opening : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + arrival, execute: landed)
    }

    /// The way back for a window parked off screen: its card sets off from its row or the mark as a blue
    /// dot, grows back into the window's card along the deposit's path run backwards,
    /// and lands where the window will be (`frame`). `landed` is called as it lands, for the window to be
    /// put back under it, and the card then clears to show the window. Without a place to set off from,
    /// or with Reduce Motion on, the window simply comes back.
    func flyOut(_ window: ParkedWindow, to frame: CGRect, from landing: DepositLanding?, landed: @escaping () -> Void) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let landing else { return landed() }
        let flight = DepositFlight(window: frame, target: landing.point,
                                   endSize: landing.dot?.diameter ?? DepositFlight.defaultEndSize)
        let area = flight.startCard.union(flight.endCard).insetBy(dx: -40, dy: -40).integral
        let (panel, view, scale) = makePanel(area, overSurface: landing.dot != nil)
        func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - area.minX, y: point.y - area.minY) }

        let size = flight.startCard.size
        let dotSize = flight.endSize
        let (card, content) = Self.card(size: size, app: window.app, title: window.displayTitle, scale: scale)
        let home = local(CGPoint(x: flight.startCard.midX, y: flight.startCard.midY))
        card.position = home
        view.layer?.addSublayer(card)

        // The deposit's curve backwards: down out of the target, across beneath the menu bar, and down
        // onto the window's spot.
        let path = CGMutablePath()
        path.move(to: local(flight.target))
        path.addCurve(to: home, control1: local(flight.control2), control2: local(flight.control1))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        let grow = CABasicAnimation(keyPath: "bounds")
        grow.fromValue = NSValue(rect: CGRect(x: (size.width - dotSize) / 2, y: (size.height - dotSize) / 2,
                                              width: dotSize, height: dotSize))
        grow.toValue = NSValue(rect: card.bounds)
        // A capsule until a little before halfway, then the card's own corners, as the deposit's in reverse.
        let shorter = min(size.width, size.height)
        let capsule: CGFloat = 0.55
        let round = Self.keyframes("cornerRadius",
                                   [dotSize / 2, max(card.cornerRadius, (shorter + (dotSize - shorter) * capsule) / 2), card.cornerRadius],
                                   at: [0, NSNumber(value: Double(1 - capsule)), 1])
        let times: [NSNumber] = [0, 0.15, 0.55, 1]
        var animations: [CAAnimation] = [move, grow, round,
                                         Self.keyframes("borderWidth", [0, 0, card.borderWidth, card.borderWidth], at: times)]
        if let dot = landing.dot {
            // It leaves as the dot, then takes on the card's own colours.
            let edge = dot.fill
            animations += [
                Self.keyframes("backgroundColor", [dot.fill, dot.fill, card.backgroundColor, card.backgroundColor], at: times),
                Self.keyframes("borderColor", [edge, edge, card.borderColor, card.borderColor], at: times),
                Self.keyframes("shadowOpacity", [0, 0, card.shadowOpacity, card.shadowOpacity], at: times)
            ]
        } else {
            animations.append(Self.keyframes("opacity", [0, 0.96, 0.96], at: [0, 0.22, 1]))
        }
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
        let contentGrow = CABasicAnimation(keyPath: "transform.scale")
        contentGrow.fromValue = dotSize / max(size.width, size.height)
        contentGrow.toValue = 1
        let appear = Self.keyframes("opacity", [0, 0, 1], at: [0, 0.4, 0.7])
        card.add(Self.flight(animations, timing: timing), forKey: "return")
        content.add(Self.flight([contentGrow, appear], timing: timing), forKey: "return")
        // Ordered in only now, with the flight already on its layers, so the card is never drawn at rest
        // where it will land before it sets off.
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + DepositFlight.duration) {
            landed()
            // The window is back under the card; the card clears to show it, from a frame later, once the
            // window is drawn there.
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                panel.orderOut(nil)
                panel.close()
            }
            let clear = Self.change("opacity", from: card.presentation()?.opacity ?? 1, to: 0)
            clear.beginTime = CACurrentMediaTime() + Self.coverDelay
            clear.duration = Self.clearing
            clear.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clear.fillMode = .both
            clear.isRemovedOnCompletion = false
            card.add(clear, forKey: "clear")
            CATransaction.commit()
        }
    }

    /// A short-lived, click-through panel for one flight, its frame in whole points. Above ordinary
    /// windows: setting off from or landing on a dot or a row, it passes just over Tuck's surface so that
    /// is seen, even in the open panel; otherwise just under it, so it slips into or out of the notch.
    private func makePanel(_ area: CGRect, overSurface: Bool) -> (panel: NSPanel, view: NSView, scale: CGFloat) {
        let panel = NSPanel(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: OverlayPanel.surfaceLevel.rawValue + (overSurface ? 1 : -1))
        panel.appearance = nil
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        if isHiddenFromCapture { panel.sharingType = .none }

        let view = NSView(frame: CGRect(origin: .zero, size: area.size))
        view.wantsLayer = true
        panel.contentView = view
        let scale = NSScreen.screens.first { $0.frame.contains(CGPoint(x: area.midX, y: area.midY)) }?.backingScaleFactor ?? 2
        return (panel, view, scale)
    }

    /// The animations of one layer in a flight, sharing its duration and curve and holding the last
    /// frame until the panel closes.
    private static func flight(_ animations: [CAAnimation], timing: CAMediaTimingFunction) -> CAAnimationGroup {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = DepositFlight.duration
        group.timingFunction = timing
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        return group
    }

    private static func change(_ keyPath: String, from: Any, to: Any) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        return animation
    }

    private static func keyframes(_ keyPath: String, _ values: [Any?], at times: [NSNumber]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values.compactMap { $0 }
        animation.keyTimes = times
        return animation
    }

    /// A small, quiet stand-in for the window: a paper card with a hairline edge, the app's icon and the
    /// title, which sit in their own layer so they can fade on their own.
    private static func card(size: CGSize, app: AppIdentity, title: String, scale: CGFloat) -> (card: CALayer, content: CALayer) {
        let card = CALayer()
        card.bounds = CGRect(origin: .zero, size: size)
        card.cornerRadius = min(12, size.height / 6)
        card.backgroundColor = appearanceCGColor(Theme.raisedNSColor)
        card.borderColor = appearanceCGColor(Theme.hairlineNSColor)
        card.borderWidth = 1
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.22
        card.shadowRadius = 10
        card.shadowOffset = CGSize(width: 0, height: -3)
        let content = CALayer()
        content.frame = card.bounds
        card.addSublayer(content)

        let iconSize = min(40, size.height * 0.4)
        let icon = CALayer()
        icon.contents = appIcon(app)
        icon.contentsGravity = .resizeAspect
        icon.contentsScale = scale
        let showsTitle = size.height >= 70 && !title.isEmpty
        let iconY = showsTitle ? size.height / 2 + 8 : size.height / 2
        icon.frame = CGRect(x: (size.width - iconSize) / 2, y: iconY - iconSize / 2, width: iconSize, height: iconSize)
        content.addSublayer(icon)

        if showsTitle {
            let label = CATextLayer()
            label.string = title
            label.font = NSFont.preferredFont(forTextStyle: .title3)
            label.fontSize = label.font?.pointSize ?? NSFont.systemFontSize
            label.foregroundColor = appearanceCGColor(.labelColor)
            label.alignmentMode = .center
            label.truncationMode = .end
            label.contentsScale = scale
            label.frame = CGRect(x: 10, y: iconY - iconSize / 2 - 22, width: size.width - 20, height: 15)
            content.addSublayer(label)
        }
        return (card, content)
    }

    private static func appIcon(_ app: AppIdentity) -> CGImage? {
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID).map { _ in
            AppIcons.icon(for: app.bundleID)
        } ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        var rect = CGRect(x: 0, y: 0, width: 80, height: 80)
        return image?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// Where a tucked window's card lands, in global coordinates, and the dot it becomes there; none when
/// it slips into the middle of the surface instead.
struct DepositLanding {
    let point: CGPoint
    let dot: Dot?
    /// The window's row in the open panel, when the card lands there: it comes down on the row's icon as
    /// `dot`, then opens out into the row.
    var row: Row?

    /// A row as the panel draws it: its frame, its highlight's corners, and the faint tint it settles to.
    struct Row {
        let frame: CGRect
        let cornerRadius: CGFloat
        let tint: CGColor
    }

    /// The blue dot the card closes in to: the mark's line width in the dip, or a row's icon.
    struct Dot {
        let diameter: CGFloat
        let fill: CGColor
    }
}
