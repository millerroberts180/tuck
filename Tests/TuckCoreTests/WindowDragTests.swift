import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Modifier-drag")
struct WindowDragTests {
    let window = CGRect(x: 100, y: 100, width: 800, height: 600) // Quartz: y grows downwards

    @Test func exactModifiersStartTheRightGesture() {
        let keys = WindowDragModifiers.controlOption
        #expect(keys.gesture(for: [.maskControl, .maskAlternate], rightButton: false) == .move)
        #expect(keys.gesture(for: [.maskControl, .maskAlternate], rightButton: true) == .resize)
        #expect(keys.gesture(for: [.maskControl, .maskAlternate, .maskShift], rightButton: false) == .resize)
        #expect(keys.gesture(for: [.maskControl], rightButton: false) == nil)
        #expect(keys.gesture(for: [.maskControl, .maskAlternate, .maskCommand], rightButton: false) == nil)
        #expect(WindowDragModifiers.controlOptionCommand.gesture(for: [.maskControl, .maskAlternate, .maskCommand],
                                                               rightButton: false) == .move)
    }

    @Test func moveKeepsTheSize() {
        let gesture = WindowDragGesture(kind: .move, pointer: CGPoint(x: 300, y: 300), windowFrame: window)
        #expect(gesture.frame(for: CGPoint(x: 350, y: 260)) == CGRect(x: 150, y: 60, width: 800, height: 600))
    }

    @Test func resizePullsTheCornerNearestThePointer() {
        let bottomRight = WindowDragGesture(kind: .resize, pointer: CGPoint(x: 850, y: 650), windowFrame: window)
        #expect(bottomRight.corner == .bottomRight)
        #expect(bottomRight.frame(for: CGPoint(x: 900, y: 700)) == CGRect(x: 100, y: 100, width: 850, height: 650))

        let topLeft = WindowDragGesture(kind: .resize, pointer: CGPoint(x: 150, y: 150), windowFrame: window)
        #expect(topLeft.corner == .topLeft)
        #expect(topLeft.frame(for: CGPoint(x: 100, y: 120)) == CGRect(x: 50, y: 70, width: 850, height: 630))
    }

    @Test func resizeNeverGoesBelowTheMinimumAndKeepsTheOppositeCorner() {
        let gesture = WindowDragGesture(kind: .resize, pointer: CGPoint(x: 850, y: 650), windowFrame: window)
        let tiny = gesture.frame(for: CGPoint(x: -2000, y: -2000))
        #expect(tiny.size == WindowDragGesture.minimumSize)
        #expect(tiny.origin == window.origin)

        let fromTopLeft = WindowDragGesture(kind: .resize, pointer: CGPoint(x: 150, y: 150), windowFrame: window)
        let collapsed = fromTopLeft.frame(for: CGPoint(x: 5000, y: 5000))
        #expect(collapsed.maxX == window.maxX && collapsed.maxY == window.maxY)
        #expect(collapsed.size == WindowDragGesture.minimumSize)
    }

    @Test func throttleCapsTheRate() {
        var throttle = FrameThrottle(framesPerSecond: 50) // 20 ms
        let first = throttle.shouldSend(at: 1.000)
        let tooSoon = throttle.shouldSend(at: 1.010)
        let later = throttle.shouldSend(at: 1.021)
        throttle.reset()
        let afterReset = throttle.shouldSend(at: 1.022)
        #expect(first && !tooSoon && later && afterReset)
    }
}
