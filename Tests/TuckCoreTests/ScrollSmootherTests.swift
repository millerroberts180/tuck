import Foundation
import Testing
@testable import TuckCore

@Suite("Scroll smoothing")
struct ScrollSmootherTests {
    private func run(_ smoother: inout ScrollSmoother, frames: Int = 400, dt: TimeInterval = 1.0 / 120) -> (Int, Int, Int) {
        var vertical = 0, horizontal = 0, count = 0
        for _ in 0..<frames {
            let frame = smoother.advance(elapsed: dt)
            vertical += Int(frame.vertical)
            horizontal += Int(frame.horizontal)
            count += 1
            if frame.finished { break }
        }
        return (vertical, horizontal, count)
    }

    @Test func classifiesDevicesFromEventFields() {
        #expect(ScrollInput.classify(isContinuous: false, scrollPhase: 0, momentumPhase: 0) == .wheel)
        #expect(ScrollInput.classify(isContinuous: true, scrollPhase: 0, momentumPhase: 0) == .preciseWheel)
        #expect(ScrollInput.classify(isContinuous: true, scrollPhase: 1, momentumPhase: 0) == .gesture)
        #expect(ScrollInput.classify(isContinuous: true, scrollPhase: 0, momentumPhase: 2) == .gesture)
    }

    @Test func everyNotchMovesAUsefulDistanceAndKeepsAcceleration() {
        #expect(ScrollSmoother.distance(forPointDelta: 0) == 0)
        #expect(ScrollSmoother.distance(forPointDelta: 10) == 10 + ScrollSmoother.notchLift)
        #expect(ScrollSmoother.distance(forPointDelta: -10) == -10 - ScrollSmoother.notchLift)
        #expect(ScrollSmoother.distance(forPointDelta: 200) > ScrollSmoother.distance(forPointDelta: 20))
    }

    @Test func aGlideDeliversExactlyTheRequestedDistance() {
        var smoother = ScrollSmoother(smoothness: .balanced)
        smoother.add(vertical: 123.7, horizontal: -40.2)
        let (vertical, horizontal, frames) = run(&smoother)
        #expect(vertical == 124)
        #expect(horizontal == -40)
        #expect(smoother.isIdle)
        #expect(frames > 5) // spread over several frames, not one jump
    }

    @Test func ticksDuringAGlideExtendIt() {
        var smoother = ScrollSmoother(smoothness: .balanced)
        smoother.add(vertical: 100, horizontal: 0)
        var moved = 0
        for _ in 0..<5 { moved += Int(smoother.advance(elapsed: 1.0 / 60).vertical) }
        smoother.add(vertical: 100, horizontal: 0)
        let (rest, _, _) = run(&smoother)
        #expect(moved + rest == 200)
    }

    @Test func reversingDropsWhatWasLeftOnThatAxis() {
        var smoother = ScrollSmoother(smoothness: .gliding)
        smoother.add(vertical: 300, horizontal: 0)
        _ = smoother.advance(elapsed: 1.0 / 60)
        smoother.add(vertical: -50, horizontal: 0)
        #expect(smoother.remainingVertical == -50)
        let (rest, _, _) = run(&smoother)
        #expect(rest == -50)
    }

    @Test func aStalledFrameNeverJumps() {
        var smoother = ScrollSmoother(smoothness: .snappy)
        smoother.add(vertical: 1000, horizontal: 0)
        let stalled = smoother.advance(elapsed: 2)
        var reference = ScrollSmoother(smoothness: .snappy)
        reference.add(vertical: 1000, horizontal: 0)
        let capped = reference.advance(elapsed: ScrollSmoother.maximumFrame)
        #expect(stalled.vertical == capped.vertical)
        #expect(stalled.vertical < 1000)
    }

    @Test func smootherFeelsTakeLonger() {
        func frames(_ smoothness: ScrollSmoothness) -> Int {
            var smoother = ScrollSmoother(smoothness: smoothness)
            smoother.add(vertical: 400, horizontal: 0)
            return run(&smoother).2
        }
        #expect(frames(.snappy) < frames(.balanced))
        #expect(frames(.balanced) < frames(.gliding))
    }
}
