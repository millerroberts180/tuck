import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Shallow fold strip gestures")
struct StripGestureTests {
    /// What one gesture did: the swipe's actions, and how far the strip was scrolled sideways.
    private struct Outcome {
        var actions: [SwipeGestureTracker.Action] = []
        var stripTravel: CGFloat = 0
    }

    /// The fingers' travel for each event of one gesture, routed as the surface routes it: events held
    /// back are replayed to the strip or to the swipe once the gesture's axis shows.
    private func gesture(_ events: [(dx: CGFloat, dy: CGFloat)], region: ScrollGestureRouting.Region,
                         stage: SwipeGestureTracker.Stage = .expanded,
                         routing: inout ScrollGestureRouting) -> Outcome {
        let tracker = SwipeGestureTracker()
        var outcome = Outcome()
        var held: [(dx: CGFloat, dy: CGFloat)] = []
        func swipe(_ event: (dx: CGFloat, dy: CGFloat), began: Bool, ended: Bool) {
            if let action = tracker.process(down: event.dy, right: event.dx, began: began, ended: ended, stage: stage) {
                outcome.actions.append(action)
            }
        }
        for (index, event) in events.enumerated() {
            let ends = index == events.count - 1
            switch routing.route(starts: index == 0, ends: ends, region: region, dx: event.dx, dy: event.dy) {
            case .swipe(let began):
                swipe(event, began: began, ended: ends)
            case .passOn:
                outcome.stripTravel += event.dx
            case .hold:
                held.append(event)
            case .swipeHeld:
                for (offset, earlier) in (held + [event]).enumerated() {
                    swipe(earlier, began: offset == 0, ended: ends && offset == held.count)
                }
                held = []
            case .passOnHeld:
                outcome.stripTravel += (held + [event]).reduce(0) { $0 + $1.dx }
                held = []
            }
        }
        return outcome
    }

    @Test func aSidewaysSwipeOverTheStripScrollsItAndNeverDeepens() {
        var routing = ScrollGestureRouting()
        let sideways: [(dx: CGFloat, dy: CGFloat)] = [(0, 0), (-3, 0), (-6, 1), (-12, 0), (-30, 2), (-40, 0)]
        let outcome = gesture(sideways, region: .strip, routing: &routing)
        #expect(outcome.actions.isEmpty)
        #expect(routing.owner == .strip)
        // Every point of it reaches the strip, the events held back while its axis showed included.
        #expect(outcome.stripTravel == -91)
    }

    @Test func aSidewaysSwipeThatTurnsDownStillOnlyScrollsTheStrip() {
        var routing = ScrollGestureRouting()
        let turning: [(dx: CGFloat, dy: CGFloat)] = [(0, 0), (-5, 0), (-6, 1), (0, 20), (0, 40), (1, 30)]
        #expect(gesture(turning, region: .strip, routing: &routing).actions.isEmpty)
        #expect(routing.owner == .strip)
    }

    @Test func aSwipeDownOverTheStripDeepensTheFold() {
        var routing = ScrollGestureRouting()
        let down: [(dx: CGFloat, dy: CGFloat)] = [(0, 0), (0, 3), (1, 6), (0, 10), (0, 20)]
        let outcome = gesture(down, region: .strip, routing: &routing)
        #expect(outcome.actions == [.unfold])
        #expect(outcome.stripTravel == 0)
        #expect(routing.owner == .surface)
    }

    @Test func aSwipeUpOverTheStripFoldsAway() {
        var routing = ScrollGestureRouting()
        let up: [(dx: CGFloat, dy: CGFloat)] = [(0, -4), (0, -6), (0, -10)]
        #expect(gesture(up, region: .strip, routing: &routing).actions == [.collapse])
    }

    @Test func aDiagonalFollowsTheAxisItStartsAlong() {
        var routing = ScrollGestureRouting()
        // Mostly down as it starts, then sideways: a swipe, which deepens.
        let downFirst: [(dx: CGFloat, dy: CGFloat)] = [(2, 6), (2, 6), (20, 8), (30, 4)]
        #expect(gesture(downFirst, region: .strip, routing: &routing).actions == [.unfold])
        #expect(routing.owner == .surface)
        // Even parts down and sideways is not clearly vertical, as for any swipe in the open fold: the strip's.
        let even: [(dx: CGFloat, dy: CGFloat)] = [(5, 5), (5, 5), (0, 30), (0, 30)]
        let outcome = gesture(even, region: .strip, routing: &routing)
        #expect(outcome.actions.isEmpty)
        #expect(outcome.stripTravel == 10)
        #expect(routing.owner == .strip)
    }

    @Test func eventsAreHeldBackOnlyUntilTheAxisShows() {
        var routing = ScrollGestureRouting()
        #expect(routing.route(starts: true, ends: false, region: .strip, dx: -3, dy: 0) == .hold)
        #expect(routing.isHolding)
        #expect(routing.route(starts: false, ends: false, region: .strip, dx: -3, dy: 1) == .hold)
        #expect(routing.route(starts: false, ends: false, region: .strip, dx: -3, dy: 0) == .passOnHeld)
        #expect(!routing.isHolding)
        #expect(routing.route(starts: false, ends: false, region: .surface, dx: 0, dy: 30) == .passOn)
        #expect(routing.route(starts: false, ends: true, region: .surface, dx: 0, dy: 30) == .passOn)
        // The next gesture, off the strip, is a swipe from its first event.
        #expect(routing.route(starts: true, ends: false, region: .surface, dx: 0, dy: 2) == .swipe(began: true))
    }

    @Test func aTouchTooShortToShowAnAxisIsASwipeThatWentNowhere() {
        var routing = ScrollGestureRouting()
        #expect(routing.route(starts: true, ends: false, region: .strip, dx: 1, dy: 1) == .hold)
        #expect(routing.route(starts: false, ends: true, region: .strip, dx: 1, dy: 2) == .swipeHeld)
        #expect(!routing.isHolding && !routing.isInGesture)
        var tap = ScrollGestureRouting()
        #expect(gesture([(1, 1), (1, 2)], region: .strip, routing: &tap).actions.isEmpty)
    }

    @Test func theFullFoldsListAndTheRestOfTheSurfaceRouteAsBefore() {
        var routing = ScrollGestureRouting()
        #expect(routing.route(starts: true, ends: false, region: .scrollableList, dx: 0, dy: -4) == .passOn)
        #expect(routing.owner == .list)
        #expect(routing.route(starts: true, ends: false, region: .surface, dx: -9, dy: 0) == .swipe(began: true))
        #expect(routing.owner == .surface)
    }
}
