import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Placement geometry")
struct PlacementGeometryTests {
    let visible = CGRect(x: 0, y: 40, width: 1000, height: 700)

    private func frame(_ placement: Placement, original: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400)) -> CGRect {
        PlacementGeometry.frame(for: placement, originalFrame: original, visibleFrame: visible)
    }

    @Test func thirdsTileWithTheRemainderOnTheRight() {
        let left = frame(.leftThird), centre = frame(.centerThird), right = frame(.rightThird)
        #expect(left == CGRect(x: 0, y: 40, width: 333, height: 700))
        #expect(centre == CGRect(x: 333, y: 40, width: 333, height: 700))
        #expect(right == CGRect(x: 666, y: 40, width: 334, height: 700))
        #expect(left.maxX == centre.minX && centre.maxX == right.minX && right.maxX == visible.maxX)
    }

    @Test func twoThirdsPairWithTheOppositeThird() {
        #expect(frame(.leftTwoThirds) == CGRect(x: 0, y: 40, width: 666, height: 700))
        #expect(frame(.leftTwoThirds).maxX == frame(.rightThird).minX)
        #expect(frame(.rightTwoThirds) == CGRect(x: 333, y: 40, width: 667, height: 700))
        #expect(frame(.rightTwoThirds).minX == frame(.leftThird).maxX)
    }

    @Test func quartersUseAppKitCoordinatesWithTopRowHigherUp() {
        #expect(frame(.bottomLeft) == CGRect(x: 0, y: 40, width: 500, height: 350))
        #expect(frame(.topLeft) == CGRect(x: 0, y: 390, width: 500, height: 350))
        #expect(frame(.topRight) == CGRect(x: 500, y: 390, width: 500, height: 350))
        #expect(frame(.bottomRight).maxX == visible.maxX)
        #expect(frame(.topRight).maxY == visible.maxY)
    }

    @Test func centreKeepsTheSizeAndShrinksToFit() {
        #expect(frame(.center) == CGRect(x: 200, y: 190, width: 600, height: 400))
        let huge = frame(.center, original: CGRect(x: 0, y: 0, width: 3000, height: 2000))
        #expect(huge == visible)
    }

    @Test func nextDisplayKeepsRelativePositionAndFits() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let destination = CGRect(x: 1000, y: 0, width: 2000, height: 1200)
        let window = CGRect(x: 100, y: 200, width: 500, height: 400)
        let moved = PlacementGeometry.translate(window, from: source, to: destination)
        #expect(moved == CGRect(x: 1300, y: 400, width: 500, height: 400))

        let small = CGRect(x: -800, y: 0, width: 800, height: 600)
        let shrunk = PlacementGeometry.translate(CGRect(x: 0, y: 0, width: 1000, height: 800), from: source, to: small)
        #expect(shrunk == small)
    }

    @Test func nextDisplayWithoutADestinationLeavesTheWindow() {
        let original = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(frame(.nextDisplay, original: original) == original)
    }

    @Test func nextDisplayWrapsRound() {
        #expect(PlacementGeometry.nextDisplay(after: 2, in: [1, 2, 3]) == 3)
        #expect(PlacementGeometry.nextDisplay(after: 3, in: [1, 2, 3]) == 1)
        #expect(PlacementGeometry.nextDisplay(after: 1, in: [1]) == nil)
    }

    @Test func flippingBetweenAppKitAndQuartzIsItsOwnInverse() {
        let appKit = CGRect(x: 50, y: 100, width: 400, height: 300)
        let quartz = PlacementGeometry.flipped(appKit, primaryDisplayHeight: 900)
        #expect(quartz == CGRect(x: 50, y: 500, width: 400, height: 300))
        #expect(PlacementGeometry.flipped(quartz, primaryDisplayHeight: 900) == appKit)
        #expect(PlacementGeometry.flipped(CGPoint(x: 5, y: 10), primaryDisplayHeight: 900) == CGPoint(x: 5, y: 890))
    }

    @Test func fitTellsExactConstrainedAndRejectedApart() {
        let target = CGRect(x: 0, y: 0, width: 500, height: 700)
        #expect(PlacementGeometry.fit(actual: target.offsetBy(dx: 1, dy: -1), target: target) == .exact)
        #expect(PlacementGeometry.fit(actual: CGRect(x: 0, y: 100, width: 640, height: 600), target: target) == .constrained)
        #expect(PlacementGeometry.fit(actual: CGRect(x: 2000, y: 0, width: 500, height: 700), target: target) == .rejected)
    }

    @Test func constrainedWindowsStayPinnedToThePlacementEdges() {
        let size = CGSize(width: 640, height: 500)
        let right = frame(.rightHalf)
        let pinnedRight = PlacementGeometry.anchored(actualSize: size, target: right, placement: .rightHalf, visibleFrame: visible)
        #expect(pinnedRight.maxX == visible.maxX)
        #expect(pinnedRight.maxY == visible.maxY) // full-height placements hang from the top

        let corner = frame(.bottomLeft)
        let pinnedCorner = PlacementGeometry.anchored(actualSize: size, target: corner, placement: .bottomLeft, visibleFrame: visible)
        #expect(pinnedCorner.origin == CGPoint(x: 0, y: 40))

        let tooWide = PlacementGeometry.anchored(actualSize: CGSize(width: 1200, height: 300), target: right,
                                                 placement: .rightHalf, visibleFrame: visible)
        #expect(tooWide.minX == visible.minX) // never pushed off the left edge
    }

    @Test func historyKeepsTheFrameFromBeforeTheFirstPlacement() {
        var history = PlacementHistory()
        let first = CGRect(x: 1, y: 2, width: 3, height: 4)
        history.remember(first, for: "w")
        history.remember(CGRect(x: 9, y: 9, width: 9, height: 9), for: "w")
        #expect(history.frame(for: "w") == first)
        let taken = history.take(for: "w")
        let again = history.take(for: "w")
        #expect(taken == first)
        #expect(again == nil)

        for index in 0..<(PlacementHistory.capacity + 5) {
            history.remember(.zero, for: "k\(index)")
        }
        #expect(history.count == PlacementHistory.capacity)
        #expect(history.frame(for: "k0") == nil)
    }
}
