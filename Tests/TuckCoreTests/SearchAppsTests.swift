import Foundation
import Testing
@testable import TuckCore

@Suite("App words")
struct SearchAppsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// Sunday 8 November 2026, at noon.
    private var now: Date { at(8, 12) }

    private let safari = SourceApp(name: "Safari", bundleID: "com.apple.Safari")
    private let chrome = SourceApp(name: "Google Chrome", bundleID: "com.google.Chrome")
    private let notes = SourceApp(name: "Notes", bundleID: "com.apple.Notes")
    private let code = SourceApp(name: "Code", bundleID: "com.microsoft.VSCode", aliases: ["Visual Studio Code"])
    private let finder = SourceApp(name: "Finder", bundleID: "com.apple.finder")

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func parse(_ text: String, _ apps: [SourceApp]) -> SearchQuery {
        SearchQuery.parse(text, apps: apps, now: now, calendar: calendar)
    }

    private func finds(_ text: String, apps: [SourceApp], searchText: String = "", category: ContentCategory = .text,
                       date: Date? = nil, extensions: Set<String> = [], from source: String? = nil) -> Bool {
        parse(text, apps).matches(searchText: searchText, category: category, date: date,
                                  facts: SearchFacts(extensions: extensions, sourceApp: source))
    }

    @Test func anAppsNameIsAFilterWhateverItsCase() {
        for typed in ["safari", "Safari", "SAFARI", "from safari", "From Safari"] {
            let query = parse(typed, [safari, notes])
            #expect(query.filterLabels == ["From Safari"], "\(typed)")
            #expect(query.terms.isEmpty, "\(typed)")
            #expect(query.apps.map(\.app) == [safari], "\(typed)")
        }
    }

    @Test func itFindsWhatCameFromTheAppAndWhatSaysItsName() {
        #expect(finds("safari", apps: [safari], from: "Safari"))
        #expect(finds("safari", apps: [safari], searchText: "Book a safari", from: "Notes"))
        #expect(!finds("safari", apps: [safari], searchText: "Meeting at 3", from: "Notes"))
        #expect(!finds("safari", apps: [safari], searchText: "Meeting at 3"))
        // "from safari" asks where it came from, not for the word.
        #expect(!finds("from safari", apps: [safari], searchText: "Book a safari", from: "Notes"))
        #expect(finds("from safari", apps: [safari], from: "Safari"))
    }

    @Test func multiWordNamesAndTheirOwnWords() {
        let apps = [safari, chrome, code]
        #expect(parse("google chrome", apps).filterLabels == ["From Google Chrome"])
        #expect(parse("chrome", apps).filterLabels == ["From Google Chrome"])
        #expect(parse("from chrome", apps).filterLabels == ["From Google Chrome"])
        // Too common a word to stand for the app.
        #expect(parse("google", apps).filterLabels.isEmpty)
        #expect(parse("google", apps).terms == ["google"])
        // A bundle's name finds what the app copied under its shorter name.
        #expect(parse("visual studio code", apps).filterLabels == ["From Code"])
        #expect(parse("visual", apps).filterLabels == ["From Code"])
        #expect(finds("chrome", apps: apps, from: "Google Chrome"))
        #expect(finds("visual studio code", apps: apps, from: "Code"))
    }

    @Test func aWordTwoAppsShareIsNeitherApp() {
        let docs = SourceApp(name: "Google Docs")
        let drive = SourceApp(name: "Google Drive")
        let one = SourceApp(name: "Affinity Photo")
        let other = SourceApp(name: "Affinity Designer")
        let query = parse("affinity", [docs, drive, one, other])
        #expect(query.apps.isEmpty)
        #expect(query.terms == ["affinity"])
        #expect(parse("designer", [one, other]).filterLabels == ["From Affinity Designer"])
    }

    @Test func notesIsTheNotesAppOnlyWhenThereIsOne() {
        let withoutNotes = parse("notes", [safari, chrome])
        #expect(withoutNotes.filterLabels == ["Text"])
        #expect(withoutNotes.apps.isEmpty)
        #expect(withoutNotes.categories == [.text, .richText])
        let withNotes = parse("notes", [safari, notes])
        #expect(withNotes.filterLabels == ["From Notes"])
        #expect(withNotes.categories.isEmpty)
        #expect(parse("note", [safari, notes]).filterLabels == ["Text"])
    }

    @Test func aChipsWordStaysAKind() {
        let music = SourceApp(name: "Music", bundleID: "com.apple.Music")
        #expect(parse("code", [code]).filterLabels == ["Code"])
        #expect(parse("music", [music]).filterLabels == ["Music and audio"])
        #expect(parse("from code", [code]).filterLabels == ["From Code"])
        #expect(parse("from music", [music]).filterLabels == ["From Music"])
        #expect(parse("screenshot", [SourceApp(name: "Screenshot")]).filterLabels == ["Screenshots"])
    }

    @Test func appsCombineWithKindsDaysAndBadges() {
        let apps = [safari, finder, notes]
        let query = parse("safari links yesterday", apps)
        #expect(query.filterLabels == ["From Safari", "Links", "Yesterday"])
        #expect(query.terms.isEmpty)
        #expect(finds("safari links yesterday", apps: apps, category: .link, date: at(7, 9), from: "Safari"))
        #expect(!finds("safari links yesterday", apps: apps, category: .link, date: at(8, 9), from: "Safari"))
        #expect(!finds("safari links yesterday", apps: apps, category: .text, date: at(7, 9), from: "Safari"))
        #expect(!finds("safari links yesterday", apps: apps, category: .link, date: at(7, 9), from: "Mail"))

        #expect(parse("pdf from finder", apps).filterLabels == ["PDF", "From Finder"])
        #expect(finds("pdf from finder", apps: apps, category: .file, extensions: ["pdf"], from: "Finder"))
        #expect(!finds("pdf from finder", apps: apps, category: .file, extensions: ["md"], from: "Finder"))
        // Any one of the apps will do.
        #expect(finds("safari finder", apps: apps, from: "Finder"))
        #expect(parse("invoice safari", apps).terms == ["invoice"])
        #expect(finds("invoice safari", apps: apps, searchText: "Invoice 42", from: "Safari"))
        #expect(!finds("invoice safari", apps: apps, searchText: "Receipt", from: "Safari"))
    }

    @Test func accentsAside() {
        let cafe = SourceApp(name: "Café Menu")
        #expect(parse("cafe menu", [cafe]).filterLabels == ["From Café Menu"])
        #expect(parse("café", [cafe]).filterLabels == ["From Café Menu"])
        #expect(finds("cafe", apps: [cafe], from: "Café Menu"))
    }

    @Test func unPickingAnAppTakesOutHowItWasTyped() {
        let apps = [safari, chrome, notes]
        #expect(SearchQuery.removing("From Safari", from: "links from Safari", apps: apps) == "links")
        #expect(SearchQuery.removing("From Google Chrome", from: "chrome invoice", apps: apps) == "invoice")
        #expect(SearchQuery.removing("From Notes", from: "notes today", apps: apps) == "today")
        // "notes" was read as the app, so un-picking Text leaves it.
        #expect(SearchQuery.removing("Text", from: "notes text", apps: apps) == "notes")
        #expect(SearchQuery.removing("Links", from: "links from safari", apps: apps) == "from safari")
    }

    @Test func theKnownAppsAreEachAppOnceAndNeverTuck() {
        let copied = [
            ClipboardEntry(text: "a", sourceAppName: "Safari", sourceBundleID: "com.apple.Safari", firstCopiedAt: now,
                           lastCopiedAt: now),
            ClipboardEntry(text: "b", sourceAppName: "Safari", sourceBundleID: "com.apple.Safari", firstCopiedAt: now,
                           lastCopiedAt: now),
            ClipboardEntry(text: "c", sourceAppName: "Tuck", sourceBundleID: "app.tuck", firstCopiedAt: now,
                           lastCopiedAt: now),
            ClipboardEntry(text: "d", firstCopiedAt: now, lastCopiedAt: now)
        ]
        let items = [HeldItem.text("e", sourceAppName: "Notes", addedAt: now),
                     HeldItem.text("f", sourceAppName: "safari", addedAt: now)]
        let known = SourceApp.known(copied: copied, items: items, excludingBundleID: "app.tuck")
        #expect(known.map(\.name) == ["Safari", "Notes"])
        #expect(known.first?.bundleID == "com.apple.Safari")
    }

    @Test func theStreamFindsWhatEachAppGave() {
        let link = ClipboardEntry(text: "https://example.com", sourceAppName: "Safari", firstCopiedAt: at(8, 9),
                                  lastCopiedAt: at(8, 9), recognition: ContentRecognition(category: .link))
        let note = ClipboardEntry(text: "Pick up the prints", sourceAppName: "Notes", firstCopiedAt: at(8, 10),
                                  lastCopiedAt: at(8, 10))
        let held = HeldItem.text("Safari trip", sourceAppName: "Messages", addedAt: at(8, 11))
        let stack = HeldItem.stack([.file(URL(fileURLWithPath: "/tmp/a.pdf"))], sourceAppName: "Finder", addedAt: at(8, 8))
        let apps = SourceApp.known(copied: [link, note], items: [held, stack])
        func found(_ text: String) -> [String] {
            TuckStream.entries(windows: [], items: [held, stack], copied: [link, note],
                               query: SearchQuery.parse(text, apps: apps, now: now, calendar: calendar)).map { entry in
                switch entry {
                case .item(let item): item.title
                case .copied(let entry): entry.text
                case .windows: "windows"
                }
            }
        }
        #expect(found("safari") == [held.title, "https://example.com"])
        #expect(found("from safari") == ["https://example.com"])
        #expect(found("notes") == ["Pick up the prints"])
        #expect(found("finder pdf") == [stack.title])
    }
}
