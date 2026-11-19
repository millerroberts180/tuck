import CoreGraphics
import Foundation

/// How deep the open fold is.
public enum FoldDepth: Hashable, Sendable {
    /// The shallow fold (State 1): one row of tiles, the newest at the left, that scrolls sideways
    /// through the whole stream, with the lenses beside the notch. One more swipe down or a click on More
    /// shows everything at once.
    case peek
    /// The full fold (State 2): the same width, taller, with one quiet line on top (search and a fold
    /// button), the whole stream in rows that scroll, and Arrange windows at its foot.
    case full
}

/// How big the fold's cards are, from Settings › Notch.
public enum CardSize: String, CaseIterable, Hashable, Sendable {
    case small, medium, large

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// Width and height against medium's card. Small still holds a title and its line of details, and
    /// stays as wide as a card can be and still be read; large gives pictures and longer text more room.
    public var scale: CGFloat {
        switch self {
        case .small: 0.9
        case .medium: 1
        case .large: 1.3
        }
    }
}

/// How the fold lays out its cards, from Settings › Notch: how many sit side by side, and how big they
/// are. The shallow fold shows one row of that many; the full fold's rows hold the same number.
public struct CardLayout: Hashable, Sendable {
    public static let columnChoices = [2, 3, 4, 5]
    public static let standard = CardLayout()

    public let columns: Int
    public let size: CardSize

    public init(columns: Int = 3, size: CardSize = .medium) {
        self.columns = min(max(columns, Self.columnChoices[0]), Self.columnChoices[Self.columnChoices.count - 1])
        self.size = size
    }
}

/// The fold's width and its cards' size for a card layout on one display. The fold is as wide as a row
/// of its cards. It is never narrower than its top line needs, and the row then sits in the middle of it;
/// nor wider than the display leaves room for, and the cards then shrink to fit, keeping their shape.
/// Shrinking stops at the narrowest card whose title can still be read: past that a row holds one card
/// fewer (never fewer than two), so a narrow display shows two wide cards rather than three cramped ones.
public struct FoldLayout: Hashable, Sendable {
    /// Medium's card: three of them fill a 540 pt fold, tall enough for a title, a preview or two lines
    /// beneath it, and a line of details.
    public static let mediumCard = CGSize(width: 168, height: 96)
    public static let cardSpacing: CGFloat = 8
    /// From the fold's edge to its cards.
    public static let edgeInset: CGFloat = 10
    /// The narrowest a card shrinks to before its row drops a card.
    public static let narrowestCard: CGFloat = 150
    /// The layout a display of any size takes without a card setting: three medium cards, 540 pt.
    public static let standard = FoldLayout(cards: .standard, minimumWidth: 0, maximumWidth: .greatestFiniteMagnitude)

    public let columns: Int
    public let cardSize: CGSize
    public let width: CGFloat

    /// - Parameters:
    ///   - minimumWidth: what the fold's top line needs: the notch and room either side of it.
    ///   - maximumWidth: what the display leaves, with a margin each side.
    public init(cards: CardLayout, minimumWidth: CGFloat, maximumWidth: CGFloat) {
        let widest = max(maximumWidth, minimumWidth)
        func gaps(_ columns: Int) -> CGFloat { CGFloat(columns - 1) * Self.cardSpacing + Self.edgeInset * 2 }
        func fitted(_ columns: Int) -> CGFloat { ((widest - gaps(columns)) / CGFloat(columns)).rounded(.down) }
        var columns = cards.columns
        while columns > CardLayout.columnChoices[0], fitted(columns) < Self.narrowestCard { columns -= 1 }
        self.columns = columns
        var card = CGSize(width: (Self.mediumCard.width * cards.size.scale).rounded(.down),
                          height: (Self.mediumCard.height * cards.size.scale).rounded(.down))
        if card.width > fitted(columns) {
            let width = max(fitted(columns), 40)
            // Shrunk, a card keeps its shape, but never gets shorter than a small one: its lines stay whole.
            let shortest = (Self.mediumCard.height * CardSize.small.scale).rounded(.down)
            card = CGSize(width: width, height: max((card.height * width / card.width).rounded(.down), min(shortest, card.height)))
        }
        cardSize = card
        width = min(max(CGFloat(columns) * card.width + gaps(columns), minimumWidth), widest)
    }

    /// One row of cards, the gaps between them included.
    public var rowWidth: CGFloat { CGFloat(columns) * cardSize.width + CGFloat(columns - 1) * Self.cardSpacing }

    /// From the fold's edge to its first card: the edge inset, or more where the row sits in the middle.
    public var sideInset: CGFloat { max(((width - rowWidth) / 2).rounded(.down), Self.edgeInset) }
}

/// How tall the fold's scrolling list is: its content, between a small minimum and the maximum height,
/// beyond which it scrolls.
public enum PanelListLayout {
    public static let minimumHeight: CGFloat = 44

    public static func viewportHeight(contentHeight: CGFloat, maximumHeight: CGFloat) -> CGFloat {
        min(max(contentHeight, minimumHeight), maximumHeight)
    }

    /// Whether the list has more content than it shows, and so scrolls.
    public static func scrolls(contentHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        contentHeight > viewportHeight + 0.5
    }
}

/// Moving through the fold's tiles with the arrow keys. The full fold lays them in rows of `columns`;
/// the shallow fold's strip is one long row. Nowhere further to go keeps the place, and up from the
/// first row leaves the tiles (nil), back to the search field or the fold itself.
public enum TileNavigation {
    public enum Move: Sendable {
        case left, right, up, down
    }

    /// Where `move` goes from `index` (nil: on no tile) among `count` tiles. From no tile, down or right
    /// goes to the first; up or left stays on none.
    public static func step(from index: Int?, _ move: Move, count: Int, columns: Int, isStrip: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let index = index.map({ min(max($0, 0), count - 1) }) else {
            return move == .down || move == .right ? 0 : nil
        }
        let columns = isStrip ? count : max(columns, 1)
        switch move {
        case .left: return max(index - 1, 0)
        case .right: return min(index + 1, count - 1)
        case .up: return index >= columns ? index - columns : nil
        case .down:
            if index + columns < count { return index + columns }
            // Down into a last row too short to have a tile under this one goes to its last.
            return index / columns < (count - 1) / columns ? count - 1 : index
        }
    }
}
