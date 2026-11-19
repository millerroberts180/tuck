import Foundation
import Testing
@testable import TuckCore

/// Obsidian (pid 3) has its window "3:30" tucked and "3:31" still in view; Safari (pid 1) is another app.
@Suite("Leaving Mission Control")
struct MissionControlVisitTests {
    let tucked = MissionControlVisit.Landing(pid: 3, window: WindowToken("3:30"))

    func at(_ pid: Int32, _ window: String? = nil) -> MissionControlVisit.Landing {
        MissionControlVisit.Landing(pid: pid, window: window.map(WindowToken.init))
    }

    @Test func leavingWithTheFrontWhereItWasChoosesNothing() {
        // The window in front clicked, Esc, F3 again or a swipe down: Safari is still in front.
        var visit = MissionControlVisit()
        visit.began(front: at(1, "1:10"))
        visit.ended(at: 100)
        #expect(!visit.choseWindow(tucked, front: at(1, "1:10")))
    }

    @Test func theKeyboardLeftInTheTuckedWindowIsNotAChoice() {
        // Obsidian kept the keyboard in the window as it went: it is still there as Mission Control ends.
        var visit = MissionControlVisit()
        visit.began(front: tucked)
        visit.ended(at: 100)
        #expect(!visit.choseWindow(tucked, front: tucked))
    }

    @Test func choosingTheTuckedWindowThereBringsItBack() {
        var visit = MissionControlVisit()
        visit.began(front: at(1, "1:10"))
        visit.ended(at: 100)
        #expect(visit.choseWindow(tucked, front: tucked))
        // From Obsidian's other window, too.
        var fromSibling = MissionControlVisit()
        fromSibling.began(front: at(3, "3:31"))
        fromSibling.ended(at: 100)
        #expect(fromSibling.choseWindow(tucked, front: tucked))
    }

    @Test func choosingAnotherWindowLeavesTheTuckedOneTucked() {
        var visit = MissionControlVisit()
        visit.began(front: at(1, "1:10"))
        visit.ended(at: 100)
        #expect(!visit.choseWindow(tucked, front: at(3, "3:31")))
        #expect(!visit.choseWindow(tucked, front: at(2, "2:20")))
        // With the front unread, nothing counts as chosen.
        #expect(!visit.choseWindow(tucked, front: nil))
    }

    @Test func anEndWithNoStartSeenChoosesNothing() {
        // Tuck began watching while it showed: what was in front as it began isn't known.
        var visit = MissionControlVisit()
        visit.ended(at: 100)
        #expect(visit.frontAtStart == nil)
        #expect(!visit.choseWindow(tucked, front: tucked))
    }

    @Test func movingBetweenItsViewsKeepsWhereItBegan() {
        // Mission Control, then App Exposé: the second start is read with Obsidian's window highlighted.
        var visit = MissionControlVisit()
        visit.began(front: at(1, "1:10"))
        visit.began(front: tucked)
        #expect(visit.frontAtStart == at(1, "1:10"))
        visit.ended(at: 100)
        #expect(!visit.choseWindow(tucked, front: at(1, "1:10")))
    }

    @Test func aSecondExitRightAfterTheFirstKeepsWhereItBegan() {
        // Another app coming forward ends it before the Dock says so.
        var visit = MissionControlVisit()
        visit.began(front: at(1, "1:10"))
        visit.ended(at: 100)
        visit.ended(at: 100.3)
        #expect(visit.frontAtStart == at(1, "1:10"))
        #expect(visit.choseWindow(tucked, front: tucked))
        // Long after, an exit with no start seen knows nothing of the earlier visit.
        visit.ended(at: 200)
        #expect(visit.frontAtStart == nil)
    }

    @Test func theDockSayingItEndedLongAfterTuckTookItToHaveIsStillThatVisit() {
        // Obsidian's window moved while it showed, so it was taken to have ended; the person stayed on,
        // and chose the tucked window there.
        var visit = MissionControlVisit()
        visit.began(front: at(1, "1:10"))
        visit.ended(at: 100, assumed: true)
        visit.ended(at: 110)
        #expect(visit.frontAtStart == at(1, "1:10"))
        #expect(visit.choseWindow(tucked, front: tucked))
        #expect(visit.isUnderway(at: 110.4))
        // A visit after that is judged afresh.
        visit.ended(at: 200)
        #expect(visit.frontAtStart == nil)
    }

    @Test func whatItLeavesIsItsDoingForAMomentAfterTheExit() {
        var visit = MissionControlVisit()
        #expect(!visit.isUnderway(at: 99))
        visit.began(front: at(1, "1:10"))
        #expect(visit.isShowing)
        #expect(visit.isUnderway(at: 99))
        visit.ended(at: 100)
        #expect(!visit.isShowing)
        #expect(visit.isUnderway(at: 101.4))
        #expect(!visit.isUnderway(at: 101.5))
    }

    @Test func itsWindowsAreLookedAtOnceTheExitHasSettled() {
        var visit = MissionControlVisit()
        visit.began(front: at(1, "1:10"))
        visit.ended(at: 100)
        #expect(abs(visit.wait(at: 100) - MissionControlVisit.settleDelay) < 0.001)
        // A move or a focus change late in the settling puts the look off by a beat, at the most.
        #expect(abs(visit.wait(at: 100.3) - MissionControlVisit.beat) < 0.001)
        #expect(abs(visit.wait(at: 101) - MissionControlVisit.beat) < 0.001)
    }

    @Test func aWindowThatCouldntBeParkedAgainIsTriedOnceMoreOnceSettled() {
        var visit = MissionControlVisit()
        let window = UUID()
        visit.began(front: at(1, "1:10"))
        visit.ended(at: 100)
        let first = visit.mayRetry(window, at: 101.4)
        let again = visit.mayRetry(window, at: 101.8)
        let another = visit.mayRetry(UUID(), at: 101.4)
        #expect(first)
        #expect(!again)
        #expect(another)
        // The try is due a settle later, and until then what it left is still its doing.
        #expect(abs(visit.wait(at: 101.4) - MissionControlVisit.settleDelay) < 0.001)
        #expect(visit.isUnderway(at: 101.7))
        #expect(!visit.isUnderway(at: 101.9))
    }

    @Test func eachVisitStartsAfresh() {
        var visit = MissionControlVisit()
        let window = UUID()
        visit.began(front: at(1, "1:10"))
        visit.ended(at: 100)
        let first = visit.mayRetry(window, at: 100.4)
        visit.began(front: at(2, "2:20"))
        #expect(visit.frontAtStart == at(2, "2:20"))
        visit.ended(at: 110)
        let next = visit.mayRetry(window, at: 110.4)
        #expect(first)
        #expect(next)
    }
}
