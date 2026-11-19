import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

func candidate(_ id: String, app: String = "Notes", pid: Int32 = 10, order: Int = 0, subrole: String? = "AXStandardWindow",
               minimised: Bool = false, fullScreen: Bool = false, onScreen: Bool = true, regular: Bool = true,
               own: Bool = false, resting: Bool = false, size: CGSize = CGSize(width: 800, height: 600)) -> WindowCandidate {
    WindowCandidate(id: id, app: AppIdentity(bundleID: "com.example.\(app)", name: app), pid: pid, title: id,
                    frame: CGRect(origin: .zero, size: size), subrole: subrole, isMinimised: minimised,
                    isFullScreen: fullScreen, isOnScreen: onScreen, isRegularApp: regular, isOwnApp: own,
                    isAppResting: resting, stackOrder: order)
}

@Suite("Window candidates")
struct WindowCandidateTests {
    @Test func onlyOrdinaryVisibleStandardWindowsAreOffered() {
        #expect(CandidatePolicy.exclusion(for: candidate("ok")) == nil)
        #expect(CandidatePolicy.exclusion(for: candidate("tuck", own: true)) == .tuckItself)
        #expect(CandidatePolicy.exclusion(for: candidate("agent", regular: false)) == .backgroundApp)
        #expect(CandidatePolicy.exclusion(for: candidate("rested", resting: true)) == .resting)
        #expect(CandidatePolicy.exclusion(for: candidate("dialog", subrole: "AXDialog")) == .notStandardWindow)
        #expect(CandidatePolicy.exclusion(for: candidate("panel", subrole: "AXFloatingWindow")) == .notStandardWindow)
        #expect(CandidatePolicy.exclusion(for: candidate("unknown", subrole: nil)) == .notStandardWindow)
        #expect(CandidatePolicy.exclusion(for: candidate("docked", minimised: true)) == .minimised)
        #expect(CandidatePolicy.exclusion(for: candidate("full", fullScreen: true)) == .fullScreen)
        #expect(CandidatePolicy.exclusion(for: candidate("elsewhere", onScreen: false)) == .offScreen)
        #expect(CandidatePolicy.exclusion(for: candidate("tiny", size: CGSize(width: 60, height: 40))) == .tooSmall)
    }

    @Test func suggestionsAreFrontFirstAndCapped() {
        let all = (0..<20).map { candidate("w\($0)", order: 19 - $0) } + [candidate("hidden", order: -1, minimised: true)]
        let offered = CandidatePolicy.suggestions(from: all)
        #expect(offered.count == CandidatePolicy.limit)
        #expect(offered.first?.id == "w19")
        #expect(!offered.contains { $0.id == "hidden" })
    }

    @Test func groupsFollowEachAppsFrontMostWindow() {
        let offered = [candidate("a1", app: "A", pid: 1, order: 0), candidate("b1", app: "B", pid: 2, order: 1),
                       candidate("a2", app: "A", pid: 1, order: 2)]
        let groups = CandidatePolicy.groupedByApp(offered)
        #expect(groups.map(\.pid) == [1, 2])
        #expect(groups.first?.windows.map(\.id) == ["a1", "a2"])
    }

    @Test func aRowsTitleUnderTheAppSaysSomethingNew() {
        func titled(_ title: String, app: String = "Safari") -> WindowCandidate {
            WindowCandidate(id: "w", app: AppIdentity(bundleID: "com.example.\(app)", name: app), pid: 1, title: title,
                            frame: CGRect(x: 0, y: 0, width: 800, height: 600), subrole: "AXStandardWindow", stackOrder: 0)
        }
        #expect(titled("Apple – Start Page").pageTitle == "Apple – Start Page")
        #expect(titled("  Groceries ", app: "Notes").pageTitle == "Groceries")
        #expect(titled("").pageTitle == nil)
        #expect(titled("   ").pageTitle == nil)
        #expect(titled("Music", app: "Music").pageTitle == nil)
        #expect(titled("calendar", app: "Calendar").pageTitle == nil)
    }
}

@Suite("Selecting windows")
struct WindowSelectionTests {
    let group = CandidateGroup(app: AppIdentity(bundleID: "com.example.A", name: "A"), pid: 1,
                               windows: [candidate("a1", pid: 1), candidate("a2", pid: 1)])

