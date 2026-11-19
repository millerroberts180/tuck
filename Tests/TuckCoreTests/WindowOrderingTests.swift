import Foundation
import Testing
@testable import TuckCore

@Suite("Window ordering")
struct WindowOrderingTests {
    let now = Date()
    let safari = AppIdentity(bundleID: "com.apple.Safari", name: "Safari")
    let notes = AppIdentity(bundleID: "com.apple.Notes", name: "Notes")

    func window(_ app: AppIdentity, _ title: String, minutesAgo: Double) -> ParkedWindow {
        ParkedWindow(app: app, title: title, originalFrame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                     tuckedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func everyWindowKeepsItsOwnRowNewestFirst() {
        let ordered = WindowOrdering.newestFirst([
            window(safari, "A", minutesAgo: 10),
            window(notes, "N", minutesAgo: 5),
            window(safari, "B", minutesAgo: 1)
        ])
        #expect(ordered.map(\.title) == ["B", "N", "A"])
    }

    @Test func simultaneousWindowsFallBackToAppName() {
        let ordered = WindowOrdering.newestFirst([
            window(safari, "S", minutesAgo: 2),
            window(notes, "N", minutesAgo: 2)
        ])
        #expect(ordered.map(\.app.name) == ["Notes", "Safari"])
        #expect(WindowOrdering.newestFirst([]).isEmpty)
    }
}
