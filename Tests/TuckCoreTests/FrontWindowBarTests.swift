import Foundation
import Testing
@testable import TuckCore

@Suite("The window the fold names")
struct FrontWindowBarTests {
    let safari = AppIdentity(bundleID: "com.apple.Safari", name: "Safari")
    let notes = AppIdentity(bundleID: "com.apple.Notes", name: "Notes")

    func front(_ app: AppIdentity, _ title: String, _ token: String) -> FrontWindowInfo {
        FrontWindowInfo(app: app, title: title, window: WindowToken(token))
    }

    func row(_ app: AppIdentity, _ title: String) -> ParkedWindow {
        ParkedWindow(app: app, title: title, originalFrame: WindowFrame(x: 0, y: 0, width: 800, height: 600))
    }

    @Test func aRenamedWindowIsStillTheSameWindowButAnotherOfItsAppsIsNot() {
        let start = front(safari, "Apple", "1:10")
        #expect(start.isSameWindow(as: front(safari, "Apple – Start Page", "1:10")))
        #expect(!start.isSameWindow(as: front(safari, "Apple", "1:11")))
        #expect(!start.isSameWindow(as: front(notes, "Apple", "1:10")))
        #expect(!start.isSameWindow(as: nil))
        // Without Accessibility no window can be read, and the fold names the app alone.
        #expect(FrontWindowInfo(app: safari, title: "").isSameWindow(as: FrontWindowInfo(app: safari, title: "")))
    }

    @Test func theBarFollowsTheWindowInFrontWhileNothingIsTucked() {
        var bar = FrontWindowBarState()
        bar.show(front(safari, "Apple", "1:10"))
        bar.frontChanged(to: front(notes, "Shopping", "2:20"), byPerson: true)
        #expect(bar.shown == front(notes, "Shopping", "2:20"))
        // Tuck's own moves (an app hidden for a moment) are followed too: the fold names what is in front.
        bar.frontChanged(to: front(safari, "Apple", "1:10"), byPerson: false)
        #expect(bar.shown == front(safari, "Apple", "1:10"))
        bar.frontChanged(to: nil, byPerson: true)
        #expect(bar.shown == nil)
        #expect(!bar.isHeldBlank)
    }

    @Test func onceItsWindowIsTuckedTheBarStaysBlankWhileTuckHandsTheKeyboardOn() {
        var bar = FrontWindowBarState(shown: front(safari, "Apple", "1:10"))
        bar.tuckedFrontWindow()
        #expect(bar.shown == nil)
        #expect(bar.isHeldBlank)
        // The window behind takes the keyboard from the one that went: not named a moment after it went.
        bar.frontChanged(to: front(notes, "Shopping", "2:20"), byPerson: false)
        #expect(bar.shown == nil)
        #expect(bar.isHeldBlank)
    }

    @Test func theNextWindowThePersonBringsForwardFillsTheBlankBar() {
        var bar = FrontWindowBarState(shown: front(safari, "Apple", "1:10"))
        bar.tuckedFrontWindow()
        bar.frontChanged(to: front(notes, "Shopping", "2:20"), byPerson: true)
        #expect(bar.shown == front(notes, "Shopping", "2:20"))
        #expect(!bar.isHeldBlank)
        // From then on the name follows every change again.
        bar.frontChanged(to: front(safari, "Apple", "1:11"), byPerson: false)
        #expect(bar.shown == front(safari, "Apple", "1:11"))
    }

    @Test func readingTheFrontAgainOrBringingAWindowBackLetsGoOfTheBlank() {
        var opened = FrontWindowBarState(shown: front(safari, "Apple", "1:10"))
        opened.tuckedFrontWindow()
        opened.show(front(notes, "Shopping", "2:20"))
        #expect(opened.shown == front(notes, "Shopping", "2:20"))
        #expect(!opened.isHeldBlank)

        var restored = FrontWindowBarState(shown: front(safari, "Apple", "1:10"))
        restored.tuckedFrontWindow()
        restored.windowRestored()
        #expect(restored.shown == nil)
        // The restored window takes the keyboard while Tuck's own moves may still be settling.
        restored.frontChanged(to: front(notes, "Shopping", "2:20"), byPerson: false)
        #expect(restored.shown == front(notes, "Shopping", "2:20"))
    }

