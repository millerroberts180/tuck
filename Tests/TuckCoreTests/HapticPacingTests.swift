import Foundation
import Testing
@testable import TuckCore

@Suite("Haptic pacing")
struct HapticPacingTests {
    /// Plays a run of ticks at the given times and reports which were allowed.
    func allowed(_ times: [TimeInterval]) -> [Bool] {
        var pacing = HapticPacing()
        return times.map { pacing.allows(at: $0) }
    }

    @Test func ticksTooCloseTogetherAreDropped() {
        #expect(allowed([10, 10.1, 10.34, 10.36]) == [true, false, false, true])
    }

    @Test func aDroppedTickDoesNotPushTheNextOneBack() {
        #expect(allowed([0, 0.3, 0.36]) == [true, false, true])
    }

    @Test func ticksFarApartAllPlay() {
        #expect(allowed([0, 1, 2, 3]) == [true, true, true, true])
    }

    /// Swipes, folds, scrolling and clicks are shown on screen only; only these three are felt.
    @Test func onlyDropsDepositsAndSnapsCanTick() {
        #expect(HapticEvent.allCases == [.dropTargetEntered, .deposited, .placementSnapped])
    }
}
