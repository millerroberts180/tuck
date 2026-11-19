import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

/// Frames here are Quartz global coordinates: y grows downwards from the top of the primary display.
@Suite("Parking windows off screen")
struct OffScreenParkingTests {
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let window = CGSize(width: 800, height: 600)

    @Test func aWindowWaitsJustBeyondTheBottomRightCornerOfItsDisplay() {
        let origin = OffScreenParking.origin(for: window, preferring: laptop, displays: [laptop])
        #expect(origin == CGPoint(x: 1511, y: 981))
    }

    @Test func aDisplayToTheRightSendsItBeyondTheBottomLeftCornerInstead() {
        let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let origin = OffScreenParking.origin(for: window, preferring: laptop, displays: [laptop, right])
        #expect(origin == CGPoint(x: -799, y: 981))
    }

    @Test func withDisplaysOnBothSidesItWaitsBeyondAnOuterCornerOfAnother() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let right = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let origin = OffScreenParking.origin(for: window, preferring: laptop, displays: [left, laptop, right])
        #expect(origin == CGPoint(x: -2719, y: 1079))
    }

    @Test func aWindowOnADisplayToTheLeftWaitsBeyondThatDisplaysOuterCorner() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let origin = OffScreenParking.origin(for: window, preferring: left, displays: [laptop, left])
        #expect(origin == CGPoint(x: -2719, y: 1079))
    }

    @Test func aDisplayBelowAnotherKeepsWindowsOffItsCorners() {
        // Directly above and as wide: anything beyond its bottom corners would show down the laptop's edge.
        let above = CGRect(x: 0, y: -1080, width: 1512, height: 1080)
        let origin = OffScreenParking.origin(for: window, preferring: above, displays: [laptop, above])
        #expect(origin == CGPoint(x: 1511, y: 981))
        // Wider and offset, its bottom-right corner lies clear of the laptop.
        let offset = CGRect(x: -204, y: -1080, width: 1920, height: 1080)
        let clear = OffScreenParking.origin(for: window, preferring: offset, displays: [laptop, offset])
        #expect(clear == CGPoint(x: 1715, y: -1))
    }

    @Test func withoutDisplaysThereIsNowhereToWait() {
        let origin = OffScreenParking.origin(for: window, preferring: nil, displays: [])
        #expect(origin == nil)
    }

    @Test func onlyASliverAlongAnEdgeCountsAsOutOfSight() {
        let inView = OffScreenParking.isOutOfSight(CGRect(x: 100, y: 100, width: 800, height: 600), displays: [laptop])
        #expect(!inView)
        // What macOS keeps on screen of a parked window: one point across, its title bar's height down.
        let parked = OffScreenParking.isOutOfSight(CGRect(x: 1511, y: 954, width: 800, height: 600), displays: [laptop])
        #expect(parked)
        let tallStrip = OffScreenParking.isOutOfSight(CGRect(x: 1511, y: 100, width: 800, height: 800), displays: [laptop])
        #expect(!tallStrip)
        // Where macOS holds a window pushed beyond a side: about 40 points still show.
        let heldBack = OffScreenParking.isOutOfSight(CGRect(x: 1472, y: 100, width: 800, height: 600), displays: [laptop])
        #expect(!heldBack)
        let beyond = OffScreenParking.isOutOfSight(CGRect(x: 2000, y: 2000, width: 800, height: 600), displays: [laptop])
        #expect(beyond)
        let unknown = OffScreenParking.isOutOfSight(CGRect(x: 2000, y: 2000, width: 800, height: 600), displays: [])
        #expect(!unknown)
    }

    @Test func aWindowWithNothingLeftOnAnyDisplayIsParkedAgain() {
        let parked = OffScreenParking.isParked(CGRect(x: 1511, y: 954, width: 800, height: 600), displays: [laptop])
        #expect(parked)
        // After its display was removed, say: macOS would soon pull it back into view.
        let stranded = OffScreenParking.isParked(CGRect(x: 2000, y: 2000, width: 800, height: 600), displays: [laptop])
        #expect(!stranded)
        let inView = OffScreenParking.isParked(CGRect(x: 100, y: 100, width: 800, height: 600), displays: [laptop])
        #expect(!inView)
    }

    // A parked window that moved or changed size without Tuck moving it (Mission Control ending, its app
    // resizing it), as `drift` judges it.
    let parked = CGRect(x: 1511, y: 954, width: 800, height: 600)
    let backInView = CGRect(x: 356, y: 191, width: 800, height: 600)

    @Test func aParkedWindowThatOnlyChangedSizeStaysWhereItIs() {
        let resized = CGRect(x: 1511, y: 954, width: 1024, height: 768)
        let drift = OffScreenParking.drift(of: resized, displays: [laptop], inFront: false, parkedAgain: [], now: 100)
        #expect(drift == .stays)
        #expect(OffScreenParking.drift(of: parked, displays: [laptop], inFront: false, parkedAgain: [], now: 100) == .stays)
    }

    @Test func aWindowBackInViewByItselfIsParkedAgain() {
        let drift = OffScreenParking.drift(of: backInView, displays: [laptop], inFront: false, parkedAgain: [], now: 100)
        #expect(drift == .parkAgain)
        // Left with nothing on any display, macOS would soon pull it back into view.
        let stranded = CGRect(x: 2000, y: 2000, width: 800, height: 600)
        #expect(OffScreenParking.drift(of: stranded, displays: [laptop], inFront: false, parkedAgain: [], now: 100) == .parkAgain)
    }

    @Test func aWindowThePersonHasInFrontIsLeftToThem() {
        // They went to it, or dragged it back by its sliver: the focus watcher brings it back or lets it go.
        let drift = OffScreenParking.drift(of: backInView, displays: [laptop], inFront: true, parkedAgain: [], now: 100)
        #expect(drift == .stays)
    }

    @Test func aWindowItsAppKeepsPullingBackIsMinimised() {
        let once = OffScreenParking.drift(of: backInView, displays: [laptop], inFront: false, parkedAgain: [99.5], now: 100)
        #expect(once == .parkAgain)
        let twice = OffScreenParking.drift(of: backInView, displays: [laptop], inFront: false, parkedAgain: [99, 99.5],
                                           now: 100)
        #expect(twice == .minimise)
    }

    @Test func pullBacksLongAgoDontCount() {
        // Mission Control ending now and then, each time with a pull-back, parks it again each time.
        let drift = OffScreenParking.drift(of: backInView, displays: [laptop], inFront: false, parkedAgain: [40, 97.5],
                                           now: 100)
        #expect(drift == .parkAgain)
    }

    @Test func withoutDisplaysNothingIsDone() {
        let drift = OffScreenParking.drift(of: backInView, displays: [], inFront: false, parkedAgain: [], now: 100)
        #expect(drift == .stays)
    }

    @Test func afterMissionControlAWindowBackInViewIsParkedAgainEvenWithTheKeyboardInIt() {
        let drift = OffScreenParking.driftAfterMissionControl(of: backInView, displays: [laptop], chosen: false)
        #expect(drift == .parkAgain)
        #expect(OffScreenParking.driftAfterMissionControl(of: parked, displays: [laptop], chosen: false) == .stays)
        #expect(OffScreenParking.driftAfterMissionControl(of: backInView, displays: [], chosen: false) == .stays)
    }

    @Test func aWindowChosenInMissionControlComesBack() {
        // Wherever Mission Control left it, it comes back where it was, as from its app's Dock icon.
        #expect(OffScreenParking.driftAfterMissionControl(of: backInView, displays: [laptop], chosen: true) == .bringBack)
        #expect(OffScreenParking.driftAfterMissionControl(of: parked, displays: [laptop], chosen: true) == .bringBack)
    }

    let leaving = OffScreenParking.ListedWindow(pid: 1, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
    let otherApp = OffScreenParking.ListedWindow(pid: 2, frame: CGRect(x: 200, y: 200, width: 800, height: 600))
    let sibling = OffScreenParking.ListedWindow(pid: 1, frame: CGRect(x: 300, y: 300, width: 700, height: 500))
    let palette = OffScreenParking.ListedWindow(pid: 1, frame: CGRect(x: 40, y: 40, width: 50, height: 50))
    let parkedEarlier = OffScreenParking.ListedWindow(pid: 1, frame: CGRect(x: 1511, y: 954, width: 800, height: 600))

    @Test func theKeyboardGoesToTheAppsNextWindowFirst() {
        let next = OffScreenParking.successor(to: 1, leaving: [leaving], in: [leaving, otherApp, palette, sibling],
                                              displays: [laptop])
        #expect(next == sibling)
    }

    @Test func otherwiseToTheFrontmostWindowInView() {
        let next = OffScreenParking.successor(to: 1, leaving: [leaving], in: [leaving, palette, parkedEarlier, otherApp],
                                              displays: [laptop])
        #expect(next == otherApp)
    }

    @Test func aWindowStillListedWhereItWasIsNeverTheOneToTakeTheKeyboard() {
        // The window server's list can lag the move by a moment, a point or so out.
        let lagging = OffScreenParking.ListedWindow(pid: 1, frame: CGRect(x: 101, y: 100, width: 800, height: 600))
        let next = OffScreenParking.successor(to: 1, leaving: [leaving], in: [lagging, otherApp], displays: [laptop])
        #expect(next == otherApp)
    }

    @Test func nothingElseInViewMeansNoWindowTakesTheKeyboard() {
        let next = OffScreenParking.successor(to: 1, leaving: [leaving], in: [leaving, palette, parkedEarlier],
                                              displays: [laptop])
        #expect(next == nil)
    }

    @Test func windowsParkedOffScreenAreRecordedAsSuch() throws {
        let row = ParkedWindow(app: AppIdentity(bundleID: "com.apple.Notes", name: "Notes"), title: "Shopping",
                               originalFrame: WindowFrame(x: 0, y: 0, width: 800, height: 600), method: .offScreen)
        #expect(row.isOffScreen)
        #expect(!row.isHiddenWithApp)
        let decoded = try JSONDecoder().decode(ParkedWindow.self, from: JSONEncoder().encode(row))
        #expect(decoded.method == .offScreen)
    }

    @Test func rowsSavedByEarlierVersionsStillRestoreAsBefore() throws {
        let old = ParkedWindow(app: AppIdentity(bundleID: "com.apple.Notes", name: "Notes"), title: "Shopping",
                               originalFrame: WindowFrame(x: 0, y: 0, width: 800, height: 600))
        let decoded = try JSONDecoder().decode(ParkedWindow.self, from: JSONEncoder().encode(old))
        #expect(decoded.method == nil)
        #expect(!decoded.isOffScreen)
        var hidden = old
        hidden.method = .hiddenWithApp
        let decodedHidden = try JSONDecoder().decode(ParkedWindow.self, from: JSONEncoder().encode(hidden))
        #expect(decodedHidden.isHiddenWithApp)
    }
}
