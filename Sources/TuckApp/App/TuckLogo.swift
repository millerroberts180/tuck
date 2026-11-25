import AppKit

/// Tuck's logo, one rounded line: the top edge of the screen dipping down round the notch. Drawn in code
/// from the geometry in design/logo/generate.py (its 256-unit grid; keep the two in step), so there is no
/// image resource to bundle or load, and the line takes whichever colour it is given.
enum TuckLogo {
    static let blue = NSColor(srgbRed: 0x72 / 255, green: 0x99 / 255, blue: 0xC5 / 255, alpha: 1)
    /// How faintly the closed surface's mark shows at rest, until the pointer arrives and lights it.
    static let restingOpacity: CGFloat = 0.32

    /// One cut of the line, symmetric about x 128. The small cut is bolder, with shorter tails and a deeper
    /// dip, so the dip stays open at 16 px. `cardHalf` and `cardY` place the short card that rests in the
    /// dip while Tuck holds something, as wide as the line and 16 units clear of the floor.
    private struct Cut {
        let tail: CGFloat
        let wall: CGFloat
        let top: CGFloat
        let floor: CGFloat
        let radius: CGFloat
        let weight: CGFloat
        let cardHalf: CGFloat
        let cardY: CGFloat
    }

    private static let regular = Cut(tail: 28, wall: 68, top: 92, floor: 160, radius: 36, weight: 24,
                                     cardHalf: 22, cardY: 120)
    private static let small = Cut(tail: 36, wall: 72, top: 82, floor: 170, radius: 36, weight: 32,
                                   cardHalf: 12, cardY: 122)
    /// Where the card starts as it drops into the dip: above the line.
    private static let cardStartY: CGFloat = 40
    /// How much further the dip reaches down at full reach, in grid units.
    private static let reachDepth: CGFloat = 28

    private static func cut(for side: CGFloat) -> Cut { side < 32 ? small : regular }

    /// The line in a square of `side` points, y down (for flipped views and layers), to be stroked
    /// `lineWidth(side:)` wide with round caps and joins; below 32 pt it is the small cut. It runs left to
    /// right, so half way along it is at the floor of the dip. `reach` (0 at rest, 1 at most) deepens the
    /// dip; every reach has the same elements, so Core Animation can morph between them.
    static func linePath(side: CGFloat, reach: CGFloat = 0) -> CGPath {
        let cut = cut(for: side), scale = side / 256
        let floor = cut.floor + reachDepth * reach
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
        let path = CGMutablePath()
        path.move(to: point(cut.tail, cut.top))
        path.addLine(to: point(cut.wall, cut.top))
        path.addArc(tangent1End: point(cut.wall, floor), tangent2End: point(128, floor),
                    radius: cut.radius * scale)
        path.addArc(tangent1End: point(256 - cut.wall, floor), tangent2End: point(256 - cut.wall, cut.top),
                    radius: cut.radius * scale)
        path.addLine(to: point(256 - cut.wall, cut.top))
        path.addLine(to: point(256 - cut.tail, cut.top))
        return path
    }

    static func lineWidth(side: CGFloat) -> CGFloat { cut(for: side).weight * side / 256 }

    /// The card at rest in the dip, y down, to be stroked `lineWidth(side:)` wide with round caps.
    static func cardPath(side: CGFloat) -> CGPath {
        let cut = cut(for: side), scale = side / 256
        let path = CGMutablePath()
        path.move(to: CGPoint(x: (128 - cut.cardHalf) * scale, y: cut.cardY * scale))
        path.addLine(to: CGPoint(x: (128 + cut.cardHalf) * scale, y: cut.cardY * scale))
        return path
    }

    /// The Tuck button's arrow in the logo's own line, y down, to be stroked `lineWidth(side:)` wide with
    /// round caps and joins: a shaft as tall as the dip, from the line's top to its floor, so it sits level
    /// with the mark across the notch, and a head as deep as it is half wide.
    static func arrowPath(side: CGFloat) -> CGPath {
        let cut = cut(for: side), scale = side / 256, head: CGFloat = 40
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
        let path = CGMutablePath()
        path.move(to: point(128, cut.floor))
        path.addLine(to: point(128, cut.top))
        path.move(to: point(128 - head, cut.top + head))
        path.addLine(to: point(128, cut.top))
        path.addLine(to: point(128 + head, cut.top + head))
        return path
    }

    /// How far below the square's centre the card rests, in points.
    static func cardOffset(side: CGFloat) -> CGFloat { (cut(for: side).cardY - 128) * side / 256 }

    /// How far the card drops into the dip as Tuck starts holding something, in points.
    static func cardDrop(side: CGFloat) -> CGFloat { (cut(for: side).cardY - cardStartY) * side / 256 }

    /// The menu-bar icon: the small cut as a template image, so the menu bar tints it.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            draw(in: rect, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tuck"
        return image
    }

    /// The mark alone, square, in the given colour.
    static func markImage(side: CGFloat, color: NSColor = blue) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            draw(in: rect, color: color)
            return true
        }
    }

    private static func draw(in rect: NSRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.addPath(linePath(side: rect.width))
        context.setLineWidth(lineWidth(side: rect.width))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.cgColor)
        context.strokePath()
    }
}
