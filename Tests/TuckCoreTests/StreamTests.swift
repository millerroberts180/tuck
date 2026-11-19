import Foundation
import Testing
@testable import TuckCore

@Suite("One stream")
struct StreamTests {
    static let now = Date(timeIntervalSinceReferenceDate: 700_000_000)
    static func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    let safari = AppIdentity(bundleID: "com.apple.Safari", name: "Safari")
    let notes = AppIdentity(bundleID: "com.apple.Notes", name: "Notes")

    func window(_ app: AppIdentity, _ title: String, minutesAgo: Double) -> ParkedWindow {
        ParkedWindow(app: app, title: title, originalFrame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                     tuckedAt: Self.ago(minutesAgo))
    }

    func copied(_ text: String, from app: String? = nil, minutesAgo: Double) -> ClipboardEntry {
        ClipboardEntry(text: text, sourceAppName: app, firstCopiedAt: Self.ago(minutesAgo + 30),
                       lastCopiedAt: Self.ago(minutesAgo), recognition: ContentClassifier.recognize(text: text))
    }

    /// The ids of each entry, readable: an app's group as its windows' titles, an item or a copy as its
    /// title or text.
    func names(_ entries: [StreamEntry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .windows(let group): group.windows.map(\.title).joined(separator: "+")
            case .item(let item): item.title
            case .copied(let entry): entry.text
            }
        }
    }

    // MARK: Order

    @Test func windowsItemsAndCopiesInterleaveNewestFirst() {
        let entries = TuckStream.entries(
            windows: [window(notes, "Groceries", minutesAgo: 20), window(safari, "Flights", minutesAgo: 5)],
            items: [.text("Seat 14A", addedAt: Self.ago(1)), .text("Old note", addedAt: Self.ago(40))],
            copied: [copied("tracking 1Z999", minutesAgo: 10), copied("hello", minutesAgo: 60)])
        #expect(names(entries) == ["Seat 14A", "Flights", "tracking 1Z999", "Groceries", "Old note", "hello"])
        #expect(entries.map(\.date) == entries.map(\.date).sorted(by: >))
    }

    @Test func anAppsWindowsShareOneEntryDatedByItsNewestWindow() {
        let entries = TuckStream.entries(
            windows: [window(safari, "Old tab", minutesAgo: 30), window(notes, "Groceries", minutesAgo: 10),
                      window(safari, "New tab", minutesAgo: 2), window(safari, "Middle tab", minutesAgo: 15)],
            items: [.text("Note", addedAt: Self.ago(5))])
        #expect(names(entries) == ["New tab+Middle tab+Old tab", "Note", "Groceries"])
        guard case .windows(let group) = entries.first else {
            Issue.record("Expected Safari's windows first")
            return
        }
        #expect(group.app == safari)
        #expect(entries.first?.date == Self.ago(2))
        #expect(entries.first?.id == "app:com.apple.Safari")
    }

    @Test func sameMomentEntriesKeepWindowsThenItemsThenCopies() {
        let entries = TuckStream.entries(windows: [window(notes, "Window", minutesAgo: 1)],
                                         items: [.text("Item", addedAt: Self.ago(1))],
                                         copied: [copied("Copy", minutesAgo: 1)])
        #expect(names(entries) == ["Window", "Item", "Copy"])
    }

    @Test func eachEntryHasItsOwnIdentityAndLens() {
        let item = HeldItem.text("Note")
        let copy = copied("Copy", minutesAgo: 1)
        let entries = TuckStream.entries(windows: [window(notes, "Window", minutesAgo: 1)], items: [item], copied: [copy])
        #expect(Set(entries.map(\.id)) == ["app:com.apple.Notes", "item:\(item.id)", "copied:\(copy.id)"])
        #expect(Set(entries.map(\.lens)) == Set(StreamLens.allCases))
    }

    // MARK: Lenses and counts

    /// Two Safari windows and a Notes one, a text and a link, and one copy.
    var everything: (windows: [ParkedWindow], items: [HeldItem], copied: [ClipboardEntry]) {
        ([window(safari, "Flights", minutesAgo: 5), window(safari, "Hotel", minutesAgo: 6), window(notes, "List", minutesAgo: 7)],
         [.text("Note", addedAt: Self.ago(1)), .link(URL(string: "https://example.com")!, addedAt: Self.ago(2))],
         [copied("Copy", minutesAgo: 3)])
    }

    @Test func aLensShowsOnlyItsKind() {
        let all = everything
        for lens in StreamLens.allCases {
            let entries = TuckStream.entries(windows: all.windows, items: all.items, copied: all.copied, lens: lens)
            #expect(!entries.isEmpty)
            #expect(entries.allSatisfy { $0.lens == lens })
        }
        let windows = TuckStream.entries(windows: all.windows, items: all.items, copied: all.copied, lens: .windows)
        #expect(names(windows) == ["Flights+Hotel", "List"])
        let files = TuckStream.entries(windows: all.windows, items: all.items, copied: all.copied, lens: .files)
        #expect(files.count == 2)
        // No lens is Everything.
        #expect(TuckStream.entries(windows: all.windows, items: all.items, copied: all.copied).count == 5)
    }

    @Test func copiedIsOfferedOnlyWhileClipboardHistoryIsOn() {
        #expect(StreamLens.available(includingCopied: false) == [.windows, .files])
        #expect(StreamLens.available(includingCopied: true) == [.windows, .files, .copied])
        #expect(StreamLens.allCases.map(\.title) == ["Windows", "Files", "Copied"])
    }

    @Test func countsCountEachWindowNotEachApp() {
        let all = everything
        let counts = TuckStream.counts(windows: all.windows, items: all.items, copied: all.copied)
        #expect(counts == [.windows: 3, .files: 2, .copied: 1])
        #expect(TuckStream.counts(windows: [], items: []) == [.windows: 0, .files: 0, .copied: 0])
    }

    // MARK: Search

    func search(_ query: String, windows: [ParkedWindow] = [], items: [HeldItem] = [],
                copied: [ClipboardEntry] = []) -> [String] {
        names(TuckStream.entries(windows: windows, items: items, copied: copied, query: query))
    }

    @Test func searchingForAnAppKeepsAllItsWindows() {
        let windows = [window(safari, "Flights", minutesAgo: 1), window(safari, "Bank", minutesAgo: 2),
                       window(notes, "Groceries", minutesAgo: 3)]
        #expect(search("safari", windows: windows) == ["Flights+Bank"])
    }

    @Test func searchingForAWindowTitleNarrowsItsAppToTheWindowsThatMatch() {
        let windows = [window(safari, "Lisbon flights", minutesAgo: 1), window(safari, "Bank", minutesAgo: 2),
                       window(safari, "Lisbon hotel", minutesAgo: 3), window(notes, "Groceries", minutesAgo: 4)]
        let entries = TuckStream.entries(windows: windows, items: [], query: "lisbon")
        #expect(names(entries) == ["Lisbon flights+Lisbon hotel"])
        let bank = TuckStream.entries(windows: windows, items: [.text("Note", addedAt: Self.ago(1.5))], query: "bank")
        #expect(names(bank) == ["Bank"])
        // The narrowed group is dated by the newest window still in it.
        #expect(bank.first?.date == Self.ago(2))
    }

    @Test func textItemsAreFoundByTheirWords() {
        let items: [HeldItem] = [.text("Check-in opens 24 hours before departure.\nSeat 14A, carry-on only."), .text("Other")]
        #expect(search("14A", items: items) == ["Check-in opens 24 hours before departure."])
        #expect(search("departure", items: items).count == 1)
    }

    @Test func filesAreFoundByNameAndByFolder() {
        let ticket = HeldItem.file(URL(fileURLWithPath: "/Users/a/Travel/Lisbon/ticket.pdf"), addedAt: Self.ago(1))
        let other = HeldItem.file(URL(fileURLWithPath: "/Users/a/Work/report.pdf"), addedAt: Self.ago(2))
        #expect(search("ticket", items: [ticket, other]) == ["ticket.pdf"])
        #expect(search("Travel", items: [ticket, other]) == ["ticket.pdf"])
        #expect(search("pdf", items: [ticket, other]) == ["ticket.pdf", "report.pdf"])
    }

    @Test func aStackIsFoundByAnyFileInIt() {
        let stack = HeldItem.stack([.file(URL(fileURLWithPath: "/Users/a/Photos/beach.jpg")),
                                    .file(URL(fileURLWithPath: "/Users/a/Photos/dinner.jpg")),
                                    .file(URL(fileURLWithPath: "/Users/a/Scans/passport.png"))])
        #expect(search("dinner", items: [stack]) == ["3 files"])
        #expect(search("Scans", items: [stack]) == ["3 files"])
        #expect(search("receipt", items: [stack]).isEmpty)
    }

    @Test func linksAreFoundByTitleDomainAndAddress() {
        let guide = HeldItem.link(URL(string: "https://www.visitlisboa.com/en/places/alfama")!, title: "Alfama walking guide")
        let other = HeldItem.link(URL(string: "https://example.com/news")!, title: "News")
        #expect(search("walking", items: [guide, other]) == ["Alfama walking guide"])
        #expect(search("visitlisboa", items: [guide, other]) == ["Alfama walking guide"])
        #expect(search("example.com", items: [guide, other]) == ["News"])
        #expect(search("en/places", items: [guide, other]) == ["Alfama walking guide"])
    }

    @Test func itemsAreFoundByTheAppTheyCameFrom() {
        let item = HeldItem.text("Quarterly numbers", sourceAppName: "Keynote")
        #expect(search("keynote", items: [item, .text("Other")]) == ["Quarterly numbers"])
    }

    @Test func copiedTextIsFoundByItsTextAndItsApp() {
        let entries = [copied("Meet at 7 by the fountain", from: "Messages", minutesAgo: 1),
                       copied("SELECT * FROM users", from: "Terminal", minutesAgo: 2)]
        #expect(search("fountain", copied: entries) == ["Meet at 7 by the fountain"])
        #expect(search("messages", copied: entries) == ["Meet at 7 by the fountain"])
        #expect(search("terminal", copied: entries) == ["SELECT * FROM users"])
    }

    @Test func everyWordHasToBeFoundSomewhere() {
        let windows = [window(safari, "Lisbon flights", minutesAgo: 1), window(safari, "Bank", minutesAgo: 2)]
        let items: [HeldItem] = [.text("Lisbon packing list", addedAt: Self.ago(3)), .text("Flights to Porto", addedAt: Self.ago(4))]
        // Words may be found in different places: the app's name and a window's title.
        #expect(search("safari lisbon", windows: windows, items: items) == ["Lisbon flights"])
        #expect(search("lisbon flights", windows: windows, items: items) == ["Lisbon flights"])
        #expect(search("lisbon list", windows: windows, items: items) == ["Lisbon packing list"])
        #expect(search("lisbon porto", windows: windows, items: items).isEmpty)
        // Extra spaces are not words.
        #expect(search("  lisbon   flights  ", windows: windows, items: items) == ["Lisbon flights"])
    }

    @Test func caseAndAccentsDoNotMatter() {
        let items: [HeldItem] = [.text("Café Lisboa reservation", addedAt: Self.ago(1)), .text("Other", addedAt: Self.ago(2))]
        #expect(search("cafe", items: items) == ["Café Lisboa reservation"])
        #expect(search("CAFÉ LISBOA", items: items) == ["Café Lisboa reservation"])
        let windows = [window(AppIdentity(bundleID: "com.example.resume", name: "Résumé Builder"), "Draft", minutesAgo: 1)]
        #expect(search("resume", windows: windows) == ["Draft"])
    }

    @Test func anEmptySearchShowsEverything() {
        let all = everything
        for query in ["", "   "] {
            #expect(TuckStream.entries(windows: all.windows, items: all.items, copied: all.copied, query: query).count == 5)
        }
    }

    @Test func aSearchAndALensNarrowTogether() {
        let windows = [window(safari, "Lisbon flights", minutesAgo: 1)]
        let items: [HeldItem] = [.text("Lisbon packing list", addedAt: Self.ago(2))]
        let copies = [copied("Lisbon hotel address", minutesAgo: 3)]
        let files = TuckStream.entries(windows: windows, items: items, copied: copies, lens: .files, query: "lisbon")
        #expect(names(files) == ["Lisbon packing list"])
        let copiedOnly = TuckStream.entries(windows: windows, items: items, copied: copies, lens: .copied, query: "lisbon")
        #expect(names(copiedOnly) == ["Lisbon hotel address"])
    }

    @Test func kindWordsPickKindsAcrossTheStream() {
        let windows = [window(safari, "Lisbon flights", minutesAgo: 1)]
        let photo = HeldItem.file(URL(fileURLWithPath: "/Users/a/Photos/beach.jpg"), addedAt: Self.ago(2))
        let guide = HeldItem.link(URL(string: "https://www.visitlisboa.com/en")!, title: "Lisbon guide", addedAt: Self.ago(3))
        let copies = [copied("https://example.com/lisbon", minutesAgo: 4), copied("Lisbon packing list", minutesAgo: 5)]
        func found(_ text: String) -> [String] {
            names(TuckStream.entries(windows: windows, items: [photo, guide], copied: copies, query: text))
        }
        #expect(found("windows") == ["Lisbon flights"])
        #expect(found("images") == ["beach.jpg"])
        // A link held and a link copied are both links; the word left must still appear.
        #expect(found("links lisbon") == ["Lisbon guide", "https://example.com/lisbon"])
        #expect(found("text") == ["Lisbon packing list"])
    }

    @Test func aStackIsFoundByTheKindsItHolds() {
        let photos = HeldItem.stack([.file(URL(fileURLWithPath: "/Users/a/Photos/beach.jpg")),
                                     .file(URL(fileURLWithPath: "/Users/a/Photos/dinner.jpg"))])
        let papers = HeldItem.stack([.file(URL(fileURLWithPath: "/Users/a/Work/report.pdf")),
                                     .file(URL(fileURLWithPath: "/Users/a/Work/notes.txt"))])
        #expect(search("images", items: [photos, papers]) == ["2 files"])
        #expect(search("images dinner", items: [photos, papers]) == ["2 files"])
        #expect(search("images report", items: [photos, papers]).isEmpty)
    }

    @Test func dayWordsPickWhenSomethingCameIn() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let items: [HeldItem] = [.text("Fresh note", addedAt: now), .text("Older note", addedAt: yesterday)]
        let today = TuckStream.entries(windows: [], items: items, query: "today", now: now)
        #expect(names(today) == ["Fresh note"])
        let before = TuckStream.entries(windows: [], items: items, query: "yesterday older", now: now)
        #expect(names(before) == ["Older note"])
    }

    @Test func searchCountsSayWhereEachLensFindsSomething() {
        let windows = [window(safari, "Lisbon flights", minutesAgo: 1), window(safari, "Lisbon hotel", minutesAgo: 2),
                       window(notes, "Groceries", minutesAgo: 3)]
        let items: [HeldItem] = [.text("Lisbon packing list", addedAt: Self.ago(4)), .text("Other", addedAt: Self.ago(5))]
        let copies = [copied("Porto", minutesAgo: 6)]
        let counts = TuckStream.counts(windows: windows, items: items, copied: copies, query: SearchQuery.parse("lisbon"))
        #expect(counts == [.windows: 2, .files: 1, .copied: 0])
    }

    @Test func aLensThatFindsNothingStepsAsideForOneThatDoes() {
        // Nothing copied matches but a window does: the search leaves Copied for Everything.
        #expect(TuckStream.lens(.copied, keptFor: [.windows: 1, .files: 0, .copied: 0]) == nil)
        // The lens finds something: it stays.
        #expect(TuckStream.lens(.files, keptFor: [.windows: 3, .files: 1, .copied: 0]) == .files)
        // Nothing anywhere: the lens stays, and the fold says so.
        #expect(TuckStream.lens(.windows, keptFor: [.windows: 0, .files: 0, .copied: 0]) == .windows)
        #expect(TuckStream.lens(nil, keptFor: [.windows: 0, .files: 2, .copied: 0]) == nil)
    }

    // MARK: Dropping

    @Test func theDropTargetSaysWhatTheDragCarries() {
        #expect(DropKind.file.label == "Drop file into Tuck")
        #expect(DropKind.link.label == "Drop link into Tuck")
        #expect(DropKind.text.label == "Drop text into Tuck")
        #expect(DropKind.invitation == "Drop into Tuck")
    }

    @Test func filesWinOverALinkAndALinkOverText() {
        #expect(DropKind.kind(hasFiles: true, hasLink: true, arrivesAsFile: false) == .file)
        #expect(DropKind.kind(hasFiles: false, hasLink: true, arrivesAsFile: true) == .link)
        // Promised files and raw images arrive as files; anything else is text.
        #expect(DropKind.kind(hasFiles: false, hasLink: false, arrivesAsFile: true) == .file)
        #expect(DropKind.kind(hasFiles: false, hasLink: false, arrivesAsFile: false) == .text)
    }

    // MARK: Library

    @Test func whatIsTuckedOrAddedLastComesFirst() {
        var library = TuckLibrary()
        library.park(window(safari, "First", minutesAgo: 2))
        library.park(window(notes, "Second", minutesAgo: 1))
        library.add(.text("older"))
        library.add(.text("newer"))
        #expect(library.windows.map(\.title) == ["Second", "First"])
        #expect(library.items.map(\.title) == ["newer", "older"])
        #expect(library.totalItemCount == 4)
    }

    @Test func aFullStreamHasNoRoomLeftButKeepsWhatItHolds() {
        let items = (0..<(TuckLibrary.heldItemLimit + 5)).map { HeldItem.text("Note \($0)") }
        let library = TuckLibrary(items: items)
        #expect(library.remainingCapacity == 0)
        #expect(library.items.count == TuckLibrary.heldItemLimit + 5)
        #expect(TuckLibrary(items: Array(items.prefix(3))).remainingCapacity == TuckLibrary.heldItemLimit - 3)
    }
}
