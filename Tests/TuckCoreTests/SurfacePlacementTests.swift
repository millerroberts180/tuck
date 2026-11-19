import Foundation
import Testing
@testable import TuckCore

@Suite("Surface placement")
struct SurfacePlacementTests {
    /// A built-in display with the menu bar, then two external ones.
    private let displays = [(id: 1, builtIn: true), (id: 2, builtIn: false), (id: 3, builtIn: false)]

    private func ids(_ choice: SurfaceDisplays, _ displays: [(id: Int, builtIn: Bool)]) -> [Int] {
        choice.select(from: displays, isBuiltIn: \.builtIn).map(\.id)
    }

    @Test func eachChoiceKeepsItsDisplaysInOrder() {
        #expect(ids(.all, displays) == [1, 2, 3])
        #expect(ids(.builtIn, displays) == [1])
        #expect(ids(.external, displays) == [2, 3])
    }

    @Test func withNoMatchTheMenuBarDisplayIsUsed() {
        // Lid closed: only external displays, the first of which has the menu bar.
        let docked = [(id: 2, builtIn: false), (id: 3, builtIn: false)]
        #expect(ids(.builtIn, docked) == [2])
        // Nothing plugged in.
        let laptop = [(id: 1, builtIn: true)]
        #expect(ids(.external, laptop) == [1])
        #expect(ids(.all, []).isEmpty)
    }

    @Test func storedValuesStayReadable() {
        #expect(SurfaceDisplays(rawValue: "builtIn") == .builtIn)
        #expect(NotchlessStyle(rawValue: "bubble") == .bubble)
        #expect(NotchlessStyle(rawValue: "island") == nil)
    }
}
