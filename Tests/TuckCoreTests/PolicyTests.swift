import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Clipboard history policy")
struct ClipboardHistoryTests {
    @Test func isOffUntilEnabled() {
        var history = ClipboardHistory()
        let decision = history.record(text: "hello")
        #expect(decision == .disabled)
        #expect(history.entries.isEmpty)
    }

    @Test func skipsPrivateMarkersAndExcludedApps() {
        var history = ClipboardHistory(isEnabled: true)
        let concealed = history.record(text: "secret", pasteboardTypes: ["org.nspasteboard.ConcealedType"])
        let excluded = history.record(text: "pw", sourceBundleID: "com.1password.1password")
        let empty = history.record(text: "  ")
        #expect(concealed == .concealed)
        #expect(excluded == .excludedApp)
        #expect(empty == .empty)
        #expect(history.entries.isEmpty)
    }

    @Test func reCopiesMoveToTheTopInsteadOfDuplicating() {
        var history = ClipboardHistory(isEnabled: true)
        history.record(text: "a")
        history.record(text: "b")
        let decision = history.record(text: "a")
        #expect(decision == .movedToTop)
        #expect(history.entries.map(\.text) == ["a", "b"])
        #expect(history.entries.first?.copyCount == 2)
    }

    @Test func agesOutByRetentionAndClearsInOneStep() {
        let now = Date()
        var history = ClipboardHistory(isEnabled: true, retention: .oneHour)
        history.record(text: "old", now: now.addingTimeInterval(-7_200))
        history.record(text: "fresh", now: now)
        #expect(history.entries.map(\.text) == ["fresh"])
        history.clear()
        #expect(history.entries.isEmpty)
    }

    @Test func respectsTheEntryCapWhenOneIsExplicitlyProvided() {
        var history = ClipboardHistory(isEnabled: true, maxEntries: 2)
        history.record(text: "1")
        history.record(text: "2")
        history.record(text: "3")
        #expect(history.entries.map(\.text) == ["3", "2"])
    }

    @Test func survivesPersistenceRoundTripWithTheDefaultCap() throws {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        history.record(text: "first")
        history.record(text: "second", sourceBundleID: "com.example.editor", sourceAppName: "Editor")
        let restored = try JSONDecoder().decode(ClipboardHistory.self, from: JSONEncoder().encode(history))
        #expect(restored.entries.map(\.text) == ["second", "first"])
        #expect(restored.entries.first?.sourceAppName == "Editor")
        #expect(restored.maxEntries == ClipboardHistory.defaultMaxEntries)
        #expect(restored == history)
    }

    @Test func keepsTwoHundredByDefaultDroppingTheLeastRecentlyCopied() {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        for number in 1...ClipboardHistory.defaultMaxEntries { history.record(text: "\(number)") }
        // Copying the first again makes "2" the least recently copied.
        history.record(text: "1")
        let decision = history.record(text: "new")
        #expect(decision == .recorded)
        #expect(history.entries.count == 200)
        #expect(history.entries.prefix(2).map(\.text) == ["new", "1"])
        #expect(!history.entries.contains { $0.text == "2" })
        #expect(history.entries.last?.text == "3")
    }

    @Test func aHistorySavedBeforeTheCapIsHeldToIt() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let entries = (0..<250).map { index in
            let copied = start.addingTimeInterval(TimeInterval(-index))
            return ClipboardEntry(text: "entry \(index)", firstCopiedAt: copied, lastCopiedAt: copied)
        }
        let saved = ClipboardHistory(isEnabled: true, retention: .untilCleared, maxEntries: 1_000, entries: entries)
        // Files from before the cap recorded no limit at all.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        object["maxEntries"] = Int.max
        let data = try JSONSerialization.data(withJSONObject: object)

        var restored = try JSONDecoder().decode(ClipboardHistory.self, from: data)
        #expect(restored.maxEntries == ClipboardHistory.defaultMaxEntries)
        restored.prune(now: start)
        #expect(restored.entries.count == 200)
        #expect(restored.entries.first?.text == "entry 0")
        #expect(restored.entries.last?.text == "entry 199")
    }
}

