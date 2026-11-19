import AppKit
import SwiftUI
import TuckCore

private func appearanceCGColor(_ color: NSColor, for appearance: NSAppearance) -> CGColor {
    var result: CGColor!
    appearance.performAsCurrentDrawingAppearance { result = color.cgColor }
    return result
}

/// The always-on surface. Closed, it is a handful of Core Animation layers (shape, mark, dot and Tuck
/// button) with no timers and no SwiftUI; empty, on a notched display, it leaves the notch as it is. A
/// bubble holds the mark alone, which gives way to the Tuck button while it is pointed at. Opening morphs
/// the shape into the fold and attaches the SwiftUI panel, which is released again on close. Swiped up,
/// the closed surface tucks itself into the notch. It is also the drop target and handles swipes, clicks
/// and hover directly. Pointing at it never opens it: a click or a swipe down does.
final class SurfaceView: NSView {
    let anchor: ScreenAnchor
    private unowned let model: TuckModel

    /// Asks the controller to resize the window before an expand, or after a collapse finishes.
    var onNeedsWindowFrame: (() -> Void)?
    /// Asks the controller for window room for the drop invitation (true) or to give it back (false).
    var onPromptRoom: ((Bool) -> Void)?

    private let shapeLayer = CAShapeLayer()
    /// Black over the hardware notch, always. It can't be seen (the camera housing covers those
    /// pixels), but it keeps the notch part of the window's shape: the window is otherwise transparent
    /// there while the surface rests in the notch, and macOS sends clicks and scrolls on transparent
    /// pixels straight through to the menu bar, so Tuck could never be hovered, clicked or swiped back.
    private let notchHitLayer = CALayer()
    /// The left wing shows Tuck's mark, the screen's top edge dipping round the notch: faint at rest, with
    /// a short card in the dip while Tuck holds something, as the Dock's Trash shows empty or full, and lit
    /// in Tuck blue while the pointer is over the closed surface. Empty, a notched display shows no wings
    /// at all; a bubble always shows the mark, alone in its middle, until the Tuck button takes its place.
    private let markLayer = CALayer()
    /// The whole line, faint: all the mark shows at rest.
    private let markBaseLayer = CAShapeLayer()
    /// The same line in Tuck blue, which comes on while the pointer is over the closed surface.
    private let markLitLayer = CAShapeLayer()
    /// The card that drops into the dip as Tuck starts holding something, and lifts out as it empties.
    private let markCardLayer = CAShapeLayer()
    /// Whether the mark last showed its card, so only a change animates.
    private var markHolds: Bool?
    /// Set when Tuck has just been given something while empty: the card drops in as what was deposited
    /// lands (`landDeposit`), or shortly, if nothing is on its way.
    private var pendingCard: DispatchWorkItem?
    /// At rest a small quiet dot on the right wing, balancing the mark. Whenever the Tuck button shows it
    /// gives way to the button. A bubble, which holds one symbol, shows none.
    private let restingDotLayer = CALayer()
    /// The Tuck button, which appears in the dot's place while the pointer is over the closed surface (in
    /// a bubble, the mark's): an arrow up into the notch, stroked in the logo's own line and Tuck blue, so
    /// it sits with the lit mark as its pair. A click tucks the window in front without opening the panel.
    private let tuckArrowLayer = CAShapeLayer()
    /// The button's target, in view coordinates; set by layout. Around a notch it is the right wing; in a
    /// bubble the middle, a little wider than the arrow, so the bubble's ends still open the fold.
    private var tuckButtonRect: CGRect = .zero
    /// A press that began on the Tuck button.
    private var isPressingTuck = false
    /// Whether the closed surface was last laid out resting in the notch, so a change animates.
    private var shownRestsInNotch: Bool?
    private let promptRimLayer = CAShapeLayer()
    /// Around a notch, fades the rim out up the shoulders, so none of it runs along the screen's top edge.
    private let promptRimFade = CAGradientLayer()
    private let promptGlyphLayer = CALayer()
    private let promptLabelLayer = CATextLayer()
    private var promptText = ""
    private var promptTextSize: CGSize = .zero
    /// Holds the panel, clipped to the surface's outline so the shape reveals it as it opens.
    private let panelClip = PanelClipView()
    private let panelMask = CAShapeLayer()
    private var host: PanelHostingView?
    /// Set while the panel is being built out of sight before the surface opens.
    private var preparingToken: UUID?
    private var lastLayoutWidth: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    private let swipe = SwipeGestureTracker()
    private var lastPlusOneToken: UUID?
    private lazy var lastRefusals = model.refusals
    /// While a drop on the closed surface draws into the mark: the mark's card and swell wait for it.
    private var compressionEnds: CFTimeInterval = 0

    private(set) var isShowingExpanded = false
    private(set) var isShowingTucked = false
    private(set) var panelHeight: CGFloat = 320
    private var isHovering = false
    /// Pointing at an empty Tuck shows "Drop into Tuck" under the notch (a bubble offers its Tuck button
    /// instead).
    private var isShowingCue = false
    /// How far a swipe in progress has pulled the collapsed surface (see `SwipeGestureTracker.pull`).
    private var gesturePull: CGFloat = 0
    /// Who the trackpad gesture in progress belongs to: the surface, the panel's scrolling list or the
    /// shallow fold's strip.
    private var gestureRouting = ScrollGestureRouting()
    /// The first events of a gesture over the strip, held back until it shows which way it goes.
    private var heldScrollEvents: [NSEvent] = []
    /// Held events are being handed on to the strip, past the overlay's scroll monitor.
    private var isReplayingScroll = false
    /// Keeps the shape drawn while it shrinks into the notch; it disappears once the morph lands.
    private var isShrinkingIntoNotch = false
    /// Mouse held down on the collapsed surface: it gives a little until released.
    private var isPressed = false
    /// Keeps the mark and dot hidden while a closing panel is still folding away.
    private var holdsCollapsedContent = false
    /// Drop invitation, or the empty cue: nil when there is neither, otherwise 0 (the cue, or a drag just
    /// inside the approach range) up to `DropApproach.levels` (a drag over the drop target).
    private(set) var promptLevel: Int?
    /// The level the drag watcher last asked for.
    private var watcherLevel: Int?
    /// The system is delivering the drag to this view and it is over the drop target: always shown as
    /// the accepted state, whatever the watcher last measured.
    private var isAcceptingDrop = false