    @Test func nothingIsTickedUntilChosen() {
        let selection = WindowSelection()
        #expect(selection.isEmpty)
        #expect(selection.actionTitle == "Tuck")
    }

    @Test func tickingNamesTheAction() {
        var selection = WindowSelection()
        selection.toggle("a1")
        selection.toggle("b1")
        selection.toggle("c1")
        #expect(selection.actionTitle == "Tuck 3")
        selection.toggle("b1")
        #expect(selection.count == 2)
        #expect(!selection.isSelected("b1"))
    }

    @Test func aWholeAppCanBeTickedAndUnticked() {
        var selection = WindowSelection()
        selection.toggle("a1")
        selection.toggleAll(in: group)
        #expect(selection.allSelected(in: group))
        selection.toggleAll(in: group)
        #expect(selection.isEmpty)
    }

    @Test func anAppCountsOnlyItsOwnTickedWindows() {
        var selection = WindowSelection()
        selection.toggle("a2")
        selection.toggle("b1")
        #expect(selection.count(in: group) == 1)
        selection.toggleAll(in: group)
        #expect(selection.count(in: group) == 2)
        #expect(selection.count == 3)
    }

    @Test func windowsThatCloseDropOutOfTheSelection() {
        var selection = WindowSelection()
        selection.toggle("a1")
        selection.toggle("gone")
        selection.keepOnly([candidate("a1"), candidate("a2")])
        #expect(selection.selected == ["a1"])
    }

    @Test func chosenWindowsKeepTheOfferedOrder() {
        var selection = WindowSelection()
        selection.toggle("a2")
        selection.toggle("a1")
        #expect(selection.chosen(from: group.windows).map(\.id) == ["a1", "a2"])
    }
}

@Suite("Window sets")
struct WindowSetTests {
    @Test func tuckedWindowsBecomeSeparateRowsInTheStream() {
        let parking = MockWindowParkingService()
        parking.candidates = [candidate("a1", pid: 1), candidate("a2", pid: 1), candidate("b1", app: "B", pid: 2)]
        var library = TuckLibrary()
        let parked = parking.park(parking.candidates).compactMap { result -> ParkedWindow? in
            if case .parked(let window) = result { return window }
            return nil
        }
        library.parkAll(parked)
        #expect(library.windows.count == 3)
        #expect(library.windows.map(\.id) == parked.map(\.id))
    }

    @Test func aSetGoesOnTopOfWhatWasAlreadyTucked() {
        var library = TuckLibrary()
        let earlier = ParkedWindow(app: AppIdentity(bundleID: "b", name: "B"), title: "earlier",
                                   originalFrame: WindowFrame(x: 0, y: 0, width: 10, height: 10))
        library.park(earlier)
        let windows = (0..<3).map { index in
            ParkedWindow(app: AppIdentity(bundleID: "a", name: "A"), title: "w\(index)", originalFrame: WindowFrame(x: 0, y: 0, width: 10, height: 10))
        }
        library.parkAll(windows)
        #expect(library.windows.map(\.title) == ["w0", "w1", "w2", "earlier"])
    }

    @Test func onlyChosenWindowsAreParkedAndRefusalsAreReported() {
        let parking = MockWindowParkingService()
        parking.candidates = [candidate("a1"), candidate("a2"), candidate("a3")]
        parking.refusing = ["a3"]
        var selection = WindowSelection()
        selection.toggle("a1")
        selection.toggle("a3")
        let results = parking.park(selection.chosen(from: parking.candidates))
        #expect(parking.parkedCandidates == ["a1"])
        #expect(results.count == 2)
        #expect(results.last == .failed)
    }

    @Test func restoringOneLeavesTheOthers() {
        var library = TuckLibrary()
        let windows = (0..<3).map { index in
            ParkedWindow(app: AppIdentity(bundleID: "a", name: "A"), title: "w\(index)", originalFrame: WindowFrame(x: 0, y: 0, width: 10, height: 10))
        }
        library.parkAll(windows)
        library.removeWindow(id: windows[1].id)
        #expect(library.windows.map(\.title) == ["w0", "w2"])
    }

    @Test func aBatchOfRestoresIsSummarisedHonestly() {
        let summary = RestoreSummary(results: [.moved, .constrained, .windowGone, .failed, .simulated])
        #expect(summary.restored == 3)
        #expect(summary.gone == 1)
        #expect(summary.kept == 1)
        #expect(summary.total == 5)
    }
}
