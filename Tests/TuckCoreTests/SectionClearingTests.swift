import Foundation
import Testing
@testable import TuckCore

@Suite("Clearing a section")
struct SectionClearingTests {
    @Test func eachSectionIsNamedForItsLens() {
        #expect(StreamLens.allCases.map(SectionClearing.title) == ["Clear Windows", "Clear Files", "Clear Copied"])
    }

    @Test func oneTuckedWindowIsAskedAboutAsOne() {
        #expect(SectionClearing.windowsQuestion(count: 1) == "Put back the tucked window?")
        #expect(SectionClearing.windowsConfirmation(count: 1) == "Put Back")
        #expect(SectionClearing.windowsQuestion(count: 3) == "Put back all 3 windows?")
        #expect(SectionClearing.windowsConfirmation(count: 3) == "Put Back All")
    }

    @Test func clearingWindowsSaysNoneIsClosed() {
        #expect(SectionClearing.windowsDetail(count: 1).contains("isn't closed"))
        #expect(SectionClearing.windowsDetail(count: 3).contains("none is closed"))
    }

    @Test func copiesAreCounted() {
        #expect(SectionClearing.copiedQuestion(count: 1) == "Clear the copied item?")
        #expect(SectionClearing.copiedQuestion(count: 12) == "Clear all 12 copied items?")
    }
}