    init(anchor: ScreenAnchor, model: TuckModel) {
        self.anchor = anchor
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        configureLayers()
        panelClip.wantsLayer = true
        panelClip.frame = bounds
        panelClip.autoresizingMask = [.width, .height]
        panelClip.layer?.mask = panelMask
        addSubview(panelClip)
        registerForDraggedTypes(DropReader.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var metrics: SurfaceMetrics {
        SurfaceMetrics(anchor: anchor, isTuckedAway: restsInNotch && promptLevel == nil, cards: model.cardLayout)
    }

    /// Anything for the closed surface to show: tucked windows or held items.
    private var holdsAnything: Bool { model.library.totalItemCount > 0 }

    /// The closed surface is the bare notch: swiped away, or, on a notched display, empty.
    private var restsInNotch: Bool { isShowingTucked || (anchor.kind == .notch && !holdsAnything) }

    /// A droppable drag is on its way or over the surface.
    private var isDragging: Bool { watcherLevel != nil || isAcceptingDrop }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The surface is black, closed or open, notch or bubble, so it continues the hardware notch:
    /// everything drawn on it, and the open panel inside it, resolves in the dark appearance whatever the
    /// Light or Dark setting.
    private var contentAppearance: NSAppearance { Theme.notchAppearance }

    // MARK: Layers

    private func configureLayers() {
        guard let root = layer else { return }
        // A tucked bubble or drawn notch draws nothing either (no hardware notch hides the spot), so it
        // gets an all but invisible spot to catch the pointer.
        let hidden = anchor.kind == .notch && !anchor.isSimulated
        notchHitLayer.backgroundColor = hidden ? NSColor.black.cgColor : NSColor(white: 0, alpha: 0.012).cgColor
        root.addSublayer(notchHitLayer)
        shapeLayer.fillColor = NSColor.black.cgColor
        shapeLayer.lineWidth = 0.75
        shapeLayer.shadowColor = NSColor.black.cgColor
        shapeLayer.shadowRadius = 6
        shapeLayer.shadowOffset = CGSize(width: 0, height: 2)
        root.addSublayer(shapeLayer)

        for line in [markBaseLayer, markLitLayer, markCardLayer] {
            line.fillColor = nil
            line.lineCap = .round
            line.lineJoin = .round
            markLayer.addSublayer(line)
        }
        markBaseLayer.opacity = Float(TuckLogo.restingOpacity)
        markLitLayer.opacity = 0
        markCardLayer.opacity = 0
        root.addSublayer(markLayer)

        restingDotLayer.opacity = 0
        root.addSublayer(restingDotLayer)
        tuckArrowLayer.fillColor = nil
        tuckArrowLayer.lineCap = .round
        tuckArrowLayer.lineJoin = .round
        tuckArrowLayer.opacity = 0
        root.addSublayer(tuckArrowLayer)

        promptRimLayer.fillColor = nil
        promptRimLayer.lineWidth = 1.5
        promptRimLayer.opacity = 0
        // Over the open panel as well, which is a subview's layer above these.
        promptRimLayer.zPosition = 1
        if anchor.kind == .notch {
            promptRimFade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor]
            promptRimLayer.mask = promptRimFade
        }
        root.insertSublayer(promptRimLayer, above: shapeLayer)

        promptGlyphLayer.contentsGravity = .resizeAspect
        promptGlyphLayer.opacity = 0
        root.addSublayer(promptGlyphLayer)

        promptLabelLayer.font = Self.promptFont
        promptLabelLayer.fontSize = Self.promptFont.pointSize
        promptLabelLayer.alignmentMode = .left
        promptLabelLayer.opacity = 0
        root.addSublayer(promptLabelLayer)
        applySurfaceFill(animated: false)
        applyContentColors()
    }

    /// Colours of what sits on the closed surface: the mark, the dot and the Tuck button, the drop words
    /// and glyph. The faint line is the label colour; the lit line, its card and the button Tuck blue.
    private func applyContentColors() {
        let appearance = contentAppearance
        let accent = appearanceCGColor(Theme.accentNSColor, for: appearance)
        markBaseLayer.strokeColor = appearanceCGColor(.labelColor, for: appearance)
        markLitLayer.strokeColor = accent
        markCardLayer.strokeColor = accent
        tuckArrowLayer.strokeColor = accent
        restingDotLayer.backgroundColor = appearanceCGColor(.tertiaryLabelColor, for: appearance)
        applyPromptContent()
    }

    /// The one drop target's words and glyph: what the drag carries ("Drop link into Tuck"), or, with no
    /// drag, the empty cue.
    private func applyPromptContent() {
        let appearance = contentAppearance
        let dragging = isDragging
        let text = dragging ? model.dragKind.label : DropKind.invitation
        if text != promptText {
            promptText = text
            promptLabelLayer.string = text
            let size = (text as NSString).size(withAttributes: [.font: Self.promptFont])
            promptTextSize = CGSize(width: ceil(size.width), height: ceil(size.height))
        }
        promptGlyphLayer.contents = Self.glyph(dragging ? Self.dropSymbol(model.dragKind) : "tray.and.arrow.down",
                                               pointSize: 14, color: dragging ? Theme.accentNSColor : .secondaryLabelColor,
                                               appearance: appearance)
        promptLabelLayer.foregroundColor = appearanceCGColor(dragging ? .labelColor : .secondaryLabelColor, for: appearance)
    }

    static func dropSymbol(_ kind: DropKind) -> String {
        switch kind {
        case .file: "doc.fill"
        case .link: "link"
        case .text: "text.quote"
        }
    }

    /// Black, closed and open, continuing the hardware notch in the Light or Dark setting alike; open, the
    /// fold gains a soft shadow as the outline morphs. The camera housing stays black inside it.
    private func applySurfaceFill(animated: Bool) {
        let open = isShowingExpanded
        let appearance = contentAppearance
        let fill = NSColor.black.cgColor
        // A bubble keeps a hairline edge: against a dark menu bar while closed, against the page while open.
        let stroke: CGColor? = anchor.kind == .bubble
            ? appearanceCGColor(open ? Theme.hairlineNSColor : .separatorColor, for: appearance) : nil
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(reduceMotion ? 0.16 : 0.26)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        shapeLayer.fillColor = fill
        shapeLayer.strokeColor = stroke
        shapeLayer.shadowOpacity = open ? 0.18 : (anchor.kind == .bubble ? 0.28 : 0)
        shapeLayer.shadowRadius = open ? 14 : 6
        shapeLayer.shadowOffset = CGSize(width: 0, height: open ? 5 : 2)
        CATransaction.commit()
    }

    /// Applies the colours for the current appearance and state.
    private func updateSurfaceAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applySurfaceFill(animated: false)
        applyContentColors()
        CATransaction.commit()
        needsLayout = true
        if promptLevel != nil { applyPromptAppearance(animated: false) }
    }

    private static let promptFont: NSFont = {
        let body = NSFont.preferredFont(forTextStyle: .body)
        return NSFont.systemFont(ofSize: body.pointSize, weight: .semibold)
    }()
    private static let promptGlyphSize: CGFloat = 16
    private static let promptGap: CGFloat = 5
    private var promptContentWidth: CGFloat { Self.promptGlyphSize + Self.promptGap + promptTextSize.width }

    private struct GlyphKey: Hashable {
        let name: String
        let pointSize: CGFloat
        let weight: NSFont.Weight
        let color: NSColor
        let appearance: NSAppearance.Name
    }
    /// Glyphs already drawn. The closed content is recoloured at every model change, which drew the same
    /// few symbols into new images each time; cleared when the appearance changes.
    private static var glyphs: [GlyphKey: CGImage] = [:]

    /// An SF Symbol drawn in a semantic colour, resolved for the appearance it sits on.
    private static func glyph(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor,
                              appearance: NSAppearance) -> CGImage? {
        let key = GlyphKey(name: name, pointSize: pointSize, weight: weight, color: color, appearance: appearance.name)
        if let cached = glyphs[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        let size = symbol.size
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            appearance.performAsCurrentDrawingAppearance {
                color.set()
                rect.fill(using: .sourceAtop)
            }
            return true
        }
        var proposed = CGRect(origin: .zero, size: CGSize(width: size.width * 2, height: size.height * 2))
        let drawn = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        glyphs[key] = drawn
        return drawn
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in [markBaseLayer, markLitLayer, markCardLayer, tuckArrowLayer, promptGlyphLayer, promptLabelLayer] {
            layer.contentsScale = scale
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        Self.glyphs.removeAll()
        updateSurfaceAppearance()
    }

    // MARK: Geometry

    private var surfaceRect: CGRect { surfaceRect(includingTransient: true) }

    /// The outline's rect. Without the transient parts (hover, press, the drop invitation) it is where
    /// the closed content sits, so those never nudge the mark or the dot.
    private func surfaceRect(includingTransient: Bool) -> CGRect {
        let metrics = metrics
        var size: CGSize
        if isShowingExpanded {
            size = CGSize(width: metrics.expandedWidth, height: panelHeight)
        } else if includingTransient, let growth = promptGrowth {
            size = CGSize(width: metrics.restingSize.width + growth.width * 2, height: metrics.restingSize.height + growth.height)
        } else {
            size = metrics.collapsedSize
            // A swipe in progress pulls the surface along with the fingers: down stretches it towards the
            // panel, or slides the wings back out of the notch; up draws the wings in.
            let wingSpan = metrics.restingSize.width - metrics.tuckedSize.width
            if gesturePull > 0, swipeStage == .tucked {
                size.width += wingSpan * 0.6 * gesturePull
            } else if gesturePull > 0 {
                size.width += 10 * gesturePull
                size.height += (metrics.isNotch ? 6 : 3) * gesturePull
            } else if gesturePull < 0, !restsInNotch {
                size.width -= wingSpan * 0.6 * -gesturePull
            }
            if isHovering && includingTransient {
                size.width += 8
                if metrics.isNotch { size.height += 2 }
            }
            if isPressed && includingTransient {
                size.width -= 6
                size.height -= metrics.isNotch ? 2 : 1
            }
        }
        return CGRect(x: (bounds.width - size.width) / 2, y: metrics.topInset,
                      width: size.width, height: size.height)
    }

    /// How far the closed surface pops out for the drop target or the empty cue: as soon as a drag starts,
    /// just enough for its words (a band under the notch, or a bubble wide enough for them), then a
    /// little more as the pointer nears. Sideways growth per side, downward growth in total.
    private var promptGrowth: CGSize? {
        guard let level = promptLevel else { return nil }
        let closeness = CGFloat(level) / CGFloat(DropApproach.levels)
        if metrics.isNotch {
            return CGSize(width: 4 + 6 * closeness, height: 24 + 4 * closeness)
        }
        let fit = max(promptContentWidth + 24 - metrics.restingSize.width, 0) / 2
        return CGSize(width: fit + 2 + 6 * closeness, height: 1 + 3 * closeness)
    }

    /// Extra window room the largest invitation needs.
    static let promptSlack = CGSize(width: 170, height: 36)

    private var panelContentRect: CGRect {
        let rect = surfaceRect
        let inset = metrics.isNotch ? SurfaceMetrics.shoulder : 0
        return CGRect(x: rect.minX + inset, y: rect.minY, width: metrics.panelWidth, height: panelHeight)
    }

    private func surfacePath(for rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        if anchor.kind == .notch {
            let s = SurfaceMetrics.shoulder
            let r = min(isShowingExpanded ? Theme.foldRadius : SurfaceMetrics.notchCornerRadius, rect.height - s,
                        (rect.width - 2 * s) / 2)
            // Shoulders are quarter circles, so the surface flows out of the top edge like the notch does.
            let k = s * 0.5523
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
        } else {
            let top = isShowingExpanded ? 18 : rect.height / 2
            let bottom = isShowingExpanded ? Theme.foldRadius : rect.height / 2
            path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + top), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottom), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
            path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }

