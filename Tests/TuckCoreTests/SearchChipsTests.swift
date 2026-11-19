import Foundation
import Testing
@testable import TuckCore

@Suite("Search chips")
struct SearchChipsTests {
    private func chips(_ categories: [ContentCategory], on: [String] = [], width: Double = 1_000,
                       measure: (SearchChips.Chip) -> Double = { _ in 10 }) -> [SearchChips.Chip] {
        SearchChips.chips(categories: categories, on: on, width: width, spacing: 0, measure: measure)
    }

    @Test func kindsComeMostFirstAndTiesKeepTheirOrder() {
        let shown = chips([.code, .text, .text, .window, .code, .window, .image])
        #expect(shown.map(\.label) == ["Windows", "Code", "Text", "Images", "Files"])
        #expect(shown.map(\.count) == [2, 2, 2, 1, 1])
        #expect(shown.allSatisfy { !$0.isOn })
        #expect(shown.first?.word == "windows")
    }

    @Test func aKindThatHoldsEverythingSaysNothingUnlessItIsTheOnlyOne() {
        // Every row is a link, so Links would filter nothing; music is one of them.
        #expect(chips([.link, .music]).map(\.label) == ["Music and audio"])
        #expect(chips([.text, .text]).map(\.label) == ["Text"])
    }

    @Test func filtersThatAreOnComeFirstAndADayHasNoCount() {
        let shown = chips([.text, .code], on: ["Yesterday", "Code"])
        #expect(shown.map(\.label) == ["Yesterday", "Code", "Text"])
        #expect(shown.map(\.isOn) == [true, true, false])
        #expect(shown[0].count == nil)
        #expect(shown[0].word == "yesterday")
    }

    @Test func aKindThatIsOnStaysWhenNothingOfItIsFound() {
        let shown = chips([.text], on: ["Images"])
        #expect(shown.map(\.label) == ["Images"])
        #expect(shown[0].count == 0)
    }

    @Test func asManyAsFitOneLineAndANarrowerOneCanStillFit() {
        let categories: [ContentCategory] = [.window, .window, .window, .screenshot, .screenshot, .code]
        let shown = chips(categories, width: 16, measure: { Double($0.label.count) })
        // Windows (7) fits; Screenshots (11) would not; Images (6) still does.
        #expect(shown.map(\.label) == ["Windows", "Images"])
    }

    @Test func nothingInTheStreamOffersNothing() {
        #expect(chips([]).isEmpty)
    }
}
