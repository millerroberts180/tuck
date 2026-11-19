import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Setup tour")
struct SetupTourTests {
    @Test func theLoopIsTickedOffInOrderAndEachMoveCountsOnce() {
        var desk = TourDesk()
        #expect(desk.next == .open)

        desk.toggle()
        #expect(desk.isOpen && !desk.isFull)
        #expect(desk.next == .tuck)

        let tucked = desk.tuckWindow()
        let tuckedAgain = desk.tuckWindow()
        #expect(tucked && !tuckedAgain)
        #expect(desk.isWindowTucked && desk.next == .hold)

        let held = desk.holdFile()
        #expect(held && desk.isFileHeld && desk.count == 2)
        #expect(desk.next == .bringBack)

        let restored = desk.restoreWindow()
        #expect(restored && !desk.isWindowTucked && desk.count == 1)
        #expect(desk.next == nil)
        #expect(desk.done == Set(TourDesk.Move.allCases))
        #expect(desk.latest == .bringBack)
        // Clicks and buttons never tick off a gesture.
        #expect(desk.tried.isEmpty)
    }

    @Test func tuckingAndRestoringNeedTheOpenPanel() {
        var desk = TourDesk()
        let tuckedClosed = desk.tuckWindow()
        let restoredNothing = desk.restoreWindow()
        #expect(!tuckedClosed && !restoredNothing)
        desk.open()
        desk.tuckWindow()
        desk.close()
        let restoredClosed = desk.restoreWindow()
        #expect(!restoredClosed && desk.isWindowTucked)
    }

    @Test func theFullFoldIsOpenToo() {
        var desk = TourDesk()
        desk.apply(.expand)
        desk.apply(.unfold)
        #expect(desk.isFull && desk.isOpen)
        let tucked = desk.tuckWindow()
        let restored = desk.restoreWindow()
        #expect(tucked && restored)
        // A click on the notch closes either depth.
        desk.toggle()
        #expect(desk.stage == .collapsed && !desk.isOpen)
    }

    @Test func theStreamListsTheNewestFirst() {
        var desk = TourDesk()
        desk.holdFile()
        desk.open()
        desk.tuckWindow()
        #expect(desk.stream == [.window, .file] && desk.count == 2)
        desk.restoreWindow()
        #expect(desk.stream == [.file] && !desk.isWindowTucked && desk.isFileHeld)
        desk.tuckWindow()
        #expect(desk.stream == [.window, .file])
    }

    @Test func aLensNarrowsTheShallowFoldUntilSomethingArrives() {
        var desk = TourDesk()
        desk.holdFile()
        desk.toggleLens(.files)
        #expect(desk.lens == nil)
        desk.open()
        desk.toggleLens(.windows)
        #expect(desk.lens == .windows && desk.rows.isEmpty)
        desk.toggleLens(.files)
        #expect(desk.rows == [.file])
        // The window arrives at the top, and the lens that would hide it is let go.
        desk.tuckWindow()
        #expect(desk.lens == nil && desk.rows == [.window, .file])
        desk.toggleLens(.windows)
        desk.toggleLens(.windows)
        #expect(desk.lens == nil)
        // The full fold always shows everything, and so does the fold opened again.
        desk.toggleLens(.files)
        desk.apply(.unfold)
        #expect(desk.lens == nil)
        desk.toggleLens(.files)
        #expect(desk.lens == nil)
        desk.apply(.fold)
        desk.toggleLens(.files)
        desk.close()
        desk.open()
        #expect(desk.lens == nil && desk.rows.count == 2)
    }

    @Test func aHeldFileIsDraggedOutIntoTheNoteAndStaysHeld() {
        var desk = TourDesk()
        let held = desk.holdFile()
        let heldAgain = desk.holdFile()
        #expect(held && !heldAgain && !desk.isOpen)
        desk.open()
        let attached = desk.attachFile()
        #expect(attached && desk.isAttached && desk.isFileHeld)
        #expect(desk.done.contains(.bringBack))
    }

