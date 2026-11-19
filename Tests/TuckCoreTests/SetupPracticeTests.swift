import Foundation
import Testing
@testable import TuckCore

@Suite("Setup practice")
struct SetupPracticeTests {
    @Test func setupAsksForAccessibilityThenPractisesThenFinishes() {
        #expect(SetupStep.steps(tutorialOnly: false) == [.accessibility, .practice, .done])
    }

    @Test func theTutorialIsOnlyThePractice() {
        #expect(SetupStep.steps(tutorialOnly: true) == [.practice])
    }

    @Test func theMovesAreTickedOffInAnyOrderAndEachCountsOnce() {
        var practice = SetupPractice()
        #expect(practice.done.isEmpty)
        let dropped = practice.record(.dropped(count: 1))
        #expect(dropped)
        #expect(practice.done == [.drop])
        let opened = practice.record(.opened)
        let openedAgain = practice.record(.opened)
        #expect(opened && !openedAgain)
        #expect(practice.done == [.drop, .open])
        let tucked = practice.record(.tucked(count: 2))
        #expect(tucked)
        let restored = practice.record(.restored(.moved))
        #expect(restored)
        #expect(practice.done == Set(SetupPractice.Move.allCases))
    }

    @Test func onlyAWindowBackOnScreenCountsAsBroughtBack() {
        for result in [WindowActionResult.moved, .constrained, .simulated] {
            #expect(SetupPractice.Event.restored(result).move == .bringBack)
        }
        for result in [WindowActionResult.windowGone, .needsPermission, .failed, .unchanged] {
            #expect(SetupPractice.Event.restored(result).move == nil)
            var practice = SetupPractice()
            let counted = practice.record(.restored(result))
            #expect(!counted)
            #expect(practice.done.isEmpty)
        }
    }

    @Test func nothingTuckedOrDroppedCountsForNothing() {
        var practice = SetupPractice()
        let tucked = practice.record(.tucked(count: 0))
        let dropped = practice.record(.dropped(count: 0))
        #expect(!tucked && !dropped)
        #expect(practice.done.isEmpty)
        #expect(SetupPractice.Event.tucked(count: 1).move == .tuck)
        #expect(SetupPractice.Event.dropped(count: 3).move == .drop)
    }
}
