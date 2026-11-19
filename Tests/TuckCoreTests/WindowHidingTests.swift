import Foundation
import Testing
@testable import TuckCore

@Suite("Tucking without the Dock")
struct WindowHidingTests {
    let preview = AppIdentity(bundleID: "com.apple.Preview", name: "Preview")
    let notes = AppIdentity(bundleID: "com.apple.Notes", name: "Notes")

    func row(_ app: AppIdentity, _ title: String, _ method: ParkingMethod?) -> ParkedWindow {
        ParkedWindow(app: app, title: title, originalFrame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                     method: method)
    }

    @Test func hidingAnAppToAvoidTheDockAnimationDoesNotLeaveItHidden() {
        #expect(ParkingPolicy.plan(visibleWindowCount: 1, tuckingCount: 1, appCanHide: true) == .hideApp)
        #expect(ParkingPolicy.method(visibleWindowCount: 1, tuckingCount: 1, appCanHide: true) == .minimised)
        #expect(ParkingPolicy.plan(visibleWindowCount: 3, tuckingCount: 3, appCanHide: true) == .hideApp)
        #expect(ParkingPolicy.method(visibleWindowCount: 3, tuckingCount: 3, appCanHide: true) == .minimised)
    }

    @Test func anotherWindowStillOpenMeansMinimisingOutOfSight() {
        // Minimising in view would play the Dock's animation: the app is hidden only while the window is minimised.
        #expect(ParkingPolicy.plan(visibleWindowCount: 2, tuckingCount: 1, appCanHide: true) == .minimiseOutOfSight)
        #expect(ParkingPolicy.method(visibleWindowCount: 2, tuckingCount: 1, appCanHide: true) == .minimised)
    }

    @Test func everyWayOfTuckingAnAppThatCanHideKeepsTheDockAnimationOutOfView() {
        for visible in 0...4 {
            for tucking in 0...visible {
                let plan = ParkingPolicy.plan(visibleWindowCount: visible, tuckingCount: tucking, appCanHide: true)
                #expect(plan != .minimiseInView)
            }
        }
    }

    @Test func anAppThatCanNotBeHiddenIsMinimisedInView() {
        #expect(ParkingPolicy.plan(visibleWindowCount: 1, tuckingCount: 1, appCanHide: false) == .minimiseInView)
        #expect(ParkingPolicy.plan(visibleWindowCount: 3, tuckingCount: 1, appCanHide: false) == .minimiseInView)
        #expect(ParkingPolicy.method(visibleWindowCount: 1, tuckingCount: 1, appCanHide: false) == .minimised)
        #expect(ParkingPolicy.method(visibleWindowCount: 0, tuckingCount: 0, appCanHide: true) == .minimised)
    }

    @Test func theFrontWindowBarGoesBlankOnceTheWindowInFrontIsTucked() {
        let front = FrontWindowInfo(app: preview, title: "A")
        #expect(ParkingPolicy.frontWindow(front, afterTucking: [row(preview, "A", .hiddenWithApp)]) == nil)
        // Another window of the same app, now in front, isn't offered a moment after its sibling went.
        #expect(ParkingPolicy.frontWindow(front, afterTucking: [row(preview, "B", .minimised)]) == nil)
    }

    @Test func tuckingAnotherAppsWindowsLeavesTheFrontWindowBarAlone() {
        let front = FrontWindowInfo(app: notes, title: "Shopping")
        #expect(ParkingPolicy.frontWindow(front, afterTucking: [row(preview, "A", .minimised)]) == front)
        #expect(ParkingPolicy.frontWindow(front, afterTucking: []) == front)
        #expect(ParkingPolicy.frontWindow(nil, afterTucking: [row(preview, "A", .minimised)]) == nil)
    }

    @Test func theFrontWindowBarMatchesAppsWithoutBundleIdentifiersByName() {
        let helper = AppIdentity(bundleID: "", name: "Helper")
        let front = FrontWindowInfo(app: helper, title: "Main")
        #expect(ParkingPolicy.frontWindow(front, afterTucking: [row(helper, "Main", .minimised)]) == nil)
        #expect(ParkingPolicy.frontWindow(front, afterTucking: [row(AppIdentity(bundleID: "", name: "Other"), "O", .minimised)]) == front)
    }

    @Test func restoringOneHiddenWindowKeepsTheOthersFromItsAppTucked() {
        let a = row(preview, "A", .hiddenWithApp), b = row(preview, "B", .hiddenWithApp)
        let minimised = row(preview, "C", .minimised), other = row(notes, "N", .hiddenWithApp)
        let siblings = ParkingPolicy.siblingsToKeepTucked(restoring: a, among: [a, b, minimised, other])
        #expect(siblings.map(\.title) == ["B"])
    }

    @Test func restoringAMinimisedWindowTouchesNothingElse() {
        let a = row(preview, "A", .minimised), b = row(preview, "B", .hiddenWithApp)
        #expect(ParkingPolicy.siblingsToKeepTucked(restoring: a, among: [a, b]).isEmpty)
    }

    @Test func appsWithoutBundleIdentifiersAreMatchedByName() {
        let helper = AppIdentity(bundleID: "", name: "Helper")
        let a = row(helper, "A", .hiddenWithApp), b = row(helper, "B", .hiddenWithApp)
        let unrelated = row(AppIdentity(bundleID: "", name: "Other"), "O", .hiddenWithApp)
        #expect(ParkingPolicy.siblingsToKeepTucked(restoring: a, among: [a, b, unrelated]).map(\.title) == ["B"])
    }

    @Test func keptTuckedWindowsAreRecordedAsMinimised() {
        var library = TuckLibrary()
        let a = row(preview, "A", .hiddenWithApp), b = row(preview, "B", .hiddenWithApp)
        library.parkAll([a, b])
        library.setParkingMethod(.minimised, forWindows: [b.id])
        let methods = Dictionary(uniqueKeysWithValues: library.windows.map { ($0.title, $0.method) })
        #expect(methods["A"] == .hiddenWithApp)
        #expect(methods["B"] == .minimised)
    }

    @Test func windowsSavedBeforeHidingExistedLoadAsMinimised() throws {
        let old = """
        {"id":"\(UUID().uuidString)","app":{"bundleID":"com.apple.Preview","name":"Preview"},"title":"Old",
         "originalFrame":{"x":0,"y":0,"width":800,"height":600},"tuckedAt":0,"hasFrozenPreview":false,"isSample":false}
        """
        let window = try JSONDecoder().decode(ParkedWindow.self, from: Data(old.utf8))
        #expect(window.method == nil)
        #expect(!window.isHiddenWithApp)
    }
}
