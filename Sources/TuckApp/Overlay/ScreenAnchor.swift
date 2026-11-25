import AppKit
import TuckCore

/// Where Tuck sits on a display: tucked around the hardware notch, or on displays without one as a small
/// bubble in the menu-bar strip or, if chosen in Settings, a drawn notch.
struct ScreenAnchor: Equatable {
    enum Kind: Equatable { case notch, bubble }

    /// Width of a drawn notch on a display without one.
    static let simulatedNotchWidth: CGFloat = 180

    let kind: Kind
    let screenID: CGDirectDisplayID
    let screenFrame: CGRect
    /// Notch size, hardware or drawn; zero for bubble displays.
    let notchSize: CGSize
    let menuBarHeight: CGFloat
    /// Horizontal centre the surface is drawn around, in global coordinates: the notch's own centre,
    /// which can sit half a point off the screen's, or the screen's centre otherwise.
    let centerX: CGFloat
    /// A drawn notch on a display without a hardware one: nothing hides behind it.
    var isSimulated = false

    static func resolve(for screen: NSScreen, notchless: NotchlessStyle = .bubble) -> ScreenAnchor {
        let frame = screen.frame
        var menuBar = frame.maxY - screen.visibleFrame.maxY
        if menuBar < 1 { menuBar = 24 } // menu bar set to auto-hide

        // A notched display reports a top safe-area inset and the usable menu-bar areas either side of
        // the camera housing; the notch is the gap between them.
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return ScreenAnchor(
                kind: .notch,
                screenID: screen.displayID,
                screenFrame: frame,
                notchSize: CGSize(width: max(width, 120), height: screen.safeAreaInsets.top),
                menuBarHeight: menuBar,
                centerX: frame.minX + left.width + width / 2
            )
        }
        if notchless == .notch {
            // As tall as the menu bar, so it reads as the notch a notched Mac would have there.
            return ScreenAnchor(kind: .notch, screenID: screen.displayID, screenFrame: frame,
                                notchSize: CGSize(width: simulatedNotchWidth, height: menuBar),
                                menuBarHeight: menuBar, centerX: frame.midX, isSimulated: true)
        }
        return ScreenAnchor(kind: .bubble, screenID: screen.displayID, screenFrame: frame,
                            notchSize: .zero, menuBarHeight: menuBar, centerX: frame.midX)
    }

    /// Area near the top centre where a drag that settles opens the drop surface.
    var dragApproachZone: CGRect { DropApproach.approachZone(in: screenFrame) }
}

/// Sizes for the collapsed and expanded surface, shared by the AppKit view and its window controller.
///
/// On a notched display the closed surface is exactly the notch, hardware or drawn, with nothing on it. A
/// drag pops a band out below it with a wing's room either side, a square of the notch's height plus a
/// little, so it sits snugly around the camera housing and keeps the same proportions on every notched
/// Mac.
struct SurfaceMetrics {
    /// The least room the fold's top line keeps either side of the notch (or the bubble's mark): the Tuck
    /// button on one side, the lenses on the other.
    static let bandWingWidth: CGFloat = 130
    /// The least room the open fold leaves either side of it on the display.
    static let foldScreenMargin: CGFloat = 48
    /// Outward curves where the notch surface meets the top edge (notch displays only).
    static let shoulder: CGFloat = 8
    /// Rounding of the collapsed notch surface's lower corners.
    static let notchCornerRadius: CGFloat = 13
    /// How far the collapsed surface reaches below the reported notch height. The physical notch can end
    /// a fraction of a point lower than the safe-area inset says at scaled resolutions, which would
    /// otherwise show as a thin line of notch under the surface.
    static let notchOverlap: CGFloat = 2
    /// Tuck's mark, alone in the middle of a bubble.
    static let markSize: CGFloat = 20
    /// The Tuck button that takes a bubble's mark's place while the pointer is over it.
    static let tuckButtonSize: CGFloat = 20
    /// Each end of a bubble, either side of the Tuck button's target: a click there opens the fold.
    static let bubbleEndWidth: CGFloat = 20

    let anchor: ScreenAnchor
    /// Only the notch, or a bubble's spot: at rest around a notch, or swiped away.
    var isTuckedAway = false
    /// How many cards the fold shows in a row, and how big, from Settings › Notch.
    var cards = CardLayout.standard

    var isNotch: Bool { anchor.kind == .notch }

    var height: CGFloat {
        isNotch ? anchor.notchSize.height + Self.notchOverlap : min(max(anchor.menuBarHeight - 6, 20), 28)
    }

    /// The mark and the Tuck button as drawn, inside a bubble's height with room above and below, since on
    /// most external displays the bubble is only 20 pt tall.
    var markSide: CGFloat { isNotch ? Self.markSize : min(Self.markSize, height - 4) }
    var tuckButtonSide: CGFloat { isNotch ? Self.tuckButtonSize : min(Self.tuckButtonSize, height - 6) }

    /// Bubbles float in the middle of the menu-bar strip rather than touching the top edge.
    var topInset: CGFloat {
        isNotch ? 0 : max(((anchor.menuBarHeight - height) / 2).rounded(), 2)
    }

    /// Width of the room the drop band takes either side of a notch.
    var wingWidth: CGFloat { anchor.notchSize.height + 4 }

    /// A bubble at rest, holding one symbol, the mark or the Tuck button in its place: the button's target
    /// (the button and 6 pt either side) with an end either side of that. Around a notch, the notch with a
    /// wing either side, which the drop band pops out from.
    var restingSize: CGSize {
        if isNotch {
            return CGSize(width: anchor.notchSize.width + wingWidth * 2 + Self.shoulder * 2, height: height)
        }
        let target = Self.tuckButtonSize + 12
        return CGSize(width: max(target + Self.bubbleEndWidth * 2, height * 1.9), height: height)
    }

    /// The closed notch, hardware or drawn, or a bubble swiped away to a bubble-high spot.
    var tuckedSize: CGSize {
        isNotch
            ? CGSize(width: anchor.notchSize.width + Self.shoulder * 2, height: height)
            : CGSize(width: height, height: height)
    }

    var collapsedSize: CGSize { isTuckedAway ? tuckedSize : restingSize }

    /// The window around the closed surface, before any room for the drop invitation, with a little
    /// margin; it is also where the pointer counts as over it. Around a notch it is the notch's, so
    /// pointing at the menu bar beside it doesn't count. A bubble's is its resting size even while it is
    /// tucked away, so tucking, revealing and a swipe that pulls it never resize it mid-animation.
    var collapsedWindowSize: CGSize {
        let size = isNotch ? tuckedSize : restingSize
        return CGSize(width: size.width + 24, height: topInset + size.height + 10)
    }

    /// The open fold on this display: a row of its cards wide, but never narrower than its top line needs
    /// around the notch, nor wider than the display leaves room for.
    var fold: FoldLayout {
        let middle = isNotch ? anchor.notchSize.width : restingSize.width
        let shoulders = isNotch ? Self.shoulder * 2 : 0
        return FoldLayout(cards: cards, minimumWidth: middle + Self.bandWingWidth * 2,
                          maximumWidth: anchor.screenFrame.width - Self.foldScreenMargin * 2 - shoulders)
    }

    var panelWidth: CGFloat { fold.width }
    var expandedWidth: CGFloat { panelWidth + (isNotch ? Self.shoulder * 2 : 0) }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