    @Test func tuckingTheBarsAppFromThePickerBlanksItAndAnotherAppsLeavesIt() {
        var tuckedItsApp = FrontWindowBarState(shown: front(safari, "Apple", "1:10"))
        tuckedItsApp.tucked([row(notes, "Shopping"), row(safari, "Apple")])
        #expect(tuckedItsApp.shown == nil)
        #expect(tuckedItsApp.isHeldBlank)

        var tuckedOthers = FrontWindowBarState(shown: front(safari, "Apple", "1:10"))
        tuckedOthers.tucked([row(notes, "Shopping")])
        tuckedOthers.tucked([])
        #expect(tuckedOthers.shown == front(safari, "Apple", "1:10"))
        #expect(!tuckedOthers.isHeldBlank)

        // Already blank after a tuck: still held, whatever else is tucked.
        var held = FrontWindowBarState(shown: front(safari, "Apple", "1:10"))
        held.tuckedFrontWindow()
        held.tucked([row(notes, "Shopping")])
        #expect(held.isHeldBlank)
    }

    @Test func aQuitOrBusyAppIsAskedNothingMore() {
        var asked: [String] = []
        func state(_ value: WindowElementState) -> WindowElementState { asked.append("state"); return value }
        func putAway(_ value: Bool) -> Bool { asked.append("putAway"); return value }

        #expect(ShownWindowCheck.classify(appRunning: false, state: state(.alive), isPutAway: putAway(false)) == .closed)
        #expect(asked.isEmpty)
        #expect(ShownWindowCheck.classify(appRunning: true, state: state(.unresponsive), isPutAway: putAway(false)) == .busy)
        #expect(ShownWindowCheck.classify(appRunning: true, state: state(.destroyed), isPutAway: putAway(false)) == .closed)
        #expect(asked == ["state", "state"])
    }

    @Test func nothingToNameInFrontNeverLetsGoOfTheBlank() {
        var bar = FrontWindowBarState(shown: front(safari, "Apple", "1:10"))
        bar.tuckedFrontWindow()
        // An app with no window open, or the tucked window still focused on its way out.
        bar.frontChanged(to: nil, byPerson: true)
        #expect(bar.isHeldBlank)
        bar.frontChanged(to: front(notes, "Shopping", "2:20"), byPerson: true)
        #expect(bar.shown == front(notes, "Shopping", "2:20"))
    }

    @Test func aWindowMissedAfterAReadyCheckIsCheckedAgainForWhy() {
        #expect(ShownWindowCheck.missed(rechecked: .closed) == .closed)
        #expect(ShownWindowCheck.missed(rechecked: .putAway) == .putAway)
        #expect(ShownWindowCheck.missed(rechecked: .stale) == .stale)
        // Ready on the second asking: it didn't answer in time the first.
        #expect(ShownWindowCheck.missed(rechecked: .ready) == .busy)
    }

    @Test func anOpenWindowIsReadyUnlessItIsAlreadyPutAway() {
        #expect(ShownWindowCheck.classify(appRunning: true, state: .alive, isPutAway: false) == .ready)
        // Parked off screen while still its app's focused window, minimised, or hidden with its app.
        #expect(ShownWindowCheck.classify(appRunning: true, state: .alive, isPutAway: true) == .putAway)
    }

    @Test func aTokenFromAnEarlierReadNeverReachesTheWindowNowInFront() {
        let parking = MockWindowParkingService(front: front(notes, "Shopping", "2:20"))
        let shown = WindowToken("1:10")
        #expect(parking.check(shown) == .stale)
        #expect(parking.park(shown) == .noWindow)
        #expect(parking.place(shown, placement: .leftHalf).result == .windowGone)
        #expect(parking.check(WindowToken("2:20")) == .ready)

        parking.front = nil
        #expect(parking.check(WindowToken("2:20")) == .closed)
    }
}

