import Foundation
import Testing
@testable import TuckCore

@Suite("Restore safety")
struct RestoreSafetyTests {
    @Test func onlyAConfirmedRestoreOrAConfirmedGoneWindowDropsTheRow() {
        #expect(WindowActionResult.moved.removesParkedRow)
        #expect(WindowActionResult.constrained.removesParkedRow)
        #expect(WindowActionResult.simulated.removesParkedRow)
        #expect(WindowActionResult.windowGone.removesParkedRow)
        #expect(!WindowActionResult.failed.removesParkedRow)
        #expect(!WindowActionResult.needsPermission.removesParkedRow)
        #expect(!WindowActionResult.unchanged.removesParkedRow)
    }

    @Test func aHeldElementDecidesWhenThereIsOne() {
        #expect(WindowLookup.classify(appRunning: true, cached: .alive, titleMatchFound: false) == .found)
        #expect(WindowLookup.classify(appRunning: true, cached: .destroyed, titleMatchFound: true) == .gone)
        #expect(WindowLookup.classify(appRunning: true, cached: .unresponsive, titleMatchFound: true) == .unavailable)
    }

    @Test func aQuitAppCountsAsGoneEvenThoughItsWindowCannotAnswer() {
        // Found while testing with a real window: a force-quit app's element reads as unresponsive.
        #expect(WindowLookup.classify(appRunning: false, cached: .unresponsive, titleMatchFound: false) == .gone)
    }

    @Test func withoutAnElementOnlyAQuitAppCountsAsGone() {
        #expect(WindowLookup.classify(appRunning: false, cached: nil, titleMatchFound: false) == .gone)
        #expect(WindowLookup.classify(appRunning: true, cached: nil, titleMatchFound: true) == .found)
        // App running but no matching window: renamed, or restored by hand. Not confirmed gone.
        #expect(WindowLookup.classify(appRunning: true, cached: nil, titleMatchFound: false) == .unavailable)
        // Unknown whether the app runs (no bundle identifier): never treated as gone.
        #expect(WindowLookup.classify(appRunning: nil, cached: nil, titleMatchFound: false) == .unavailable)
    }

    @Test func aFailedRestoreLeavesTheWindowParked() {
        var library = TuckLibrary()
        let window = ParkedWindow(app: AppIdentity(bundleID: "com.apple.Notes", name: "Notes"), title: "List",
                                  originalFrame: WindowFrame(x: 0, y: 0, width: 600, height: 400))
        library.park(window)
        for result in [WindowActionResult.failed, .needsPermission, .unchanged] where result.removesParkedRow {
            library.removeWindow(id: window.id)
        }
        #expect(library.window(id: window.id) != nil)
        if WindowActionResult.windowGone.removesParkedRow { library.removeWindow(id: window.id) }
        #expect(library.window(id: window.id) == nil)
    }
}
