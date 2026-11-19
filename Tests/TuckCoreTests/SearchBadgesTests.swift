import Foundation
import Testing
@testable import TuckCore

@Suite("Badge words")
struct SearchBadgesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// Sunday 8 November 2026, at noon.
    private var now: Date { at(8, 12) }

    private func parse(_ text: String) -> SearchQuery {
        SearchQuery.parse(text, now: now, calendar: calendar)
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func finds(_ text: String, searchText: String = "", category: ContentCategory = .file, date: Date? = nil,
                       extensions: Set<String> = [], bytes: Int? = nil) -> Bool {
        parse(text).matches(searchText: searchText, category: category, date: date,
                            facts: SearchFacts(extensions: extensions, byteCount: bytes))
    }

    // MARK: Types

    @Test func typeWordsFindFilesByTheirExtension() {
        for word in ["pdf", "pdfs", "PDF"] {
            let query = parse(word)
            #expect(query.filterLabels == ["PDF"], "\(word)")
            #expect(query.terms.isEmpty, "\(word)")
            #expect(query.categories.isEmpty, "\(word)")
        }
        #expect(finds("pdf", extensions: ["pdf"]))
        #expect(!finds("pdf", extensions: ["png"]))
        #expect(finds("png", extensions: ["png"]))
        #expect(finds("zip", extensions: ["zip"]))
        #expect(finds("jpeg", extensions: ["jpg"]))
        #expect(finds("archives", extensions: ["gz"]))
        #expect(finds("disk images", extensions: ["dmg"]))
        #expect(parse("disk images").filterLabels == ["Disk images"])
        #expect(finds("spreadsheets", extensions: ["numbers"]))
        #expect(finds("keynote", extensions: ["key"]))
    }

    @Test func aTypeWordAlsoFindsWhatSaysIt() {
        // A window titled with a file's name, and a note that mentions one.
        #expect(finds("pdfs", searchText: "Preview\nInvoice-0423.pdf", category: .window))
        #expect(finds("pdf", searchText: "send me the pdf", category: .text))
        #expect(finds("archives", searchText: "Backup.zip", category: .window))
        #expect(!finds("pdf", searchText: "Trip planning", category: .window))
    }

    @Test func anyOfSeveralTypesWill() {
        let query = parse("pdf png")
        #expect(query.filterLabels == ["PDF", "PNG"])
        #expect(finds("pdf png", extensions: ["png"]))
        #expect(finds("pdf png", extensions: ["pdf"]))
        #expect(!finds("pdf png", extensions: ["zip"]))
    }

    @Test func kindWordsStayKinds() {
        #expect(parse("folder").categories == [.folder])
        #expect(parse("folder").badges.isEmpty)
        #expect(parse("video").categories == [.video])
        #expect(parse("videos pdf").categories == [.video])
        #expect(parse("videos pdf").filterLabels == ["Videos", "PDF"])
        #expect(parse("keys").categories == [.secret])
        #expect(parse("docs").filterLabels == ["Files"])
        // A kind and a type together: files that are PDFs.
        #expect(finds("files pdf", category: .file, extensions: ["pdf"]))
        #expect(!finds("files pdf", category: .text, extensions: ["pdf"]))
        // The chips' kinds are read as they were.
        #expect(SearchChips.kinds.map(\.label).contains("Videos"))
        #expect(SearchChips.kinds.allSatisfy { !$0.categories.isEmpty })
    }

    @Test func everyBadgeWordHasALabelAndIsNoKindWord() {
        for (word, match) in SearchQuery.badgeWords {
            #expect(!match.label.isEmpty, "\(word)")
            #expect(SearchQuery.typeWords[word] == nil, "\(word)")
            #expect(SearchQuery.parse(word).filterLabels == [match.label], "\(word)")
            #expect(SearchQuery.parse(word).badges.count == 1, "\(word)")
        }
    }

    // MARK: Sizes

    @Test func aSizeFindsUpToTheNextStepOfItsLastDigit() {
        #expect(parse("2 mb").filterLabels == ["2 MB"])
        #expect(parse("2mb").filterLabels == ["2 MB"])
        #expect(finds("2 mb", bytes: 2_000_000))
        #expect(finds("2 mb", bytes: 2_999_999))
        #expect(!finds("2 mb", bytes: 3_000_000))
        #expect(!finds("2 mb", bytes: 1_999_999))
        #expect(finds("2.4 mb", bytes: 2_450_000))
        #expect(!finds("2.4 mb", bytes: 2_500_000))
        #expect(!finds("2.4 mb", bytes: 2_399_999))
        #expect(parse("500kb").filterLabels == ["500 KB"])
        #expect(finds("500kb", bytes: 500_400))
        #expect(!finds("500kb", bytes: 501_000))
        #expect(finds("1 gigabyte", bytes: 1_500_000_000))
        #expect(finds("700 bytes", bytes: 700))
    }

    @Test func comparisonsFindAboveOrBelow() {
        for text in [">10mb", "> 10 mb", "over 10 mb", "more than 10mb", "bigger than 10 MB", "larger than 10 megabytes"] {
            let query = parse(text)
            #expect(query.filterLabels == ["Over 10 MB"], "\(text)")
            #expect(query.terms.isEmpty, "\(text)")
            #expect(finds(text, bytes: 10_000_001), "\(text)")
            #expect(!finds(text, bytes: 10_000_000), "\(text)")
        }
        for text in ["<1mb", "under 1 mb", "less than 1 mb", "smaller than 1mb", "below 1 mb"] {
            #expect(parse(text).filterLabels == ["Under 1 MB"], "\(text)")
            #expect(finds(text, bytes: 999_999), "\(text)")
            #expect(!finds(text, bytes: 1_000_000), "\(text)")
        }
        #expect(finds("at least 5 mb", bytes: 5_000_000))
        #expect(!finds("at least 5 mb", bytes: 4_999_999))
        #expect(finds("<=5mb", bytes: 5_000_000))
        #expect(!finds("at most 5 mb", bytes: 5_000_001))
        // Every size must hold: between two.
        #expect(finds("over 1 mb under 10 mb", bytes: 4_000_000))
        #expect(!finds("over 1 mb under 10 mb", bytes: 12_000_000))
    }

    @Test func largeAndSmallHaveThresholds() {
        for word in ["large", "big", "huge"] {
            #expect(parse(word).filterLabels == ["Large"], "\(word)")
            #expect(finds(word, bytes: 10_000_000), "\(word)")
            #expect(!finds(word, bytes: 9_999_999), "\(word)")
        }
        for word in ["small", "tiny"] {
            #expect(parse(word).filterLabels == ["Small"], "\(word)")
            #expect(finds(word, bytes: 99_999), "\(word)")
            #expect(!finds(word, bytes: 100_000), "\(word)")
        }
        // Something without a size is neither, unless it says so.
        #expect(!finds("small", category: .text))
        #expect(finds("big", searchText: "big news", category: .text))
    }

    @Test func aNumberAloneIsNoSizeOrTime() {
        #expect(parse("invoices 2019").badges.isEmpty)
        #expect(parse("invoices 2019").terms == ["invoices", "2019"])
        #expect(parse("before 6").terms == ["before", "6"])
        #expect(parse("13pm").terms == ["13pm"])
        #expect(parse("mp3").filterLabels == ["MP3"])
    }

    // MARK: Times

    @Test func anHourFindsTheWholeHour() {
        for text in ["3pm", "3 pm", "3 p.m.", "3:00pm", "15:00"] {
            #expect(!parse(text).badges.isEmpty, "\(text)")
            #expect(finds(text, date: at(8, 15)), "\(text)")
            #expect(finds(text, date: at(8, 15, 59)), "\(text)")
            #expect(!finds(text, date: at(8, 16)), "\(text)")
            #expect(!finds(text, date: at(8, 3)), "\(text)")
        }
        #expect(parse("3pm").filterLabels == ["3 PM"])
        #expect(parse("15:00").filterLabels == ["15:00"])
        #expect(finds("12am", date: at(8, 0, 30)))
        #expect(finds("12pm", date: at(8, 12, 30)))
    }

    @Test func minutesFindThatMinuteOnEitherClock() {
        #expect(parse("3:41").filterLabels == ["3:41"])
        #expect(finds("3:41", date: at(8, 15, 41)))
        #expect(finds("3:41", date: at(8, 3, 41)))
        #expect(!finds("3:41", date: at(8, 15, 42)))
        #expect(parse("3:41pm").filterLabels == ["3:41 PM"])
        #expect(finds("3:41 pm", date: at(8, 15, 41)))
        #expect(!finds("3:41 pm", date: at(8, 3, 41)))
        #expect(finds("15:41", date: at(8, 15, 41)))
        #expect(!finds("15:41", date: at(8, 3, 41)))
        #expect(!finds("3pm"))
    }

    @Test func partsOfTheDay() {
        #expect(finds("morning", date: at(8, 5)))
        #expect(finds("morning", date: at(8, 11, 59)))
        #expect(!finds("morning", date: at(8, 12)))
        #expect(finds("afternoon", date: at(8, 12)))
        #expect(!finds("afternoon", date: at(8, 17)))
        #expect(finds("evening", date: at(8, 17)))
        #expect(!finds("evening", date: at(8, 21)))
        #expect(finds("night", date: at(8, 23)))
        #expect(finds("night", date: at(8, 4, 59)))
        #expect(!finds("night", date: at(8, 5)))
        // "Good morning" is still found by what it says.
        #expect(finds("morning", searchText: "Good morning", category: .text, date: at(8, 20)))
    }

    @Test func timesCombineWithDaysAndTypes() {
        let yesterday3pm = parse("yesterday 3pm")
        #expect(yesterday3pm.filterLabels == ["Yesterday", "3 PM"])
        #expect(yesterday3pm.matches(searchText: "", category: .text, date: at(7, 15, 20)))
        #expect(!yesterday3pm.matches(searchText: "", category: .text, date: at(8, 15, 20)))
        #expect(!yesterday3pm.matches(searchText: "", category: .text, date: at(7, 14, 20)))

        let pdfThisMorning = parse("pdf this morning")
        #expect(pdfThisMorning.filterLabels == ["PDF", "This morning"])
        let pdf = SearchFacts(extensions: ["pdf"])
        #expect(pdfThisMorning.matches(searchText: "", category: .file, date: at(8, 9), facts: pdf))
        #expect(!pdfThisMorning.matches(searchText: "", category: .file, date: at(7, 9), facts: pdf))
        #expect(!pdfThisMorning.matches(searchText: "", category: .file, date: at(8, 13), facts: pdf))
        #expect(!pdfThisMorning.matches(searchText: "", category: .file, date: at(8, 9)))

        #expect(parse("last night").dateRange == DateInterval(start: at(7, 21), end: at(8, 5)))
        #expect(parse("this afternoon").dateRange == DateInterval(start: at(8, 12), end: at(8, 17)))
        #expect(parse("screenshots yesterday morning").filterLabels == ["Screenshots", "Yesterday", "Morning"])
    }

    // MARK: Labels

    @Test func badgeLabelsReadBackAsThemselves() {
        // The chips put a label back in the field, lowercased, when it is clicked.
        for text in ["pdf", "jpg", "archives", "2.4mb", ">10mb", "under 1 mb", "at least 5 mb", "large", "3pm",
                     "3:41pm", "3:41", "15:00", "morning", "this morning", "last night"] {
            for label in parse(text).filterLabels {
                #expect(SearchQuery.parse(label.lowercased(), now: now, calendar: calendar).filterLabels == [label],
                        "\(text) → \(label)")
            }
        }
    }

    @Test func unpickingABadgeTakesOutWhatWasReadAsIt() {
        #expect(SearchQuery.removing("PDF", from: "PDFs from mail") == "from mail")
        #expect(SearchQuery.removing("Over 10 MB", from: "pdf over 10 MB safari") == "pdf safari")
        #expect(SearchQuery.removing("Over 10 MB", from: "pdf >10mb") == "pdf")
        #expect(SearchQuery.removing("3 PM", from: "notes 3pm") == "notes")
        #expect(SearchQuery.removing("3 PM", from: "notes 4pm") == "notes 4pm")
        #expect(SearchQuery.removing("Large", from: "big zip") == "zip")
        #expect(SearchQuery.removing("This morning", from: "pdf this morning") == "pdf")
    }

    @Test func aBadgeWordIsASearch() {
        #expect(!parse("pdf").isEmpty)
        #expect(!parse("3pm").isEmpty)
        #expect(parse("over 2 mb").asksForSize)
        #expect(!parse("pdf 3pm").asksForSize)
    }

    // MARK: The stream

    @Test func theStreamReadsHeldFilesAndCopiesBadges() {
        let report = HeldItem.file(URL(fileURLWithPath: "/tmp/Report.pdf"), addedAt: at(8, 9))
        let photo = HeldItem.file(URL(fileURLWithPath: "/tmp/Beach.jpg"), addedAt: at(8, 15))
        let stack = HeldItem.stack([.file(URL(fileURLWithPath: "/tmp/a.pdf")), .file(URL(fileURLWithPath: "/tmp/b.md"))],
                                   addedAt: at(8, 10))
        let shot = ClipboardEntry(text: "", firstCopiedAt: at(8, 11), lastCopiedAt: at(8, 11),
                                  recognition: ContentRecognition(category: .screenshot),
                                  payload: ClipPayload(imageFile: "shot.png", byteCount: 2_400_000))
        let sizes = [report.id: 12_000_000, photo.id: 3_000_000]
        func titles(_ text: String) -> [String] {
            TuckStream.entries(windows: [], items: [report, photo, stack], copied: [shot],
                               query: SearchQuery.parse(text, now: now, calendar: calendar),
                               size: { sizes[$0.id] }).map { entry in
                switch entry {
                case .item(let item): item.title
                case .copied: "shot"
                case .windows: "windows"
                }
            }
        }
        #expect(Set(titles("pdf")) == ["Report.pdf", stack.title])
        #expect(titles("png") == ["shot"])
        #expect(titles("jpeg") == ["Beach.jpg"])
        #expect(titles("large") == ["Report.pdf"])
        #expect(titles("2 mb") == ["shot"])
        #expect(titles("afternoon") == ["Beach.jpg"])
        #expect(Set(titles("morning")) == ["shot", stack.title, "Report.pdf"])
    }

    @Test func sizesAreAskedForOnlyWhenASearchNamesOne() {
        let items = [HeldItem.file(URL(fileURLWithPath: "/tmp/Report.pdf"), addedAt: at(8, 9))]
        var asked = 0
        _ = TuckStream.entries(windows: [], items: items, query: SearchQuery.parse("pdf report"),
                               size: { _ in asked += 1; return nil })
        _ = TuckStream.counts(windows: [], items: items, query: SearchQuery.parse("3pm"),
                              size: { _ in asked += 1; return nil })
        #expect(asked == 0)
        _ = TuckStream.entries(windows: [], items: items, query: SearchQuery.parse("large"),
                               size: { _ in asked += 1; return nil })
        #expect(asked == 1)
    }
}