@Suite("Tuck's own changes to the window in front")
struct OwnFrontChangesTests {
    let safari = AppIdentity(bundleID: "com.apple.Safari", name: "Safari")
    let notes = AppIdentity(bundleID: "com.apple.Notes", name: "Notes")
    let mail = AppIdentity(bundleID: "com.apple.mail", name: "Mail")

    func at(_ pid: Int32, _ window: String? = nil) -> OwnFrontChanges.Landing {
        OwnFrontChanges.Landing(pid: pid, window: window.map(WindowToken.init))
    }

    /// Whether the person made a change, as the service asks it after each one the watcher reports.
    func byPerson(_ changes: inout OwnFrontChanges, to landing: OwnFrontChanges.Landing?, at now: TimeInterval) -> Bool {
        changes.changed(to: landing, at: now)
    }

    @Test func aSwitchRightAfterTuckHandsTheKeyboardOnFillsTheBlankBar() {
        var bar = FrontWindowBarState(shown: FrontWindowInfo(app: safari, title: "Apple", window: WindowToken("1:10")))
        var changes = OwnFrontChanges()
        changes.read(at(1, "1:10"))
        bar.tuckedFrontWindow()
        // Safari's window goes and Tuck gives the keyboard to Notes': its own change, let by.
        changes.expect(at(2, "2:20"), at: 100)
        bar.frontChanged(to: FrontWindowInfo(app: notes, title: "Shopping", window: WindowToken("2:20")),
                         byPerson: byPerson(&changes, to: at(2, "2:20"), at: 100.2))
        #expect(bar.shown == nil)
        // A fifth of a second later the person ⌘-Tabs to Mail: theirs, however soon it comes.
        let inbox = FrontWindowInfo(app: mail, title: "Inbox", window: WindowToken("3:30"))
        bar.frontChanged(to: inbox, byPerson: byPerson(&changes, to: at(3, "3:30"), at: 100.4))
        #expect(bar.shown == inbox)
    }

    @Test func anotherWindowOfTheAppTuckGaveTheKeyboardToIsThePersons() {
        var changes = OwnFrontChanges()
        changes.read(at(1, "1:10"))
        changes.expect(at(2, "2:20"), at: 100)
        #expect(byPerson(&changes, to: at(2, "2:21"), at: 100.2))
    }

    @Test func anAppTuckPutBackInFrontCountsWhicheverOfItsWindowsTakesFocus() {
        var changes = OwnFrontChanges()
        changes.read(at(1, "1:10"))
        changes.expect(at(1), at: 100)
        #expect(!byPerson(&changes, to: at(1, "1:11"), at: 100.3))
        // A window that couldn't be read (its app slow to answer) is taken to be the one expected.
        changes.expect(at(2, "2:20"), at: 101)
        #expect(!byPerson(&changes, to: at(2), at: 101.2))
    }

    @Test func aChangeThatLeavesTheFrontWhereItWasBringsNothingForward() {
        var changes = OwnFrontChanges()
        changes.read(at(1, "1:10"))
        // A rename, long after any move of Tuck's.
        #expect(!byPerson(&changes, to: at(1, "1:10"), at: 500))
        #expect(byPerson(&changes, to: at(2, "2:20"), at: 500.2))
        #expect(changes.front == at(2, "2:20"))
        // Tuck never expects the front to be left empty.
        #expect(byPerson(&changes, to: nil, at: 500.4))
    }

    @Test func whatTuckExpectedLapsesOnceItsMomentHasPassed() {
        var changes = OwnFrontChanges()
        changes.read(at(1, "1:10"))
        changes.expect(at(2, "2:20"), at: 100)
        #expect(byPerson(&changes, to: at(2, "2:20"), at: 100 + OwnFrontChanges.span))
    }
}
