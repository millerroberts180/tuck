import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Placement chooser")
struct PlacementChooserTests {
    @Test func startsClosed() {
        let state = PlacementChooserState()
        #expect(!state.isOpen)
        #expect(state.highlighted == .original)
    }

    @Test func commandClickTogglesTheSameRow() {
        var state = PlacementChooserState()
        let id = UUID()
        state.toggle(for: id)
        #expect(state.isOpen(for: id))
        state.toggle(for: id)
        #expect(!state.isOpen)
    }

    @Test func openingAnotherRowMovesTheChooser() {
        var state = PlacementChooserState()
        let first = UUID()
        let second = UUID()
        state.open(for: first)
        state.highlight(.rightHalf)
        state.toggle(for: second)
        #expect(state.isOpen(for: second))
        #expect(!state.isOpen(for: first))
        #expect(state.highlighted == .original)
    }

    @Test func commitReturnsTheChoiceAndCloses() {
        var state = PlacementChooserState()
        let id = UUID()
        state.open(for: id)
        let request = state.commit(.leftHalf)
        #expect(request == PlacementRequest(windowID: id, placement: .leftHalf))
        #expect(!state.isOpen)
        let second = state.commit()
        #expect(second == nil)
    }

    @Test func committingWithoutAChoiceUsesTheHighlight() {
        var state = PlacementChooserState()
        let id = UUID()
        state.open(for: id)
        state.moveHighlight(by: 2)
        #expect(state.highlighted == .rightHalf)
        state.moveHighlight(by: 1)
        #expect(state.highlighted == .fullScreen)
        state.moveHighlight(by: 100)
        #expect(state.highlighted == .nextDisplay)
        let request = state.commit()
        #expect(request?.placement == .nextDisplay)
    }

    @Test func highlightIsIgnoredWhileClosed() {
        var state = PlacementChooserState()
        state.highlight(.fullScreen)
        #expect(state.highlighted == .original)
    }

    @Test func halvesTileTheUsableAreaExactly() {
        let visible = CGRect(x: 0, y: 0, width: 1511, height: 944)
        let original = CGRect(x: 100, y: 100, width: 800, height: 600)
        let left = PlacementGeometry.frame(for: .leftHalf, originalFrame: original, visibleFrame: visible)
        let right = PlacementGeometry.frame(for: .rightHalf, originalFrame: original, visibleFrame: visible)
        #expect(left == CGRect(x: 0, y: 0, width: 755, height: 944))
        #expect(right == CGRect(x: 755, y: 0, width: 756, height: 944))
        #expect(left.maxX == right.minX)
        #expect(right.maxX == visible.maxX)
    }

    @Test func secondaryRowHoldsEveryFinerLayout() {
        #expect(Placement.primary.count + Placement.secondary.count == Placement.allCases.count)
        #expect(!Placement.secondary.contains(.original))
        #expect(Placement.secondary.last == .nextDisplay)
    }

    @Test func fullScreenFillsTheUsableArea() {
        let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = PlacementGeometry.frame(for: .fullScreen, originalFrame: .zero, visibleFrame: visible)
        #expect(frame == visible)
    }

    @Test func originalRestoresExactBoundsOrCentresWhenTheDisplayIsGone() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let original = CGRect(x: 1600, y: 200, width: 600, height: 400)
        #expect(PlacementGeometry.frame(for: .original, originalFrame: original, visibleFrame: visible) == original)
        let centred = PlacementGeometry.frame(for: .original, originalFrame: original, visibleFrame: visible,
                                              originalDisplayAvailable: false)
        #expect(centred == CGRect(x: 200, y: 200, width: 600, height: 400))
    }
}