@Suite("Badge text")
struct BadgeTextTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let us = Locale(identifier: "en_US")
    private let uk = Locale(identifier: "en_GB")

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Formatters put a narrow space before AM and PM.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func typesAreShortCapitalsOrAWord() {
        #expect(BadgeText.type(forExtension: "pdf") == "PDF")
        #expect(BadgeText.type(forExtension: "PNG") == "PNG")
        #expect(BadgeText.type(forExtension: "heic") == "HEIC")
        #expect(BadgeText.type(forExtension: "swift") == "Swift")
        #expect(BadgeText.type(forExtension: "key") == "Keynote")
        #expect(BadgeText.type(forExtension: "md") == "Markdown")
        #expect(BadgeText.type(forExtension: "") == "File")
    }

    @Test func sizesAreFindersAndNeverZero() {
        #expect(BadgeText.size(2_400_000) == ByteCountFormatter.string(fromByteCount: 2_400_000, countStyle: .file))
        #expect(BadgeText.size(nil) == nil)
        #expect(BadgeText.size(0) == nil)
        #expect(BadgeText.items(1) == "1 item")
        #expect(BadgeText.items(12) == "12 items")
        #expect(BadgeText.files(3) == "3 files")
    }

    @Test func timesSayAsLittleAsTheyCan() {
        let now = at(8, 12)
        #expect(plain(BadgeText.time(at(8, 9, 30), now: now, calendar: calendar, locale: us)) == "9:30 AM")
        #expect(BadgeText.time(at(8, 15, 41), now: at(8, 18), calendar: calendar, locale: uk) == "15:41")
        #expect(plain(BadgeText.time(at(7, 15, 41), now: now, calendar: calendar, locale: us)) == "Yesterday 3:41 PM")
        #expect(BadgeText.shortTime(at(7, 15, 41), now: now, calendar: calendar, locale: us) == "Yesterday")
        #expect(plain(BadgeText.shortTime(at(8, 9, 30), now: now, calendar: calendar, locale: us)) == "9:30 AM")
        #expect(BadgeText.time(at(2, 15, 41), now: now, calendar: calendar, locale: uk) == "Mon")
        #expect(BadgeText.time(at(1, 15, 41), now: now, calendar: calendar, locale: uk) == "1 Nov")
        #expect(BadgeText.time(at(1, 15, 41), now: now, calendar: calendar, locale: us) == "Nov 1")
        #expect(BadgeText.time(at(2, 9, year: 2025), now: now, calendar: calendar, locale: uk) == "2 Nov 2025")
    }

    @Test func textsCountTheirWordsAndCodeItsLines() {
        #expect(BadgeText.wordCount("Pick up the prints before 6, and ask about the frame.") == 11)
        #expect(BadgeText.wordCount("  — ") == 0)
        #expect(BadgeText.wordCount("東京は晴れです") > 1)
        #expect(BadgeText.lineCount("func greet() {\n    return 1\n}\n") == 3)
        #expect(BadgeText.lineCount("one\r\ntwo") == 2)
        #expect(BadgeText.lineCount("\n\nls -la\n") == 1)
        #expect(BadgeText.lineCount("") == 0)
        #expect(BadgeText.words(1) == "1 word")
        #expect(BadgeText.words(240) == "240 words")
        #expect(BadgeText.lines(4) == "4 lines")
    }

    @Test func lengthsReadAsAClock() {
        #expect(BadgeText.duration(94) == "1:34")
        #expect(BadgeText.duration(248.4) == "4:08")
        #expect(BadgeText.duration(3723) == "1:02:03")
        #expect(BadgeText.duration(0.4) == nil)
        #expect(BadgeText.duration(nil) == nil)
        #expect(BadgeText.duration(.infinity) == nil)
    }

    @Test func datesSayHowFarAwayTheyAre() {
        let now = at(8, 12)
        func distance(_ date: Date) -> String { BadgeText.distance(to: date, now: now, calendar: calendar) }
        #expect(distance(at(8, 23)) == "Today")
        #expect(distance(at(9, 1)) == "Tomorrow")
        #expect(distance(at(7, 23)) == "Yesterday")
        #expect(distance(at(17, 15)) == "In 9 days")
        #expect(distance(at(5, 15)) == "3 days ago")
        #expect(distance(at(29, 15)) == "In 3 weeks")
        #expect(distance(at(8, 9, month: 2, year: 2027)) == "In 3 months")
        #expect(distance(at(8, 9, month: 12, year: 2027)) == "In 1 year")
        #expect(distance(at(1, 9, month: 1, year: 2020)) == "6 years ago")
    }

    @Test func foldersAreNamedAsFinderShowsThem() {
        let home = URL(fileURLWithPath: "/Users/ada")
        func folder(_ paths: String...) -> String? {
            BadgeText.folder(of: paths.map { URL(fileURLWithPath: $0) }, home: home)
        }
        #expect(folder("/Users/ada/Downloads/Report.pdf") == "Downloads")
        #expect(folder("/Users/ada/notes.txt") == "~")
        #expect(folder("/Users/ada/.Trash/old.txt") == "Trash")
        #expect(folder("/Users/ada/Library/Mobile Documents/com~apple~CloudDocs/Plan.key") == "iCloud Drive")
        #expect(folder("/Users/ada/Desktop/a.png", "/Users/ada/Desktop/b.png") == "Desktop")
        #expect(folder("/Users/ada/Desktop/a.png", "/Users/ada/Downloads/b.png") == nil)
        #expect(folder("/Users/ada/Desktop/Project/") == "Desktop")
        #expect(folder("/Volumes/Backup/film.mov") == "Backup")
        #expect(folder("/mach_kernel") == nil)
    }

    @Test func keysSayWhoseTheyAre() {
        #expect(BadgeText.keyMaker("Anthropic API key") == "Anthropic")
        #expect(BadgeText.keyMaker("GitHub token") == "GitHub")
        #expect(BadgeText.keyMaker("AWS access key") == "AWS")
        #expect(BadgeText.keyMaker("Google OAuth token") == "Google")
        #expect(BadgeText.keyMaker("Stripe key") == "Stripe")
        #expect(BadgeText.keyMaker("JSON web token") == "JWT")
        #expect(BadgeText.keyMaker("Private key") == "Private")
        #expect(BadgeText.keyMaker("API key") == nil)
        #expect(BadgeText.keyMaker(nil) == nil)
        for (_, name) in ContentClassifier.secretPrefixes where name != "API key" {
            #expect(BadgeText.keyMaker(name) != nil, "\(name)")
        }
    }

    @Test func linksSayWhatTheyOpen() {
        #expect(BadgeText.musicKind(URL(string: "https://open.spotify.com/album/2Kh43m04B1UkVcpcRa1Zug")) == "Album")
        #expect(BadgeText.musicKind(URL(string: "https://open.spotify.com/track/abc")) == "Track")
        #expect(BadgeText.musicKind(URL(string: "https://music.apple.com/gb/playlist/todays-hits/pl.f4d1")) == "Playlist")
        #expect(BadgeText.musicKind(URL(string: "https://open.spotify.com/")) == nil)
        #expect(BadgeText.linkedType(URL(string: "https://example.com/files/Report.pdf")) == "PDF")
        #expect(BadgeText.linkedType(URL(string: "https://example.com/index.html")) == nil)
        #expect(BadgeText.linkedType(URL(string: "https://developer.apple.com/design/human-interface-guidelines")) == nil)
        #expect(BadgeText.linkedType(URL(string: "https://example.com")) == nil)
    }

    @Test func coloursSayHowTheyWereWritten() {
        #expect(BadgeText.colourFormat("#2F6FED") == "HEX")
        #expect(BadgeText.colourFormat("rgba(47, 111, 237, 0.5)") == "RGB")
        #expect(BadgeText.colourFormat("blue") == nil)
        #expect(BadgeText.opacity(0.5) == "50%")
        #expect(BadgeText.opacity(1) == nil)
    }

    @Test func spokenTimesReadAsASentence() {
        let now = at(8, 12)
        #expect(plain(BadgeText.spokenTime(at(8, 9, 30), now: now, calendar: calendar, locale: us)) == "at 9:30 AM")
        #expect(plain(BadgeText.spokenTime(at(7, 15, 41), now: now, calendar: calendar, locale: us))
            == "yesterday at 3:41 PM")
        #expect(BadgeText.spokenTime(at(2, 15, 41), now: now, calendar: calendar, locale: uk) == "on Monday")
        #expect(BadgeText.spokenTime(at(1, 15, 41), now: now, calendar: calendar, locale: uk) == "on 1 November")
    }
}
