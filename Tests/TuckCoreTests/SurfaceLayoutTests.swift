import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Surface layout")
struct SurfaceLayoutTests {
    @Test func theFoldsListFitsItsContentWithinLimits() {
        #expect(PanelListLayout.viewportHeight(contentHeight: 200, maximumHeight: 320) == 200)
        #expect(PanelListLayout.viewportHeight(contentHeight: 500, maximumHeight: 320) == 320)
        #expect(PanelListLayout.viewportHeight(contentHeight: 10, maximumHeight: 320) == PanelListLayout.minimumHeight)
        #expect(PanelListLayout.scrolls(contentHeight: 500, viewportHeight: 320))
        #expect(!PanelListLayout.scrolls(contentHeight: 200, viewportHeight: 200))
        // Half a point of rounding is not something to scroll.
        #expect(!PanelListLayout.scrolls(contentHeight: 200.4, viewportHeight: 200))
    }

    @Test func theFoldShowsThreeMediumCardsUnlessToldOtherwise() {
        #expect(CardLayout.standard.columns == 3)
        #expect(CardLayout.standard.size == .medium)
        #expect(FoldLayout.standard.cardSize == CGSize(width: 168, height: 96))
        #expect(FoldLayout.standard.width == 540)
        #expect(FoldLayout.standard.sideInset == FoldLayout.edgeInset)
        #expect(FoldDepth.peek != FoldDepth.full)
    }

    @Test func cardsInARowAreTwoToFive() {
        #expect(CardLayout(columns: 1).columns == 2)
        #expect(CardLayout(columns: 9).columns == 5)
        #expect(CardLayout.columnChoices.map { CardLayout(columns: $0).columns } == [2, 3, 4, 5])
    }

    @Test func theFoldIsAsWideAsARowOfItsCards() {
        let small = FoldLayout(cards: CardLayout(columns: 4, size: .small), minimumWidth: 0, maximumWidth: 2000)
        #expect(small.cardSize == CGSize(width: 151, height: 86))
        #expect(small.width == 648)
        #expect(small.cardSize.width >= FoldLayout.narrowestCard)
        let large = FoldLayout(cards: CardLayout(columns: 5, size: .large), minimumWidth: 0, maximumWidth: 2000)
        #expect(large.cardSize == CGSize(width: 218, height: 124))
        #expect(large.width == 1142)
        #expect(large.rowWidth + 2 * large.sideInset == large.width)
    }

    @Test func cardsShrinkToFitANarrowDisplayRatherThanBeingCut() {
        let fold = FoldLayout(cards: CardLayout(columns: 5, size: .large), minimumWidth: 417, maximumWidth: 900)
        #expect(fold.columns == 5)
        #expect(fold.width <= 900)
        #expect(fold.rowWidth <= fold.width - 2 * FoldLayout.edgeInset)
        #expect(fold.cardSize.width == 169)
        // Shrunk, they keep their shape.
        #expect(abs(fold.cardSize.width / fold.cardSize.height - 218 / 124) < 0.05)
    }

    @Test func aRowDropsACardRatherThanShrinkingItsTitlesPastReading() {
        let fold = FoldLayout(cards: CardLayout(columns: 5, size: .large), minimumWidth: 417, maximumWidth: 800)
        #expect(fold.columns == 4)
        #expect(fold.width == 800)
        #expect(fold.cardSize.width == 189)
        #expect(fold.rowWidth + 2 * fold.sideInset == fold.width)
        // Two is as few as a row holds, and a card shrunk that far keeps a small card's height.
        let tight = FoldLayout(cards: CardLayout(columns: 3), minimumWidth: 0, maximumWidth: 300)
        #expect(tight.columns == 2)
        #expect(tight.width == 300)
        #expect(tight.cardSize == CGSize(width: 136, height: 86))
        // Where there is room, three medium cards stay three.
        #expect(FoldLayout(cards: CardLayout(columns: 3), minimumWidth: 417, maximumWidth: 1200).columns == 3)
    }

    @Test func aFewSmallCardsSitInTheMiddleOfAFoldTheNotchKeepsWide() {
        let fold = FoldLayout(cards: CardLayout(columns: 2, size: .small), minimumWidth: 417, maximumWidth: 1400)
        #expect(fold.width == 417)
        #expect(fold.cardSize == CGSize(width: 151, height: 86))
        #expect(fold.sideInset == ((417 - fold.rowWidth) / 2).rounded(.down))
        #expect(fold.sideInset > FoldLayout.edgeInset)
    }
}

@Suite("Tile navigation")
struct TileNavigationTests {
    private func step(_ index: Int?, _ move: TileNavigation.Move, count: Int = 8, columns: Int = 3,
                      strip: Bool = false) -> Int? {
        TileNavigation.step(from: index, move, count: count, columns: columns, isStrip: strip)
    }

    @Test func fromNoTileDownOrRightGoesToTheFirst() {
        #expect(step(nil, .down) == 0)
        #expect(step(nil, .right) == 0)
        #expect(step(nil, .up) == nil)
        #expect(step(nil, .left) == nil)
        #expect(step(nil, .down, count: 0) == nil)
    }

    @Test func theArrowsMoveAlongARowAndBetweenRows() {
        #expect(step(0, .right) == 1)
        #expect(step(4, .left) == 3)
        #expect(step(1, .down) == 4)
        #expect(step(4, .up) == 1)
        // The ends of the stream keep the place.
        #expect(step(0, .left) == 0)
        #expect(step(7, .right) == 7)
    }

    @Test func upFromTheFirstRowLeavesTheTiles() {
        #expect(step(2, .up) == nil)
        #expect(step(0, .up) == nil)
    }

    @Test func downIntoAShortLastRowGoesToItsLastTile() {
        // Eight in rows of three: the last row holds 6 and 7, so down from 5 lands on 7.
        #expect(step(5, .down) == 7)
        #expect(step(4, .down) == 7)
        #expect(step(7, .down) == 7)
        #expect(step(6, .down) == 6)
    }

    @Test func theStripIsOneLongRow() {
        #expect(step(2, .right, strip: true) == 3)
        #expect(step(3, .down, strip: true) == 3)
        #expect(step(3, .up, strip: true) == nil)
        #expect(step(7, .right, strip: true) == 7)
    }

    @Test func aPlaceOutsideTheStreamIsBroughtInsideIt() {
        #expect(step(12, .left) == 6)
        #expect(step(-3, .right) == 1)
    }
}
