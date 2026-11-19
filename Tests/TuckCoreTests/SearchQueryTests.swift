import Foundation
import Testing
@testable import TuckCore

@Suite("Search")
struct SearchQueryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// Sunday 8 November 2026, at noon.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 12))! }

    private func parse(_ text: String) -> SearchQuery {
        SearchQuery.parse(text, now: now, calendar: calendar)
    }

    private func day(_ day: Int, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9))!
    }

    @Test func kindAndDateWordsBecomeFiltersInTheOrderTyped() {
        let query = parse("screenshots yesterday")
        #expect(query.categories == [.screenshot])
        #expect(query.dateRange == calendar.dateInterval(of: .day, for: day(7)))
        #expect(query.filterLabels == ["Screenshots", "Yesterday"])
        #expect(query.terms.isEmpty)

        let reversed = parse("Yesterday SCREENSHOTS")
        #expect(reversed.filterLabels == ["Yesterday", "Screenshots"])
    }

    @Test func wordsLeftOverMustAllAppear() {
        let query = parse("links safari")
        #expect(query.categories == [.link, .music])
        #expect(query.terms == ["safari"])
        #expect(query.matches(searchText: "https://apple.com\nSafari", category: .link, date: now))
        #expect(!query.matches(searchText: "https://apple.com\nMail", category: .link, date: now))
        #expect(!query.matches(searchText: "Safari", category: .text, date: now))
    }

    @Test func twoWordKindsAndSpansAreReadWhole() {
        let phones = parse("phone numbers")
        #expect(phones.filterLabels == ["Phone numbers"])
        #expect(phones.terms.isEmpty)

        let lastWeek = parse("photos from last week")
        #expect(lastWeek.terms == ["from"])
        #expect(lastWeek.filterLabels == ["Images", "Last week"])
        #expect(lastWeek.dateRange == calendar.dateInterval(of: .weekOfYear, for: day(1)))
    }

    @Test func aWeekdayIsTheMostRecentOneTodayIncluded() {
        #expect(parse("friday").dateRange == calendar.dateInterval(of: .day, for: day(6)))
        #expect(parse("sunday").dateRange == calendar.dateInterval(of: .day, for: day(8)))
        // Only one span is read; the second day word stays a word to find.
        let both = parse("today monday")
        #expect(both.dateRange == calendar.dateInterval(of: .day, for: day(8)))
        #expect(both.terms == ["monday"])
    }

    @Test func matchingIgnoresCaseAndAccents() {
        let query = parse("cafe")
        #expect(query.matches(searchText: "Café on the corner", category: .text, date: nil))
        #expect(!query.matches(searchText: "Bakery", category: .text, date: nil))
    }

    @Test func aSpanNeedsADate() {
        let query = parse("today")
        #expect(query.matches(searchText: "", category: .text, date: now))
        #expect(!query.matches(searchText: "", category: .text, date: day(7)))
        #expect(!query.matches(searchText: "", category: .text, date: nil))
    }

    @Test func nothingTypedFindsEverything() {
        #expect(parse("").isEmpty)
        #expect(parse("   ").isEmpty)
        #expect(!parse("images").isEmpty)
        #expect(parse("").matches(searchText: "", category: .secret, date: nil))
    }

    @Test func unpickingAFilterTakesOutEveryWordReadAsIt() {
        #expect(SearchQuery.removing("Images", from: "photos from safari") == "from safari")
        #expect(SearchQuery.removing("Images", from: "Images and more pictures") == "and more")
        #expect(SearchQuery.removing("Yesterday", from: "screenshots yesterday") == "screenshots")
        #expect(SearchQuery.removing("Last week", from: "links last week") == "links")
        #expect(SearchQuery.removing("Phone numbers", from: "phone numbers from mail") == "from mail")
    }

    @Test func everyKindWordHasALabelAndAKind() {
        for (word, match) in SearchQuery.typeWords {
            #expect(!match.label.isEmpty, "\(word)")
            #expect(!match.categories.isEmpty, "\(word)")
            #expect(SearchQuery.parse(word).filterLabels == [match.label], "\(word)")
        }
    }
}