    @Test func theNoteMustBeOnTheDeskToTakeTheFile() {
        var desk = TourDesk()
        desk.open()
        desk.tuckWindow()
        desk.holdFile()
        let attached = desk.attachFile()
        #expect(!attached && !desk.isAttached)
    }

    @Test func aDropOnTheTuckedAwayNotchBringsItBack() {
        var desk = TourDesk()
        desk.apply(.tuckAway)
        #expect(desk.isTuckedAway)
        let held = desk.holdFile()
        #expect(held && desk.stage == .collapsed && desk.count == 1)
    }

    // MARK: The screen's geometry, with Tuck's real drop and flight logic

    @Test func theFileStartsWithAFaintInvitationAndDoesNotOpenThePanel() {
        let zone = TourLayout.zone
        let level = DropApproach.invitation(pointer: TourLayout.file, zone: zone, wasInviting: false)
        #expect(level != nil)
        #expect((level ?? .max) < DropApproach.levels / 2)
        #expect(!DropApproach.isArmed(pointer: TourLayout.file, zone: zone, wasArmed: false))
    }

    @Test func theNotchTakesTheDropAndBesideItIsRefused() {
        let zone = TourLayout.zone
        let surface = TourLayout.surface
        #expect(DropApproach.invitation(pointer: CGPoint(x: surface.midX, y: surface.midY), zone: zone,
                                        wasInviting: true) == DropApproach.levels)
        let beside = CGPoint(x: surface.maxX + 60, y: surface.midY)
        #expect((DropApproach.invitation(pointer: beside, zone: zone, wasInviting: true) ?? 0) < DropApproach.levels)
    }

    @Test func theDeskKeepsTheWindowAndFileClearOfTheNotchAndTheFold() {
        let fold = TourLayout.panel(height: TourLayout.size.height)
        #expect(TourLayout.bounds.contains(TourLayout.window))
        #expect(!TourLayout.window.intersects(TourLayout.surface))
        #expect(!TourLayout.window.intersects(fold))
        #expect(!fold.contains(TourLayout.file))
        #expect(!TourLayout.window.contains(TourLayout.file))
        #expect(TourLayout.surface.contains(TourLayout.notch))
    }

    @Test func aDepositLandsInTheMarkClosedAndOnTheTopRowOpen() {
        // Closed: the middle of the left wing, beside the notch.
        let mark = TourLayout.landing(open: false)
        #expect(TourLayout.surface.contains(mark) && !TourLayout.notch.contains(mark))
        #expect(mark.x < TourLayout.notch.minX)
        // Open: the first row's icon, under the band and inside the fold, rows going down from there.
        let fold = TourLayout.panel(height: TourLayout.listTop + TourLayout.rowHeight * 2)
        let top = TourLayout.landing(open: true)
        #expect(fold.contains(top) && top.y < TourLayout.notch.minY)
        #expect(top.x - TourLayout.rowIconSize / 2 == fold.minX + TourLayout.rowIconInset)
        #expect(TourLayout.landing(open: true, row: 1).y == top.y - TourLayout.rowHeight)
    }

    @Test func theWindowRisesIntoWhatItLandsOn() {
        for open in [false, true] {
            let flight = TourLayout.flight(open: open)
            let end = flight.point(at: 1)
            #expect(abs(end.x - TourLayout.landing(open: open).x) < 0.001)
            #expect(abs(end.y - TourLayout.landing(open: open).y) < 0.001)
            // It arrives the size of what it lands on: the row's icon, or the mark's line.
            #expect(flight.endSize == (open ? TourLayout.rowIconSize : TourLayout.markStroke))
            // It starts on the window itself, and goes up first, then across.
            #expect(abs(flight.point(at: 0).x - TourLayout.window.midX) < 0.001)
            #expect(flight.point(at: 0.5).y > TourLayout.window.midY + 40)
        }
        // Coming back from a lower row, it leaves from that row's icon.
        #expect(TourLayout.flight(open: true, row: 1).target == TourLayout.rowIcon(1))
    }

    // MARK: Gestures, through the real swipe tracker

    /// One two-finger swipe: a few events of travel, then the fingers lift. Returns what each action it
    /// committed changed on the desk.
    private func swipe(_ desk: inout TourDesk, tracker: SwipeGestureTracker,
                       down: CGFloat = 0, right: CGFloat = 0) -> [Bool] {
        var changed: [Bool] = []
        for index in 0..<10 {
            if let action = tracker.process(down: down, right: right, began: index == 0, ended: index == 9,
                                            stage: desk.stage) {
                changed.append(desk.apply(action))
            }
        }
        return changed
    }

    @Test func eachSwipeDoesOneThingAndEveryGestureIsTicked() {
        let tracker = SwipeGestureTracker()
        var desk = TourDesk()

        #expect(swipe(&desk, tracker: tracker, down: 6) == [true])
        #expect(desk.stage == .expanded && desk.done.contains(.open))
        #expect(desk.latestGesture == .open)
        #expect(swipe(&desk, tracker: tracker, down: 6) == [true])
        #expect(desk.isFull && desk.latestGesture == .unfold)
        // Folding back to the shallow fold isn't taught; closing is.
        #expect(swipe(&desk, tracker: tracker, down: -6) == [true])
        #expect(desk.stage == .expanded && desk.tried == [.open, .unfold])
        #expect(swipe(&desk, tracker: tracker, down: -6) == [true])
        #expect(desk.stage == .collapsed && desk.latestGesture == .close)
        #expect(desk.tried == Set(TourDesk.Gesture.allCases))
    }

    @Test func untaughtSwipesStillWorkButTickNothing() {
        let tracker = SwipeGestureTracker()
        var desk = TourDesk()

        #expect(swipe(&desk, tracker: tracker, down: -6) == [true])
        #expect(desk.isTuckedAway)
        #expect(swipe(&desk, tracker: tracker, down: 6) == [true])
        #expect(desk.stage == .collapsed)
        #expect(desk.tried.isEmpty && desk.latestGesture == nil)
    }

    @Test func sidewaysSwipesDoNothing() {
        let tracker = SwipeGestureTracker()
        var desk = TourDesk()
        for pass in 0..<2 {
            #expect(swipe(&desk, tracker: tracker, right: 8).isEmpty)
            #expect(swipe(&desk, tracker: tracker, right: -8).isEmpty)
            #expect(desk.stage == (pass == 0 ? .collapsed : .expanded))
            desk.open()
        }
        #expect(desk.tried.isEmpty)
    }

    @Test func swipesThatChangeNothingCountForNothing() {
        var desk = TourDesk()
        // Collapsed: nothing to fold, unfold, collapse or bring back.
        for action in [SwipeGestureTracker.Action.fold, .unfold, .collapse, .reveal] {
            let changed = desk.apply(action)
            #expect(!changed, "\(action)")
        }
        #expect(desk.stage == .collapsed)
        desk.open()
        // Open: already expanded, can't be tucked away or folded further.
        for action in [SwipeGestureTracker.Action.expand, .tuckAway, .fold, .reveal] {
            let changed = desk.apply(action)
            #expect(!changed, "\(action)")
        }
        #expect(desk.stage == .expanded && desk.tried.isEmpty)
        desk.apply(.unfold)
        let unfoldedAgain = desk.apply(.unfold)
        #expect(!unfoldedAgain && desk.tried == [.unfold])
    }

    @Test func aClickBringsBackATuckedAwayNotchWithoutTickingIt() {
        var desk = TourDesk()
        desk.apply(.tuckAway)
        desk.toggle()
        #expect(desk.stage == .collapsed)
        #expect(desk.tried.isEmpty)
        desk.toggle()
        #expect(desk.isOpen && !desk.tried.contains(.open))
    }
}