    override func layout() {
        super.layout()
        // A width change moves every x-coordinate (the window stays centred on the notch), so a morph in
        // flight would continue in stale coordinates: land it, then lay out in the new ones.
        if bounds.width != lastLayoutWidth {
            lastLayoutWidth = bounds.width
            finishMorphs()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if anchor.kind == .notch {
            // Inside the physical cutout, clear of its rounded lower corners, so nothing drawn here can show.
            let notch = anchor.notchSize
            notchHitLayer.frame = CGRect(x: bounds.midX - notch.width / 2 + 6, y: 0,
                                         width: max(notch.width - 12, 0), height: max(notch.height - 3, 0))
        } else {
            let tucked = metrics.tuckedSize
            notchHitLayer.frame = CGRect(x: bounds.midX - tucked.width / 2, y: metrics.topInset,
                                         width: tucked.width, height: tucked.height)
        }
        panelMask.frame = panelClip.bounds
        if anchor.kind == .notch, bounds.height > 0 {
            // Clear where a shoulder meets the top edge, whole where it has turned down into the side.
            promptRimFade.frame = bounds
            promptRimFade.locations = [2, SurfaceMetrics.shoulder + 2].map { NSNumber(value: Double($0 / bounds.height)) }
        }
        setOutline(surfacePath(for: surfaceRect))
        layoutCollapsedContent()
        CATransaction.commit()
        applyVisibility(animated: false)
        host?.frame = panelContentRect
    }

    // MARK: Closed content

    /// Rebuilds the mark's colours and its card from the model. Cheap; runs only when the model changes.
    func refreshCollapsedContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyContentColors()
        CATransaction.commit()
        followHolds()
        followRestingForm()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.16)
        applyDropRim()
        CATransaction.commit()
        needsLayout = true
        pulseIfNeeded()
        shakeIfNeeded()
        announceSummaryIfChanged()
    }

    /// The mark's card follows the library: it lifts out at once as Tuck empties, but drops in only once
    /// what was deposited has landed (`landDeposit`), or shortly if nothing is on its way. The library
    /// changes as a window is tucked, before its card has flown up, and the mark's own card must not drop
    /// in under it.
    private func followHolds() {
        let holds = holdsAnything
        guard let shown = markHolds else {
            markHolds = holds
            return setMarkHolds(holds, animated: false)
        }
        guard holds != shown else {
            pendingCard?.cancel()
            pendingCard = nil
            return
        }
        guard holds else {
            pendingCard?.cancel()
            pendingCard = nil
            markHolds = false
            return setMarkHolds(false, animated: true)
        }
        guard pendingCard == nil else { return }
        let drop = DispatchWorkItem { [weak self] in self?.dropCardIfWaiting() }
        pendingCard = drop
        DispatchQueue.main.asyncAfter(deadline: .now() + DepositFlight.duration + 0.3, execute: drop)
    }

    /// Drops the mark's card in if it is waiting for something to land; false if it wasn't.
    @discardableResult
    private func dropCardIfWaiting() -> Bool {
        guard let drop = pendingCard else { return false }
        drop.cancel()
        pendingCard = nil
        guard markHolds == false, holdsAnything else { return false }
        markHolds = true
        setMarkHolds(true, animated: true)
        return true
    }

    /// The card drops into the dip from above with the mark's swell and settles, as Tuck starts holding
    /// something; as it empties the card lifts out. With Reduce Motion it fades instead. The line itself
    /// lights only while pointed at (`applyVisibility`). In a bubble pointed at, the card drops into the
    /// hidden mark and the Tuck button standing in its place swells instead.
    private func setMarkHolds(_ holds: Bool, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        markCardLayer.removeAllAnimations()
        markCardLayer.opacity = holds ? 1 : 0
        CATransaction.commit()
        guard animated else { return }
        func change(_ keyPath: String, from: Double, to: Double, duration: CFTimeInterval,
                    timing: CAMediaTimingFunctionName) -> CABasicAnimation {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: timing)
            return animation
        }
        if reduceMotion {
            markCardLayer.add(change("opacity", from: holds ? 0 : 1, to: holds ? 1 : 0, duration: 0.2, timing: .easeOut),
                              forKey: "light")
            return
        }
        let drop = Double(TuckLogo.cardDrop(side: markLayer.bounds.width))
        guard holds else {
            markCardLayer.add(change("opacity", from: 1, to: 0, duration: 0.2, timing: .easeIn), forKey: "light")
            markCardLayer.add(change("transform.translation.y", from: 0, to: -drop, duration: 0.2, timing: .easeIn),
                              forKey: "lift")
            return
        }
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1, 1.16, 1]
        pop.keyTimes = [0, 0.42, 1]
        pop.duration = 0.2
        landingLayer.add(pop, forKey: "pulse")
        // The card comes in over its first few points, then springs down into the dip and settles.
        markCardLayer.add(change("opacity", from: 0, to: 1, duration: 0.06, timing: .easeOut), forKey: "light")
        let fall = CASpringAnimation(keyPath: "transform.translation.y")
        fall.fromValue = -drop
        fall.toValue = 0
        fall.stiffness = 385
        fall.damping = 28
        fall.duration = fall.settlingDuration
        markCardLayer.add(fall, forKey: "drop")
    }

    /// The closed surface's wings come out of the notch as Tuck starts holding something, and go back in
    /// as it empties or is swiped away, morphing on from wherever a swipe left it. While the panel is open
    /// or a drop is invited, the change waits for them to end.
    private func followRestingForm() {
        let rests = restsInNotch
        guard let shown = shownRestsInNotch, shown != rests else {
            shownRestsInNotch = rests
            return
        }
        guard !isShowingExpanded, promptLevel == nil else { return }
        shownRestsInNotch = rests
        // Keep the surface visible throughout either direction of the morph: coming out it grows from
        // the notch instead of appearing only once its geometry is in place.
        isShrinkingIntoNotch = true
        animateShape(to: surfacePath(for: surfaceRect)) { [weak self] in
            guard let self else { return }
            self.isShrinkingIntoNotch = false
            if rests { self.applyVisibility(animated: true, duration: 0.08) }
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1))
        layoutCollapsedContent()
        CATransaction.commit()
        // Fade with the shape morph, so the surface disappears as it goes into the notch rather than
        // lingering after the motion has finished.
        applyVisibility(animated: true, duration: 0.3)
    }

    /// As the pointer arrives on the closed surface the mark greets it while its line lights
    /// (`applyVisibility`): the dip reaches down, as the panel would drop from it, springs back a little
    /// past rest and settles, with the card (while Tuck holds something) riding it a beat behind. Run once
    /// per arrival, and left to finish rather than restarted. Under Reduce Motion the line only lights. A
    /// bubble's mark is giving way to the Tuck button as the pointer arrives, so it greets only when the
    /// button doesn't come.
    private func greetMark() {
        guard !restsInNotch, !holdsCollapsedContent, !reduceMotion, !buttonTakesMarksPlace,
              markBaseLayer.animation(forKey: "greet") == nil else { return }
        let side = markLayer.bounds.width
        let reach = CAKeyframeAnimation(keyPath: "path")
        reach.values = TuckLogo.greetingReach.map { TuckLogo.linePath(side: side, reach: $0) }
        reach.keyTimes = TuckLogo.greetingKeyTimes.map { NSNumber(value: $0) }
        reach.duration = TuckLogo.greetingDuration
        reach.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
                                 CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeOut)]
        markBaseLayer.add(reach, forKey: "greet")
        markLitLayer.add(reach, forKey: "greet")
        let ride = CAKeyframeAnimation(keyPath: "transform.translation.y")
        ride.values = TuckLogo.greetingReach.map { $0 * TuckLogo.reachDrop(side: side) }
        ride.keyTimes = reach.keyTimes
        ride.duration = reach.duration
        ride.timingFunctions = reach.timingFunctions
        ride.isAdditive = true
        ride.beginTime = markCardLayer.convertTime(CACurrentMediaTime(), from: nil) + TuckLogo.greetingCardDelay
        markCardLayer.add(ride, forKey: "greet")
    }

    private func layoutCollapsedContent() {
        let metrics = metrics
        // The expanded outline is much wider than the closed wings. Keep the closed content anchored to
        // those wings while it fades out; using surfaceRect here sends it to the panel's far edges during
        // the opening morph, outside the visible notch.
        let rect = isShowingExpanded
            ? CGRect(x: (bounds.width - metrics.restingSize.width) / 2, y: metrics.topInset,
                     width: metrics.restingSize.width, height: metrics.restingSize.height)
            : surfaceRect(includingTransient: false)
        let promptRect = surfaceRect
        let mark = metrics.markSide
        let button = metrics.tuckButtonSide
        // Content stays centred on the resting height, so hover and a downward pull never move it.
        let midY = pixelAligned(rect.minY + metrics.height / 2)
        let markCenterX: CGFloat
        let buttonCenterX: CGFloat
        if metrics.isNotch {
            // Each wing runs from the shape's straight side to the notch, so content slides in with the
            // sides when the surface tucks away and stays put when hover grows it.
            let notchLeft = bounds.midX - anchor.notchSize.width / 2
            let notchRight = bounds.midX + anchor.notchSize.width / 2
            markCenterX = pixelAligned((rect.minX + SurfaceMetrics.shoulder + notchLeft) / 2)
            buttonCenterX = pixelAligned((rect.maxX - SurfaceMetrics.shoulder + notchRight) / 2)
        } else {
            // A bubble holds one symbol in its middle: the mark, or the Tuck button in its place, so the
            // one gives way to the other without either sliding.
            markCenterX = pixelAligned(rect.midX)
            buttonCenterX = markCenterX
        }
        markLayer.bounds = CGRect(x: 0, y: 0, width: mark, height: mark)
        markLayer.position = CGPoint(x: markCenterX, y: midY)
        if markBaseLayer.bounds.width != mark {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let line = TuckLogo.linePath(side: mark)
            for layer in [markBaseLayer, markLitLayer, markCardLayer] {
                layer.frame = CGRect(x: 0, y: 0, width: mark, height: mark)
                layer.path = layer === markCardLayer ? TuckLogo.cardPath(side: mark) : line
                layer.lineWidth = TuckLogo.lineWidth(side: mark)
            }
            CATransaction.commit()
        }
        // The resting dot, and the Tuck button's arrow in a square the mark's size, so the two strokes
        // match. Its whole wing is the target; in a bubble the arrow and 6 pt either side, leaving the
        // bubble's ends (`bubbleEndWidth`) to open the fold.
        let dot = SurfaceMetrics.restingDotSize
        restingDotLayer.bounds = CGRect(x: 0, y: 0, width: dot, height: dot)
        restingDotLayer.cornerRadius = dot / 2
        restingDotLayer.position = CGPoint(x: buttonCenterX, y: midY)
        tuckArrowLayer.bounds = CGRect(x: 0, y: 0, width: mark, height: mark)
        tuckArrowLayer.position = CGPoint(x: buttonCenterX, y: midY)
        if tuckArrowLayer.lineWidth != TuckLogo.lineWidth(side: mark) || tuckArrowLayer.path == nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tuckArrowLayer.path = TuckLogo.arrowPath(side: mark)
            tuckArrowLayer.lineWidth = TuckLogo.lineWidth(side: mark)
            CATransaction.commit()
        }
        let buttonWidth = metrics.isNotch ? metrics.wingWidth : button + 12
        tuckButtonRect = CGRect(x: buttonCenterX - buttonWidth / 2, y: rect.minY, width: buttonWidth, height: metrics.height)

        // Drop target and empty cue: the glyph and its words, centred under the notch in the band the
        // surface pops out by, or inside the widened bubble.
        let glyph = Self.promptGlyphSize
        let promptMidY = metrics.isNotch
            ? promptRect.minY + metrics.height + (promptRect.height - metrics.height) / 2
            : promptRect.midY
        let promptStartX = (metrics.isNotch ? bounds.midX : promptRect.midX) - promptContentWidth / 2
        promptGlyphLayer.bounds = CGRect(x: 0, y: 0, width: glyph, height: glyph)
        promptGlyphLayer.position = CGPoint(x: promptStartX + glyph / 2, y: promptMidY)
        promptLabelLayer.bounds = CGRect(x: 0, y: 0, width: promptTextSize.width + 2, height: promptTextSize.height)
        promptLabelLayer.position = CGPoint(x: promptStartX + glyph + Self.promptGap + (promptTextSize.width + 2) / 2,
                                            y: promptMidY)
    }

    /// Snaps a position to the display's pixel grid so the mark and text stay crisp.
    private func pixelAligned(_ value: CGFloat) -> CGFloat {
        let scale = window?.backingScaleFactor ?? 2
        return (value * scale).rounded() / scale
    }

    /// Opacity of the shape and of the mark, the dot and the Tuck button, from expansion, resting in the
    /// notch, the drop invitation, hover and any swipe in progress. Resting in the notch the surface draws
    /// nothing unless hovered, pulled or still shrinking into it, so only the hardware notch shows.
    private func applyVisibility(animated: Bool, duration: CFTimeInterval = 0.16) {
        let shape: Float
        let content: Float
        if isShowingExpanded {
            shape = 1
            content = 0
        } else if promptLevel != nil {
            // The words take the bubble's room; around a notch the mark stays in its wing.
            shape = 1
            content = anchor.kind == .notch ? 1 : 0
        } else if restsInNotch {
            let pull = max(gesturePull, 0)
            shape = pull > 0 || isHovering || isShrinkingIntoNotch ? 1 : 0
            content = swipeStage == .tucked ? Float(pull) : 0
        } else {
            shape = 1
            content = holdsCollapsedContent ? 0 : Float(1 - max(-gesturePull, 0))
        }
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(duration)
        } else {
            CATransaction.setDisableActions(true)
        }
        shapeLayer.opacity = shape
        let button = showsTuckButton
        let buttonInMarksPlace = buttonTakesMarksPlace
        // Empty, a notch shows no mark unless a drop or the cue brings the wings out; a bubble always does,
        // except while the Tuck button stands in its place.
        let showsMark = holdsAnything || !metrics.isNotch || promptLevel != nil
        markLayer.opacity = showsMark && !buttonInMarksPlace ? content : 0
        // The line lights while the pointer is over the closed surface, as it greets it, and goes back to
        // faint when the pointer leaves. A bubble's mark stays faint as it gives way to the button.
        let pointedAt = isHovering && !isShowingExpanded && !isShowingTucked && promptLevel == nil
        markLitLayer.opacity = pointedAt && !buttonInMarksPlace ? 1 : 0
        // The resting dot shrinks away as the arrow rises into its place, and back again. A bubble has no
        // dot: its mark shrinks a little as it fades, and the arrow rises in the middle where it was.
        restingDotLayer.opacity = showsMark && !button && metrics.isNotch ? content : 0
        tuckArrowLayer.opacity = button ? content : 0
        markLayer.transform = buttonInMarksPlace && !reduceMotion ? CATransform3DMakeScale(0.7, 0.7, 1) : CATransform3DIdentity
        if !reduceMotion {
            restingDotLayer.transform = button ? CATransform3DMakeScale(0.4, 0.4, 1) : CATransform3DIdentity
            if !isPressingTuck {
                let scale: CGFloat = button ? 1 : 0.6
                let rise = button ? 0 : TuckLogo.lineWidth(side: metrics.markSide)
                tuckArrowLayer.transform = CATransform3DTranslate(CATransform3DMakeScale(scale, scale, 1), 0, rise, 0)
            }
        }
        CATransaction.commit()
    }

    /// The right wing, or the middle of a bubble, is a Tuck button while the pointer is over the closed
    /// surface.
    private var showsTuckButton: Bool {
        isHovering && !isShowingExpanded && !restsInNotch && promptLevel == nil && !holdsCollapsedContent
    }

    /// A bubble holds one symbol: while the Tuck button shows, it stands in the mark's place.
    private var buttonTakesMarksPlace: Bool { showsTuckButton && !metrics.isNotch }

    /// What a deposit landing swells: the mark, or the Tuck button while it stands in the mark's place, so
    /// the swell is never drawn on a hidden mark.
    private var landingLayer: CALayer { buttonTakesMarksPlace ? tuckArrowLayer : markLayer }

    /// What was deposited lands in the mark: an empty mark takes its card, otherwise the mark swells once
    /// (in a bubble pointed at, the Tuck button in its place does). A drop on the closed surface draws
    /// into the mark first (`compressIntoMark`).
    private func pulseIfNeeded() {
        guard let plusOne = model.plusOne, plusOne.token != lastPlusOneToken else { return }
        lastPlusOneToken = plusOne.token
        let wait = compressionEnds - CACurrentMediaTime()
        guard wait > 0 else { return landDeposit() }
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.landDeposit() }
    }

    private func landDeposit() {
        // Landing in an empty mark drops its card in, with its own swell.
        guard !dropCardIfWaiting(), !reduceMotion else { return }
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 1.12, 1]
        pulse.keyTimes = [0, 0.42, 1]
        pulse.duration = 0.24
        landingLayer.add(pulse, forKey: "pulse")
    }

    /// A small sideways shake of the mark and the dot (or the Tuck button), or of a bubble's one symbol,
    /// when an action (a keyboard shortcut, say) did nothing while the panel is closed. With the panel
    /// open, its status line says why instead.
    private func shakeIfNeeded() {
        guard model.refusals != lastRefusals else { return }
        lastRefusals = model.refusals
        guard !isShowingExpanded, !isShowingTucked, !reduceMotion else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -4, 4, -2.5, 1.5, 0]
        shake.keyTimes = [0, 0.15, 0.4, 0.62, 0.82, 1]
        shake.duration = 0.36
        shake.isAdditive = true
        for layer in [markLayer, restingDotLayer, tuckArrowLayer] { layer.add(shake, forKey: "refuse") }
    }

    // MARK: Deposits

    /// Where a tucked window's card lands, in global coordinates: the window's row or tile while the
    /// open panel shows it, as a Tuck-blue dot on its icon that opens out into the row; the dip of the
    /// mark on the closed surface (in a bubble pointed at, the foot of the Tuck button standing there); or
    /// the middle of the surface, with no dot, while it rests in the notch.
    func depositLanding(window windowID: UUID) -> DepositLanding? {
        guard let window else { return nil }
        layoutSubtreeIfNeeded()
        func screen(_ point: CGPoint) -> CGPoint { window.convertPoint(toScreen: convert(point, to: nil)) }

        if isShowingExpanded, model.windowPicker == nil, let landing = model.windowLandings[windowID],
           model.listFrame.insetBy(dx: -1, dy: -1).contains(landing.frame) {
            let row = landing.frame.offsetBy(dx: panelContentRect.minX, dy: panelContentRect.minY)
            let icon = landing.icon.offsetBy(dx: panelContentRect.minX, dy: panelContentRect.minY)
            let appearance = contentAppearance
            return DepositLanding(
                point: screen(CGPoint(x: icon.midX, y: icon.midY)),
                dot: DepositLanding.Dot(diameter: icon.width,
                                        fill: appearanceCGColor(Theme.accentNSColor, for: appearance)),
                row: DepositLanding.Row(frame: window.convertToScreen(convert(row, to: nil)),
                                        cornerRadius: RowChrome.cornerRadius,
                                        tint: appearanceCGColor(Theme.accentNSColor.withAlphaComponent(0.1), for: appearance))
            )
        }
        if !isShowingExpanded, !restsInNotch {
            // A dot the line's thickness, into the mark's dip.
            let side = metrics.markSide
            let point = CGPoint(x: markLayer.position.x, y: markLayer.position.y + TuckLogo.cardOffset(side: side))
            return DepositLanding(point: screen(point),
                                  dot: DepositLanding.Dot(diameter: TuckLogo.lineWidth(side: side),
                                                          fill: appearanceCGColor(Theme.accentNSColor, for: contentAppearance)))
        }
        let rect = surfaceRect
        return DepositLanding(point: screen(CGPoint(x: rect.midX, y: rect.minY + metrics.height / 2)), dot: nil)
    }

    /// A drop on the closed surface goes into the mark: the drop words and glyph draw together into it,
    /// shrinking, as the band folds back, and the mark takes them in as they arrive (`pulseIfNeeded`).
    /// Under Reduce Motion they simply fade with the band.
    private func compressIntoMark() {
        guard !reduceMotion else { return }
        let target = NSValue(point: markLayer.position)
        for layer in [promptGlyphLayer, promptLabelLayer] {
            let start = (layer.presentation() ?? layer)
            let move = CASpringAnimation(keyPath: "position")
            move.fromValue = NSValue(point: start.position)
            move.toValue = target
            move.mass = 1
            move.stiffness = 170
            move.damping = 24
            move.duration = 0.48
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1
            shrink.toValue = 0.15
            shrink.duration = 0.42
            shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = start.opacity
            fade.toValue = 0
            fade.duration = 0.42
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.9, 1)
            let group = CAAnimationGroup()
            group.animations = [move, shrink, fade]
            group.duration = 0.48
            layer.add(group, forKey: "compress")
        }
        compressionEnds = CACurrentMediaTime() + 0.4
    }

    // MARK: Expand / collapse

    var isPreparingToExpand: Bool { preparingToken != nil }

    /// Builds the panel out of sight first, so its real height is known before the surface moves: the
    /// surface then makes one spring to the right size instead of correcting itself mid-flight.
    func prepareToExpand(_ ready: @escaping () -> Void) {
        // Marked first, so a model change that building the panel sets off finds it under way: it can't
        // start a second build, and a cancel it causes lets this one go rather than leaving it behind.
        let token = UUID()
        preparingToken = token
        attachPanel()
        host?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.preparingToken == token else { return }
            self.preparingToken = nil
            ready()
        }
    }

    /// Drops a panel that was being prepared when the surface no longer needs to open.
    func cancelExpand() {
        guard preparingToken != nil else { return }
        preparingToken = nil
        if !isShowingExpanded, let host {
            self.host = nil
            Self.release(host)
        }
    }

    /// Lets go of every panel still in the surface while it is closed and nothing is preparing to open.
    /// None should be there by then; one that is keeps its whole SwiftUI tree, observing the model.
    func dropIdlePanel() {
        guard !isShowingExpanded, preparingToken == nil else { return }
        host = nil
        for case let host as PanelHostingView in panelClip.subviews { Self.release(host) }
    }

    /// Lands any shape animation at once, so a window resize can't shift a morph that is in flight.
    func finishMorphs() {
        for layer in [shapeLayer, promptRimLayer, panelMask, promptGlyphLayer, promptLabelLayer] {
            layer.removeAnimation(forKey: "morph")
        }
        shapeLayer.removeAnimation(forKey: "morphShadow")
        // Removing a Core Animation morph does not run its transaction completion handler. A close
        // waits on that handler before shrinking the panel window, so settle pending work explicitly
        // whenever a layout change lands a morph early.
        morphSettled()
    }

    /// Opening is one lively spring for the whole outline, with the panel clipped to it and fading in
    /// just behind while the black of the notch gains its shadow; closing settles without overshoot while
    /// the panel fades and folds away inside it, and the mark and dot come back once it is nearly home.
    func setExpanded(_ expanded: Bool, completion: (() -> Void)? = nil) {
        guard expanded != isShowingExpanded else {
            completion?()
            return
        }
        isShowingExpanded = expanded
        gesturePull = 0
        if expanded {
            // The fold takes over from the empty cue.
            isShowingCue = false
            if promptLevel != nil, !isDragging { promptLevel = nil }
            applySurfaceFill(animated: true)
            applyPromptAppearance(animated: true)
            // From the keyboard the panel is wanted at once: no overshoot to wait out.
            let spring = model.lastTrigger == .keyboard ? SurfaceMotion.settle : SurfaceMotion.open
            animateShape(to: surfacePath(for: surfaceRect), spring: spring, completion: completion)
            isPressed = false
            isPressingTuck = false
            holdsCollapsedContent = false
            applyVisibility(animated: true, duration: 0.08)
            attachPanel()
            host?.frame = panelContentRect
            revealPanel()
            return
        }
        // Closing into the notch keeps the shape until it has shrunk back, then lets it go.
        isShrinkingIntoNotch = restsInNotch
        shownRestsInNotch = restsInNotch
        holdsCollapsedContent = true
        // Home is the resting form unless the pointer is over where the closed surface will be: hover set
        // before the panel opened must not carry the wider, pointed-at form back with it.
        isHovering = isPointerOverClosedSurface && promptLevel == nil
        applySurfaceFill(animated: true)
        // The mark and dot were laid out for the open panel, further out than the wings: put them back in
        // place while they are hidden, so they come back where they belong rather than jump there.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyContentColors()
        layoutCollapsedContent()
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        applyDropRim()
        CATransaction.commit()
        animateShape(to: surfacePath(for: surfaceRect), spring: SurfaceMotion.close) { [weak self] in
            guard let self else { return }
            self.isShrinkingIntoNotch = false
            self.applyVisibility(animated: true)
            completion?()
        }
        applyVisibility(animated: true, duration: 0.12)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, !self.isShowingExpanded, self.holdsCollapsedContent else { return }
            self.holdsCollapsedContent = false
            self.applyVisibility(animated: true, duration: 0.2)
        }
        detachPanel()
    }

    /// Whether the outline is animating; the window is not resized meanwhile, since that lands it early.
    var isMorphing: Bool { shapeLayer.animation(forKey: "morph") != nil }

    /// The outline's current on-screen path: the running morph's, or the model path at rest.
    private var displayedPath: CGPath? {
        isMorphing ? (shapeLayer.presentation()?.path ?? shapeLayer.path) : shapeLayer.path
    }

    /// Completions of morphs that a newer morph replaced run when the outline is finally at rest, not
    /// when they were cut short (which would resize the window mid-animation and snap the shape).
    private var pendingMorphCompletions: [() -> Void] = []

    /// Runs `work` now if the outline is at rest, otherwise as soon as it is.
    func whenSettled(_ work: @escaping () -> Void) {
        if isMorphing { pendingMorphCompletions.append(work) } else { work() }
    }

    private func morphSettled() {
        guard !isMorphing else { return }
        let completions = pendingMorphCompletions
        pendingMorphCompletions.removeAll()
        completions.forEach { $0() }
    }

    private func animateShape(to path: CGPath, spring: SpringParameters = SurfaceMotion.settle,
                              from start: CGPath? = nil, completion: (() -> Void)? = nil) {
        // Start from what is on screen only while a morph is actually running. Otherwise the model path is
        // the truth: the presentation layer still holds the last committed frame, which after a window
        // resize is in the old window's coordinates and would make the shape start off to one side.
        let from = start ?? displayedPath
        if let completion { pendingMorphCompletions.append(completion) }
        let animation = Self.morph("path", spring: spring, from: from, to: path)
        let shadow = animation.copy() as! CASpringAnimation
        shadow.keyPath = "shadowPath"
        let rim = animation.copy() as! CASpringAnimation
        rim.fromValue = from.map(rimPath)
        rim.toValue = rimPath(path)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.morphSettled() }
        setOutline(path)
        for layer in [shapeLayer, panelMask] { layer.add(animation, forKey: "morph") }
        shapeLayer.add(shadow, forKey: "morphShadow")
        promptRimLayer.add(rim, forKey: "morph")
        CATransaction.commit()
    }

    /// One of the outline's springs, run to the end (a spring cut short jumps to its target). With Reduce
    /// Motion every change settles without bouncing.
    private static func morph(_ keyPath: String, spring: SpringParameters, from: Any?, to: Any?) -> CASpringAnimation {
        let spring = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? SurfaceMotion.settle : spring
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = 1
        animation.stiffness = CGFloat(spring.stiffness)
        animation.damping = CGFloat(spring.damping)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
    }

    /// Applies an outline to everything that follows it: the shape, its shadow, the drop rim and the
    /// mask the panel is clipped to.
    private func setOutline(_ path: CGPath) {
        shapeLayer.path = path
        shapeLayer.shadowPath = path
        promptRimLayer.path = rimPath(path)
        panelMask.path = path
    }

    /// The drop rim traces the outline but not its top, which around a notch is the screen's own top edge:
    /// stroked, it drew a line along the top of each wing and in under the notch. The shoulders still
    /// start along that edge, so `promptRimFade` fades them out before they reach it.
    private func rimPath(_ outline: CGPath) -> CGPath {
        guard anchor.kind == .notch else { return outline }
        let open = CGMutablePath()
        outline.applyWithBlock { element in
            let points = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint: open.move(to: points[0])
            case .addLineToPoint: open.addLine(to: points[0])
            case .addQuadCurveToPoint: open.addQuadCurve(to: points[1], control: points[0])
            case .addCurveToPoint: open.addCurve(to: points[2], control1: points[0], control2: points[1])
            default: break
            }
        }
        return open
    }

    /// Adds the panel, invisible; `revealPanel` fades it in once the surface is opening.
    private func attachPanel() {
        guard host == nil else { return }
        let root = ExpandedPanelView(model: model, anchor: anchor) { [weak self] height in
            self?.panelHeightChanged(height)
        }
        let host = PanelHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        host.frame = panelContentRect
        host.alphaValue = 0
        // On the black fold the panel is always drawn dark, whatever the Light or Dark setting.
        host.appearance = contentAppearance
        // Recorded before it joins the view tree: a host added first and recorded after could be
        // replaced by one that the insertion asked for, and then nothing would ever take it out.
        self.host = host
        panelClip.addSubview(host)
    }

    /// Fades the panel in a beat after the outline starts to open, so the shape leads and the content
    /// arrives inside it.
    private func revealPanel() {
        guard let host else { return }
        host.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak host] in
            guard let self, let host, self.host === host, self.isShowingExpanded else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.25, 1)
                host.animator().alphaValue = 1
            }
        }
    }

    /// Fades the panel out at once, but releases its SwiftUI tree only once the outline is back home:
    /// tearing the tree down takes the main thread for a moment, and done mid-close it held the screen
    /// on a half-closed frame for half a second before the outline jumped into the notch.
    private func detachPanel() {
        guard let host else { return }
        self.host = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            host.animator().alphaValue = 0
        }
        whenSettled { [weak host] in
            if let host { Self.release(host) }
        }
    }

    /// Empties a panel host and takes it out of the surface. Removing it alone doesn't free its SwiftUI
    /// tree: AppKit can keep the view (the window holds on to the last view a scroll went to), and the
    /// tree goes with it. Swapping in an empty view while it is still in the window frees the tree now.
    private static func release(_ host: PanelHostingView) {
        host.rootView = AnyView(EmptyView())
        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        host.removeFromSuperview()
    }

    private func panelHeightChanged(_ height: CGFloat) {
        let rounded = ceil(height)
        guard rounded > 30, abs(rounded - panelHeight) > 0.5 else { return }
        let shrinking = rounded < panelHeight
        panelHeight = rounded
        guard isShowingExpanded else { return }
        // From what is on screen now: resizing the window lays the new outline out at once. The window
        // grows first, and shrinks only once the outline has, so it never clips the shape.
        let from = displayedPath
        if !shrinking {
            onNeedsWindowFrame?()
            layoutSubtreeIfNeeded()
        }
        animateShape(to: surfacePath(for: surfaceRect), from: from) { [weak self] in
            if shrinking { self?.onNeedsWindowFrame?() }
        }
        host?.frame = panelContentRect
    }

    // MARK: Drop target

    /// Shows, updates or hides the drop invitation. Called only when the level changes, so a drag costs
    /// at most `DropApproach.levels` small layer animations on its way in.
    func setDropPrompt(_ level: Int?, completion: (() -> Void)? = nil) {
        watcherLevel = level
        updatePrompt(completion: completion)
    }

    private func updatePrompt(completion: (() -> Void)? = nil) {
        // The open panel takes drops itself: let the invitation go without a second spring competing with
        // the opening one. (The closed window's room follows `promptLevel`, so it goes too.)
        if isShowingExpanded {
            if promptLevel != nil {
                promptLevel = nil
                applyPromptAppearance(animated: true)
            }
            completion?()
            return
        }
        let level = isAcceptingDrop ? DropApproach.levels : (watcherLevel ?? (isShowingCue ? 0 : nil))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyPromptContent()
        CATransaction.commit()
        guard level != promptLevel else {
            applyPromptAppearance(animated: true)
            completion?()
            return
        }
        // The window grows before the shape pops out, and shrinks only once it has folded back in. Mid-
        // morph (a close still settling) the invitation waits, since resizing would land the morph early.
        if promptLevel == nil, level != nil {
            if isMorphing {
                pendingMorphCompletions.append { [weak self] in self?.updatePrompt(completion: completion) }
                return
            }
            onPromptRoom?(true)
            layoutSubtreeIfNeeded()
        }
        promptLevel = level
        animateShape(to: surfacePath(for: surfaceRect), spring: SurfaceMotion.pop) { [weak self] in
            guard let self else { return }
            if self.promptLevel == nil, level == nil {
                self.onPromptRoom?(false)
                // The wings follow the library again once the invitation has gone.
                self.followRestingForm()
            }
            completion?()
        }
        movePromptContent(spring: SurfaceMotion.pop)
        applyPromptAppearance(animated: true)
        needsLayout = true
    }

    /// The glyph and its words move to their place in the new outline on the outline's own spring, so
    /// they ride down with the band as it pops out, bounce with it, and go back up into the notch with
    /// it, rather than waiting at their final place.
    private func movePromptContent(spring: SpringParameters) {
        let layers = [promptGlyphLayer, promptLabelLayer]
        // As for the outline, the presentation layer is only the truth while a move is running.
        let starts = layers.map { layer in
            layer.animation(forKey: "morph") != nil ? (layer.presentation() ?? layer).position : layer.position
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutCollapsedContent()
        for (layer, start) in zip(layers, starts) where layer.position != start {
            layer.add(Self.morph("position", spring: spring, from: NSValue(point: start), to: NSValue(point: layer.position)),
                      forKey: "morph")
        }
        CATransaction.commit()
    }

    private func applyPromptAppearance(animated: Bool) {
        let showing = promptLevel != nil && !isShowingExpanded
        let closeness = CGFloat(promptLevel ?? 0) / CGFloat(DropApproach.levels)
        // Appearing, the words fade in slowly at first, so they don't show ahead of the shape popping out.
        let appearing = showing && promptGlyphLayer.opacity == 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? (appearing ? 0.24 : 0.16) : 0)
        CATransaction.setAnimationTimingFunction(appearing ? CAMediaTimingFunction(controlPoints: 0.7, 0, 0.8, 1)
                                                           : CAMediaTimingFunction(name: .easeOut))
        applyDropRim()
        promptGlyphLayer.opacity = showing ? Float(0.75 + 0.25 * closeness) : 0
        promptLabelLayer.opacity = showing ? Float(0.8 + 0.2 * closeness) : 0
        CATransaction.commit()
        applyVisibility(animated: animated)
    }

    /// The drop rim, in Tuck blue on the outline so it wraps the notch and rides every spring: around the
    /// invitation while a drag nears, firming up over the target, and around the open panel while
    /// something is dragged over it. The empty cue has none.
    private func applyDropRim() {
        promptRimLayer.strokeColor = appearanceCGColor(Theme.accentNSColor, for: contentAppearance)
        if isShowingExpanded {
            promptRimLayer.opacity = model.isDragActive ? 0.55 : 0
            promptRimLayer.lineWidth = 1.5
        } else {
            let closeness = CGFloat(promptLevel ?? 0) / CGFloat(DropApproach.levels)
            promptRimLayer.opacity = promptLevel != nil && isDragging ? Float(0.3 + 0.7 * closeness) : 0
            // Over the target the rim firms up: release here and the item is taken.
            promptRimLayer.lineWidth = promptLevel == DropApproach.levels ? 2 : 1.5
        }
    }

    // MARK: Tucking away

    /// Tucks the closed surface into the notch or brings it back out, morphing on from wherever a swipe
    /// left it. While the panel is open the change waits for it to close.
    func setTuckedAway(_ tucked: Bool) {
        guard tucked != isShowingTucked else { return }
        isShowingTucked = tucked
        gesturePull = 0
        followRestingForm()
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isShowingExpanded, !isDragging else { return }
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isShowingExpanded else { return }
        setHovering(false)
    }

    /// Pointing at the closed surface opens nothing: one that holds something greets the pointer, lights
    /// its mark and offers the Tuck button (a bubble's mark gives way to it instead); an empty notch shows
    /// "Drop into Tuck". A bubble offers the button even when Tuck is empty, as it did before the prompt.
    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering, model.isStreamEmpty, metrics.isNotch {
            isShowingCue = true
            updatePrompt()
            return
        }
        if !hovering, isShowingCue {
            isShowingCue = false
            updatePrompt()
            return
        }
        if hovering { greetMark() }
        animateShape(to: surfacePath(for: surfaceRect))
        applyVisibility(animated: true)
        needsLayout = true
    }

    /// Where the pointer counts as over the closed surface: the closed window's area, centred on the
    /// notch, whatever size the window is at the moment.
    private var isPointerOverClosedSurface: Bool {
        guard let window else { return false }
        let size = metrics.collapsedWindowSize
        let zone = CGRect(x: bounds.midX - size.width / 2, y: 0, width: size.width, height: size.height)
        return zone.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    /// Hover follows where the pointer is, not only the enter and exit events. When the window shrinks
    /// under a still pointer (the panel closing), AppKit replaces the tracking area without sending an
    /// exit, and the surface stayed in its pointed-at form until the pointer came back and left again.
    /// Called once the closed window has its size.
    func pointerMayHaveMoved() {
        guard !isShowingExpanded, !isDragging else { return }
        setHovering(isPointerOverClosedSurface)
    }

    /// A press gives a little; letting go over the surface opens it from the pressed shape, letting go
    /// elsewhere springs it back. A press on the Tuck button presses the button instead.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isShowingExpanded {
            if !surfaceRect.contains(point) { model.collapse(via: .click) }
        } else if showsTuckButton, tuckButtonRect.contains(point) {
            isPressingTuck = true
            setTuckArrowPressed(true)
        } else if surfaceRect.insetBy(dx: -4, dy: -4).contains(point) {
            isPressed = true
            animateShape(to: surfacePath(for: surfaceRect))
            needsLayout = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isPressingTuck {
            isPressingTuck = false
            setTuckArrowPressed(false)
            if tuckButtonRect.insetBy(dx: -6, dy: -6).contains(convert(event.locationInWindow, from: nil)) {
                model.tuckFrontWindow()
            }
            return
        }
        guard isPressed, !isShowingExpanded else { return }
        let point = convert(event.locationInWindow, from: nil)
        if surfaceRect.insetBy(dx: -8, dy: -8).contains(point) {
            // The pressed shape stays until the open spring takes over from it.
            model.toggle(on: anchor.screenID, via: .click)
            if model.isExpanded(on: anchor.screenID) { return }
        }
        isPressed = false
        animateShape(to: surfacePath(for: surfaceRect), spring: SurfaceMotion.release)
        needsLayout = true
    }

    /// The Tuck button presses in, as the panel's buttons do; Reduce Motion keeps it still. Letting go
    /// hands it back to `applyVisibility`, which keeps it full size while it still shows.
    private func setTuckArrowPressed(_ pressed: Bool) {
        guard !reduceMotion else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        tuckArrowLayer.transform = pressed ? CATransform3DMakeScale(0.86, 0.86, 1) : CATransform3DIdentity
        CATransaction.commit()
        if !pressed { applyVisibility(animated: true) }
    }

    // MARK: Swipes

    private var swipeStage: SwipeGestureTracker.Stage {
        if isShowingExpanded { return model.foldDepth == .full ? .full : .expanded }
        // Empty, the bare notch is the closed surface itself: down opens it, as from the wings.
        return isShowingTucked && holdsAnything ? .tucked : .collapsed
    }

    /// Two-finger trackpad swipes, delivered by the overlay's scroll monitor before the panel sees them.
    /// Fingers down deepen (bring a tucked surface back, open the fold, unfold it); fingers up go back one
    /// step. A gesture that starts over a list long enough to scroll belongs to the list, and mouse wheels
    /// (including Tuck's own smooth scrolling, which has no gesture phase) never count as swipes. One that
    /// starts over the shallow fold's strip is held back until it shows its axis: sideways, the strip is
    /// handed all of it and scrolls; up or down, it is a swipe like any other.
    func handleScroll(_ event: NSEvent) -> Bool {
        guard event.hasPreciseScrollingDeltas, !isReplayingScroll else { return false }
        // The glide after a swipe the surface used must not scroll anything underneath.
        if !event.momentumPhase.isEmpty { return gestureRouting.owner == .surface }
        guard !event.phase.isEmpty else { return false }
        let starts = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        if starts || !gestureRouting.isInGesture { heldScrollEvents = [] }
        let step = gestureRouting.route(starts: starts, ends: ended, region: scrollRegion(for: event),
                                        dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        switch step {
        case .swipe(let began):
            swipe(with: event, began: began, ended: ended)
            return true
        case .passOn:
            return false
        case .hold:
            heldScrollEvents.append(event)
            return true
        case .swipeHeld:
            let held = heldScrollEvents
            heldScrollEvents = []
            for (index, earlier) in held.enumerated() { swipe(with: earlier, began: index == 0, ended: false) }
            swipe(with: event, began: held.isEmpty, ended: ended)
            return true
        case .passOnHeld:
            let held = heldScrollEvents
            heldScrollEvents = []
            isReplayingScroll = true
            held.forEach { window?.sendEvent($0) }
            isReplayingScroll = false
            return false
        }
    }

    private func swipe(with event: NSEvent, began: Bool, ended: Bool) {
        let inverted = event.isDirectionInvertedFromDevice
        let down = inverted ? event.scrollingDeltaY : -event.scrollingDeltaY
        let right = inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        let stage = swipeStage
        if let action = swipe.process(down: down, right: right, began: began, ended: ended, stage: stage) {
            gesturePull = 0 // the stage change animates on from wherever the fingers left the surface
            model.handleSwipe(action, on: anchor.screenID)
        } else {
            followPull(swipe.pull(stage: stage), settling: ended)
        }
    }

    /// Where a gesture over the open panel starts. The panel's frames are in SwiftUI's named panel space:
    /// the event is converted straight into the hosting view's local space rather than by subtracting the
    /// animated surface's changing origin. The small inset tolerates pixel-rounding at a clipped
    /// ScrollView's edge.
    private func scrollRegion(for event: NSEvent) -> ScrollGestureRouting.Region {
        guard isShowingExpanded, let host else { return .surface }
        let point = host.convert(event.locationInWindow, from: nil)
        if model.foldDepth == .peek, let strip = model.stripFrame, strip.contains(point) { return .strip }
        if let list = model.scrollableListFrame, list.insetBy(dx: -2, dy: -2).contains(point) { return .scrollableList }
        return .surface
    }

    /// Moves the closed surface with the fingers, or eases it back when they lift short of the
    /// threshold. Runs only while a swipe is in progress.
    private func followPull(_ pull: CGFloat, settling: Bool) {
        guard !isShowingExpanded, promptLevel == nil, pull != gesturePull else { return }
        gesturePull = pull
        let path = surfacePath(for: surfaceRect)
        if settling {
            animateShape(to: path)
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            layoutCollapsedContent()
            CATransaction.commit()
            applyVisibility(animated: true)
            return
        }
        finishMorphs()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setOutline(path)
        layoutCollapsedContent()
        CATransaction.commit()
        applyVisibility(animated: false)
    }

    // MARK: VoiceOver

    /// What VoiceOver last heard the closed surface hold, so it is told only of a change.
    private var spokenSummary: String?
    /// A change is announced a moment after it settles, so a burst of them (every window coming back at
    /// once) is one announcement of where things ended up.
    private var pendingAnnouncement: DispatchWorkItem?

    /// Closed, the surface is one button named Tuck, whose value is what Tuck holds, counted, as the notch
    /// itself doesn't; pressing it opens the panel, with focus, as the keyboard shortcut does. Open, it
    /// steps aside for the panel's own controls.
    override func isAccessibilityElement() -> Bool { !isShowingExpanded }
    override func accessibilityRole() -> NSAccessibility.Role? { isShowingExpanded ? .group : .button }
    override func accessibilityLabel() -> String? { "Tuck" }
    override func accessibilityValue() -> Any? { isShowingExpanded ? nil : model.spaceSummary }

    /// The outline, not the window around it, which leaves room for the panel.
    override func accessibilityFrame() -> NSRect {
        guard let window, !isShowingExpanded else { return super.accessibilityFrame() }
        return window.convertToScreen(convert(surfaceRect, to: nil))
    }

    override func accessibilityPerformPress() -> Bool {
        guard !isShowingExpanded else { return false }
        model.expand(on: anchor.screenID, via: .keyboard)
        return true
    }

    private func announceSummaryIfChanged() {
        let summary = model.spaceSummary
        guard summary != spokenSummary else { return }
        let first = spokenSummary == nil
        spokenSummary = summary
        guard !first, !isShowingExpanded else { return }
        NSAccessibility.post(element: self, notification: .valueChanged)
        // VoiceOver speaks a value change only while its focus is on the surface, so the change is
        // announced too, at low priority so it never cuts into anything else being read. Only while
        // VoiceOver is on, so nothing is scheduled otherwise.
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        pendingAnnouncement?.cancel()
        let announce = DispatchWorkItem { [weak self] in
            guard let self, !self.isShowingExpanded, self.spokenSummary == summary else { return }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
                .announcement: "Tuck, \(summary)",
                .priority: NSAccessibilityPriorityLevel.low.rawValue,
            ])
        }
        pendingAnnouncement = announce
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: announce)
    }

    // MARK: Dropping

    /// Where a drop is taken: the open panel, or the closed surface as it pops out for a drop. The
    /// window around it is larger and transparent; a drag over that margin is refused so a release near
    /// the menu bar is never captured by accident.
    private var dropTargetRect: CGRect {
        let rect = surfaceRect
        if isShowingExpanded { return rect.insetBy(dx: -6, dy: -6) }
        let slack = DropApproach.targetSlack
        return CGRect(x: rect.minX - slack.width, y: rect.minY,
                      width: rect.width + slack.width * 2, height: max(rect.height, metrics.height + slack.height))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Only the advertised types are checked here; nothing is read until the drop.
        guard DropReader.canRead(sender.draggingPasteboard) else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        guard dropTargetRect.contains(point) else {
            leaveDropTarget()
            return []
        }
        if !isAcceptingDrop {
            isAcceptingDrop = true
            model.dragEntered(on: anchor.screenID, kind: DropReader.kind(of: sender.draggingPasteboard))
            updatePrompt()
        }
        model.updateDropTarget(isOver: true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        leaveDropTarget()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isAcceptingDrop = false
        updatePrompt()
    }

    private func leaveDropTarget() {
        guard isAcceptingDrop else { return }
        isAcceptingDrop = false
        updatePrompt()
        model.dragExited(from: anchor.screenID)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let source = NSWorkspace.shared.frontmostApplication?.localizedName
        guard let payload = DropReader.payload(from: sender.draggingPasteboard, sourceAppName: source) else { return false }
        let intoMark = !isShowingExpanded
        // Set before the deposit, whose confirmation then waits for the words to reach the mark.
        if intoMark, !reduceMotion { compressionEnds = CACurrentMediaTime() + 0.4 }
        isAcceptingDrop = false
        setDropPrompt(nil)
        model.deposit(payload, at: panelPoint(for: sender))
        if intoMark {
            layoutSubtreeIfNeeded()
            compressIntoMark()
        }
        return true
    }

    private func panelPoint(for sender: NSDraggingInfo) -> CGPoint {
        let point = convert(sender.draggingLocation, from: nil)
        let origin = panelContentRect.origin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }
}

/// Holds the panel and clips it to the surface's outline (its layer's mask follows the shape), so the
/// shape reveals the panel as it opens and folds it away as it closes. Clicks and drops anywhere outside
/// the panel fall through to the surface view.
final class PanelClipView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// Hosting view for the SwiftUI panel: accepts the first click (the panel never activates Tuck) and never
/// registers as a drag destination, so drops always reach the surface view underneath.
final class PanelHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {}
}