@Suite("Swipe gestures")
struct SwipeGestureTrackerTests {
    @Test func swipingDownOnTheCollapsedSurfaceExpandsOnce() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        #expect(tracker.process(down: 12, right: 0, began: true, ended: false, stage: .collapsed) == nil)
        #expect(tracker.process(down: 12, right: 0, began: false, ended: false, stage: .collapsed) == .expand)
        #expect(tracker.process(down: 30, right: 0, began: false, ended: false, stage: .expanded) == nil)
    }

    @Test func swipingUpTucksTheCollapsedSurfaceAwayAndDownBringsItBack() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        #expect(tracker.process(down: -25, right: 0, began: true, ended: true, stage: .collapsed) == .tuckAway)
        #expect(tracker.process(down: -25, right: 0, began: true, ended: true, stage: .tucked) == nil)
        #expect(tracker.process(down: 25, right: 0, began: true, ended: true, stage: .tucked) == .reveal)
    }

    @Test func swipingDownTheShallowFoldUnfoldsItAndUpFoldsItBack() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        #expect(tracker.process(down: 25, right: 0, began: true, ended: true, stage: .expanded) == .unfold)
        #expect(tracker.process(down: -14, right: 0, began: true, ended: true, stage: .full) == .fold)
        // The full fold is as deep as it goes.
        #expect(tracker.process(down: 40, right: 0, began: true, ended: true, stage: .full) == nil)
    }

    @Test func eachDepthStepsOneWayDownAndOneWayUp() {
        let steps: [(SwipeGestureTracker.Stage, down: SwipeGestureTracker.Action?, up: SwipeGestureTracker.Action?)] = [
            (.tucked, .reveal, nil),
            (.collapsed, .expand, .tuckAway),
            (.expanded, .unfold, .collapse),
            (.full, nil, .fold),
        ]
        for step in steps {
            #expect(SwipeGestureTracker.verticalAction(from: step.0, down: true) == step.down)
            #expect(SwipeGestureTracker.verticalAction(from: step.0, down: false) == step.up)
        }
    }

    @Test func anOpenPanelClosesWithAShorterSwipeUp() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        // Down from the shallow fold unfolds, which takes the full pull: 14 is not enough.
        #expect(tracker.process(down: 14, right: 0, began: true, ended: true, stage: .expanded) == nil)
        #expect(tracker.process(down: -14, right: 0, began: true, ended: true, stage: .expanded) == .collapse)
    }

    @Test func foldingAndClosingTakeAFlickWhileEverythingElseTakesAPull() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        // Upward from an open depth: the close threshold.
        #expect(tracker.process(down: -12, right: 0, began: true, ended: true, stage: .full) == .fold)
        #expect(tracker.process(down: -12, right: 0, began: true, ended: true, stage: .expanded) == .collapse)
        // Opening, deepening, tucking away and bringing back: the vertical threshold.
        for (stage, down) in [(SwipeGestureTracker.Stage.tucked, CGFloat(19)), (.collapsed, 19), (.expanded, 19), (.collapsed, -19)] {
            #expect(tracker.process(down: down, right: 0, began: true, ended: true, stage: stage) == nil)
        }
        #expect(tracker.process(down: 20, right: 0, began: true, ended: true, stage: .tucked) == .reveal)
        #expect(tracker.process(down: 20, right: 0, began: true, ended: true, stage: .collapsed) == .expand)
        #expect(tracker.process(down: 20, right: 0, began: true, ended: true, stage: .expanded) == .unfold)
        #expect(tracker.process(down: -20, right: 0, began: true, ended: true, stage: .collapsed) == .tuckAway)
    }

    @Test func oneGestureTakesOneStepEvenWhenItKeepsGoing() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        #expect(tracker.process(down: -15, right: 0, began: true, ended: false, stage: .expanded) == .collapse)
        #expect(tracker.process(down: -40, right: 0, began: false, ended: false, stage: .collapsed) == nil)
        #expect(tracker.process(down: -40, right: 0, began: true, ended: false, stage: .collapsed) == .tuckAway)
        // Swiping down from the collapsed surface opens the shallow fold, never straight to the full one.
        #expect(tracker.process(down: 25, right: 0, began: true, ended: false, stage: .collapsed) == .expand)
        #expect(tracker.process(down: 60, right: 0, began: false, ended: true, stage: .expanded) == nil)
    }

    @Test func pullFollowsTheFingersTowardsTheNextStage() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        _ = tracker.process(down: -10, right: 0, began: true, ended: false, stage: .collapsed)
        #expect(tracker.pull(stage: .collapsed) == -0.5)
        #expect(tracker.pull(stage: .tucked) == 0)
        _ = tracker.process(down: 15, right: 0, began: false, ended: false, stage: .collapsed)
        #expect(tracker.pull(stage: .collapsed) == 0.25)
        _ = tracker.process(down: 0, right: 0, began: false, ended: true, stage: .collapsed)
        #expect(tracker.pull(stage: .collapsed) == 0)
    }

    @Test func pullMeasuresEachDirectionAgainstItsOwnThreshold() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        _ = tracker.process(down: 10, right: 0, began: true, ended: false, stage: .expanded)
        #expect(tracker.pull(stage: .expanded) == 0.5)
        // Nowhere deeper to go from the full fold.
        #expect(tracker.pull(stage: .full) == 0)
        _ = tracker.process(down: -6, right: 0, began: true, ended: false, stage: .full)
        #expect(tracker.pull(stage: .full) == -0.5)
    }

    @Test func sidewaysSwipesNeverActAtAnyDepth() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        for stage in [SwipeGestureTracker.Stage.tucked, .collapsed, .expanded, .full] {
            for right in [CGFloat(45), -45, 200] {
                #expect(tracker.process(down: 2, right: right, began: true, ended: false, stage: stage) == nil)
                #expect(tracker.axis == .horizontal)
                #expect(tracker.pull(stage: stage) == 0)
                // However far it then goes, sideways stays sideways.
                #expect(tracker.process(down: 0, right: right, began: false, ended: true, stage: stage) == nil)
            }
        }
    }

    @Test func aSidewaysSwipeThatDriftsUpNeverCloses() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        // It starts at a slant, more up than sideways, then carries on sideways: nothing happens, even
        // though it travels further up than a close needs.
        #expect(tracker.process(down: -5, right: -4, began: true, ended: false, stage: .expanded) == nil)
        #expect(tracker.process(down: -4, right: -6, began: false, ended: false, stage: .expanded) == nil)
        #expect(tracker.axis == .horizontal)
        #expect(tracker.process(down: -6, right: -20, began: false, ended: false, stage: .expanded) == nil)
        #expect(tracker.process(down: -3, right: -15, began: false, ended: true, stage: .expanded) == nil)
        // Locked vertical, a swipe up closes even if it then wanders sideways.
        #expect(tracker.process(down: -9, right: 1, began: true, ended: false, stage: .expanded) == nil)
        #expect(tracker.axis == .vertical)
        #expect(tracker.process(down: -6, right: -50, began: false, ended: false, stage: .expanded) == .collapse)
    }

    @Test func theOpenPanelAsksForAClearerVerticalThanTheClosedNotch() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        // A slant just past diagonal counts as vertical on the collapsed surface...
        _ = tracker.process(down: 9, right: 8, began: true, ended: false, stage: .collapsed)
        #expect(tracker.axis == .vertical)
        // ...but in the open panel it has to be half as vertical again as it is sideways.
        _ = tracker.process(down: -9, right: 8, began: true, ended: false, stage: .expanded)
        #expect(tracker.axis == .horizontal)
        _ = tracker.process(down: -13, right: 8, began: true, ended: false, stage: .full)
        #expect(tracker.axis == .vertical)
    }

    /// The fingers' travel for each event of one gesture, routed as the surface routes it, then tracked.
    private func swipe(_ events: [(dx: CGFloat, dy: CGFloat)], overScrollableList: Bool, stage: SwipeGestureTracker.Stage,
                       routing: inout ScrollGestureRouting, tracker: SwipeGestureTracker) -> [SwipeGestureTracker.Action] {
        var actions: [SwipeGestureTracker.Action] = []
        for (index, event) in events.enumerated() {
            let ends = index == events.count - 1
            let route = routing.route(starts: index == 0, ends: ends, overScrollableList: overScrollableList,
                                      dx: event.dx, dy: event.dy)
            guard route.surface else { continue }
            if let action = tracker.process(down: event.dy, right: event.dx, began: route.began, ended: ends,
                                            stage: stage) {
                actions.append(action)
            }
        }
        return actions
    }

    @Test func aSwipeUpOverTheFullFoldsScrollingListScrollsItInsteadOfFolding() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        var routing = ScrollGestureRouting()
        // Clearly vertical and far past the fold threshold, but it started over a list that scrolls.
        let up: [(dx: CGFloat, dy: CGFloat)] = [(0, 0), (0, -6), (1, -10), (0, -14), (0, -20)]
        #expect(swipe(up, overScrollableList: true, stage: .full, routing: &routing, tracker: tracker).isEmpty)
        #expect(routing.owner == .list)
        // The same swipe begun off the list folds.
        #expect(swipe(up, overScrollableList: false, stage: .full, routing: &routing, tracker: tracker) == [.fold])
        #expect(routing.owner == .surface)
    }

    @Test func aGestureThatStartsOverAListScrollsItThroughout() {
        let tracker = SwipeGestureTracker(verticalThreshold: 20, closeThreshold: 12)
        var routing = ScrollGestureRouting()
        let scroll: [(dx: CGFloat, dy: CGFloat)] = [(0, 0), (1, -6), (20, -2), (30, 0), (5, -20)]
        let actions = swipe(scroll, overScrollableList: true, stage: .full, routing: &routing, tracker: tracker)
        #expect(actions.isEmpty)
        #expect(routing.owner == .list)
        // Off the list, a fresh gesture belongs to the surface from its first event.
        let next = routing.route(starts: true, ends: false, overScrollableList: false, dx: 0, dy: 0)
        #expect(next.surface && next.began)
    }

    @Test func ownershipIsDecidedOnceAsTheGestureStarts() {
        var routing = ScrollGestureRouting()
        // Begun over the list, it stays the list's when the pointer leaves it mid-gesture...
        #expect(!routing.route(starts: true, ends: false, overScrollableList: true, dx: 0, dy: -4).surface)
        #expect(!routing.route(starts: false, ends: false, overScrollableList: false, dx: 0, dy: -4).surface)
        #expect(!routing.route(starts: false, ends: true, overScrollableList: false, dx: 0, dy: -4).surface)
        // ...and begun off it, it stays a swipe when the pointer passes over the list, without restarting.
        let first = routing.route(starts: true, ends: false, overScrollableList: false, dx: 0, dy: 4)
        let over = routing.route(starts: false, ends: false, overScrollableList: true, dx: 0, dy: 4)
        #expect(first.surface && first.began)
        #expect(over.surface && !over.began)
        #expect(routing.owner == .surface)
    }

    @Test func aDeviceThatOmitsBeganStillStartsEachGestureAfresh() {
        var routing = ScrollGestureRouting()
        let first = routing.route(starts: false, ends: false, overScrollableList: false, dx: 3, dy: 0)
        let during = routing.route(starts: false, ends: false, overScrollableList: false, dx: 3, dy: 0)
        let last = routing.route(starts: false, ends: true, overScrollableList: false, dx: 3, dy: 0)
        let nextGesture = routing.route(starts: false, ends: false, overScrollableList: false, dx: 3, dy: 0)
        #expect(first.began)
        #expect(!during.began)
        #expect(!last.began)
        #expect(nextGesture.began)
        #expect(routing.isInGesture)
    }
}
