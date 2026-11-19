import CoreGraphics
import Foundation
import Testing
@testable import TuckCore

@Suite("Window grouping")
struct WindowGroupingTests {
    let now = Date()
    let safari = AppIdentity(bundleID: "com.apple.Safari", name: "Safari")
    let notes = AppIdentity(bundleID: "com.apple.Notes", name: "Notes")

    func window(_ app: AppIdentity, _ title: String, minutesAgo: Double) -> ParkedWindow {
        ParkedWindow(app: app, title: title, originalFrame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                     tuckedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func windowsFromOneAppShareARow() {
        let groups = WindowGrouping.groups(for: [window(safari, "A", minutesAgo: 10), window(notes, "N", minutesAgo: 5),
                                                 window(safari, "B", minutesAgo: 1)])
        #expect(groups.count == 2)
        #expect(groups.first { $0.app == safari }?.isMultiWindow == true)
        #expect(groups.first { $0.app == notes }?.isMultiWindow == false)
    }

    @Test func groupsFollowTheirNewestWindowAndChildrenAreNewestFirst() {
        let groups = WindowGrouping.groups(for: [window(safari, "old", minutesAgo: 30), window(notes, "N", minutesAgo: 3),
                                                 window(safari, "new", minutesAgo: 1), window(safari, "middle", minutesAgo: 10)])
        #expect(groups.map(\.app.name) == ["Safari", "Notes"])
        #expect(groups.first?.windows.map(\.title) == ["new", "middle", "old"])
    }

    @Test func appsWithoutBundleIdentifiersGroupByName() {
        let helper = AppIdentity(bundleID: "", name: "Helper")
        let groups = WindowGrouping.groups(for: [window(helper, "1", minutesAgo: 1), window(helper, "2", minutesAgo: 2)])
        #expect(groups.count == 1)
        #expect(groups.first?.id == "name:Helper")
    }

    @Test func aSingleWindowIsADirectRowThatNeverExpands() {
        let single = WindowGrouping.groups(for: [window(notes, "N", minutesAgo: 1)]).first!
        var expansion = WindowGroupExpansion()
        expansion.toggle(single)
        #expect(!single.isMultiWindow)
        #expect(!expansion.isExpanded(single))
    }

    @Test func rowsOpenOnlyOnPurposeAndCloseAgain() {
        let group = WindowGrouping.groups(for: [window(safari, "A", minutesAgo: 1), window(safari, "B", minutesAgo: 2)]).first!
        var expansion = WindowGroupExpansion()
        #expect(!expansion.isExpanded(group))
        expansion.toggle(group)
        #expect(expansion.isExpanded(group))
        expansion.toggle(group)
        #expect(!expansion.isExpanded(group))
    }

    @Test func expansionIsForgottenWhenARowStopsGroupingWindows() {
        let two = WindowGrouping.groups(for: [window(safari, "A", minutesAgo: 1), window(safari, "B", minutesAgo: 2)])
        var expansion = WindowGroupExpansion()
        expansion.toggle(two[0])
        expansion.prune(to: WindowGrouping.groups(for: [window(safari, "A", minutesAgo: 1)]))
        #expect(expansion.expanded.isEmpty)
    }
}

@Suite("Deposit flight")
struct DepositFlightTests {
    @Test func theStandInFliesUpIntoTheTarget() {
        let flight = DepositFlight(window: CGRect(x: 200, y: 200, width: 800, height: 500), target: CGPoint(x: 855, y: 1090))
        #expect(flight.point(at: 0) == CGPoint(x: flight.startCard.midX, y: flight.startCard.midY))
        #expect(flight.point(at: 1) == flight.target)
        #expect(flight.endCard.midX == 855 && flight.endCard.midY == 1090)
        // It rises before it glides across: early on it has climbed more than it has moved sideways.
        let early = flight.point(at: 0.3)
        let start = flight.point(at: 0)
        #expect(early.y - start.y > abs(early.x - start.x))
    }

    @Test func itGoesStraightUpIntoTheTargetFromBelow() {
        // From either side of a 1710 pt screen, the end of the flight climbs from below the target more
        // than it moves sideways, so it never runs along the menu bar or across the notch to get there.
        for x in [0.0, 1010.0] {
            let flight = DepositFlight(window: CGRect(x: x, y: 200, width: 700, height: 500), target: CGPoint(x: 745, y: 1090))
            for t in [0.85, 0.9, 0.95, 0.99] {
                let point = flight.point(at: t)
                #expect(point.y < flight.target.y)
                #expect(flight.target.y - point.y > abs(flight.target.x - point.x))
            }
        }
    }

    @Test func bigWindowsStartAsACompactStandInCentredOnThem() {
        let flight = DepositFlight(window: CGRect(x: 0, y: 0, width: 1700, height: 1000), target: CGPoint(x: 850, y: 1090))
        #expect(flight.startCard.width <= DepositFlight.maximumCard.width)
        #expect(flight.startCard.height <= DepositFlight.maximumCard.height)
        #expect(flight.startCard.midX == 850 && flight.startCard.midY == 500)
        let small = DepositFlight(window: CGRect(x: 10, y: 10, width: 200, height: 120), target: .zero)
        #expect(small.startCard == small.window)
    }

    @Test func itArrivesTheSizeOfTheDotItLandsOn() {
        let flight = DepositFlight(window: CGRect(x: 200, y: 200, width: 800, height: 500), target: CGPoint(x: 855, y: 1090),
                                   endSize: 22)
        #expect(flight.endCard == CGRect(x: 844, y: 1079, width: 22, height: 22))
        let plain = DepositFlight(window: CGRect(x: 200, y: 200, width: 800, height: 500), target: .zero)
        #expect(plain.endCard.width == DepositFlight.defaultEndSize && plain.endCard.height == DepositFlight.defaultEndSize)
    }
}
