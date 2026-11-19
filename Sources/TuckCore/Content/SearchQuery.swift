import Foundation

/// What a search in the panel asks for: type words ("images", "code") pick kinds, date words ("yesterday",
/// "last week") pick a span, and the words left must all appear. So "screenshots yesterday" is every
/// screenshot from yesterday, and "links safari" every link copied in Safari. Badge words ("pdf",
/// "over 10 mb", "3pm") read what tiles wear; see `BadgeFilter`. App names ("safari", "from safari") read
/// where things came from; see `AppFilter`. All of it is local and runs over what Tuck already holds.
public struct SearchQuery: Hashable, Sendable {
    /// Words that must each appear, lowercased.
    public var terms: [String]
    /// The kinds asked for; empty means every kind.
    public var categories: Set<ContentCategory>
    /// The span asked for, if any.
    public var dateRange: DateInterval?
    /// File types, sizes and times of day asked for. Any one of the types will do; every size and one of
    /// the times must hold.
    public var badges: [BadgeFilter]
    /// The apps asked for. Any one of them will do.
    public var apps: [AppFilter]
    /// What the type, date, badge and app words were read as, in the order typed: "Images", "Yesterday".
    public var filterLabels: [String]
    /// Whose clock a time of day is read on.
    public var calendar: Calendar

    public init(terms: [String] = [], categories: Set<ContentCategory> = [], dateRange: DateInterval? = nil,
                badges: [BadgeFilter] = [], apps: [AppFilter] = [], filterLabels: [String] = [],
                calendar: Calendar = .current) {
        self.terms = terms
        self.categories = categories
        self.dateRange = dateRange
        self.badges = badges
        self.apps = apps
        self.filterLabels = filterLabels
        self.calendar = calendar
    }

    /// Nothing typed, so everything shows.
    public var isEmpty: Bool {
        terms.isEmpty && categories.isEmpty && dateRange == nil && badges.isEmpty && apps.isEmpty
    }

    /// Whether a size was asked for, so sizes are looked up only then.
    public var asksForSize: Bool { badges.contains { $0.isSize } }

    /// Words that name kinds, each with the label the field shows for it.
    static let typeWords: [String: (label: String, categories: Set<ContentCategory>)] = {
        var table: [String: (label: String, categories: Set<ContentCategory>)] = [:]
        func add(_ words: [String], _ label: String, _ categories: Set<ContentCategory>) {
            for word in words { table[word] = (label, categories) }
        }
        add(["screenshot", "screenshots", "screen shot", "screen shots"], "Screenshots", [.screenshot])
        add(["image", "images", "photo", "photos", "pic", "pics", "picture", "pictures"], "Images", [.image, .screenshot])
        add(["link", "links", "url", "urls", "website", "websites"], "Links", [.link, .music])
        add(["file", "files", "document", "documents", "doc", "docs"], "Files",
            [.file, .folder, .stack, .image, .screenshot, .audio, .video])
        add(["folder", "folders"], "Folders", [.folder])
        add(["code", "snippet", "snippets", "command", "commands"], "Code", [.code])
        add(["color", "colors", "colour", "colours"], "Colors", [.color])
        add(["email", "emails", "mail"], "Emails", [.email])
        add(["phone", "phones", "phone number", "phone numbers"], "Phone numbers", [.phone])
        add(["contact", "contacts", "vcard", "vcards"], "Contacts", [.contact])
        add(["password", "passwords", "key", "keys", "secret", "secrets", "token", "tokens"], "Keys", [.secret])
        add(["emoji", "emojis"], "Emoji", [.emoji])
        add(["address", "addresses", "place", "places"], "Addresses", [.address])
        add(["audio", "music", "song", "songs", "track", "tracks"], "Music and audio", [.audio, .music])
        add(["video", "videos", "movie", "movies"], "Videos", [.video])
        add(["window", "windows"], "Windows", [.window])
        add(["text", "texts", "note", "notes"], "Text", [.text, .richText])
        add(["path", "paths"], "Paths", [.path])
        add(["date", "dates"], "Dates", [.date])
        return table
    }()

    /// The date words, longest first so "last week" is read before "week" could be.
    static let datePhrases = ["this afternoon", "this morning", "this evening", "last night", "this week", "last week",
                              "this month", "last month", "this year", "last year", "today", "yesterday"]
    static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

    /// Reads a search as typed. `apps` are the apps things in Tuck came from, whose names read as apps.
    public static func parse(_ text: String, apps known: [SourceApp] = [], now: Date = Date(),
                             calendar: Calendar = .current) -> SearchQuery {
        var query = SearchQuery(calendar: calendar)
        var remaining = " " + text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) + " "
        var labelled: [(position: Int, label: String)] = []

        func take(_ phrase: String) -> Int? {
            guard let range = remaining.range(of: " " + phrase + " ") else { return nil }
            let position = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
            // Spaces as long as the phrase, so what is found later keeps its place in the text as typed.
            remaining.replaceSubrange(range, with: String(repeating: " ", count: phrase.count + 2))
            return position
        }
        // App names are matched with their accents aside, so the space they leave is as long as what was typed.
        func takeName(_ phrase: String) -> Int? {
            guard let range = remaining.range(of: " " + phrase + " ", options: [.diacriticInsensitive]) else { return nil }
            let position = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
            remaining.replaceSubrange(range, with: String(repeating: " ", count: remaining[range].count))
            return position
        }
        let appPhrases = known.isEmpty ? nil : appPhrases(known)
        func readApps(_ phrases: [(String, SourceApp)]) {
            for (phrase, app) in phrases {
                while let position = takeName(phrase) {
                    let filter = AppFilter(app: app, phrase: phrase)
                    query.apps.append(filter)
                    if !labelled.contains(where: { $0.label == filter.label }) { labelled.append((position, filter.label)) }
                }
            }
        }

        for phrase in datePhrases where query.dateRange == nil {
            if let position = take(phrase), let range = dateRange(for: phrase, now: now, calendar: calendar) {
                query.dateRange = range
                labelled.append((position, phrase.prefix(1).uppercased() + phrase.dropFirst()))
            }
        }
        for (index, day) in weekdays.enumerated() where query.dateRange == nil {
            if let position = take(day), let range = lastWeekday(index + 1, now: now, calendar: calendar) {
                query.dateRange = range
                labelled.append((position, day.prefix(1).uppercased() + day.dropFirst()))
            }
        }
        // "from" and a name, then whole names, before kind words, so "notes" is the Notes app when there is one.
        if let appPhrases {
            readApps(appPhrases.from)
            readApps(appPhrases.names)
        }
        // Two-word kinds first, then single words, so "phone numbers" isn't read as "phone" and "numbers".
        for word in (Array(typeWords.keys) + Array(badgeWords.keys)).sorted(by: { $0.count > $1.count }) {
            while let position = take(word) {
                let label: String
                if let match = typeWords[word] {
                    query.categories.formUnion(match.categories)
                    label = match.label
                } else if let match = badgeWords[word] {
                    query.badges.append(BadgeFilter(kind: match.kind, phrase: word, label: match.label))
                    label = match.label
                } else {
                    continue
                }
                if !labelled.contains(where: { $0.label == label }) { labelled.append((position, label)) }
            }
        }
        // A word only one app's name has, once it is clear it isn't a kind: "chrome".
        if let appPhrases { readApps(appPhrases.words) }
        // Sizes and times written out: "2 mb", "over 10 mb", "3pm", "15:00".
        while let written = firstWrittenBadge(in: remaining) {
            let position = remaining.distance(from: remaining.startIndex, to: written.range.lowerBound)
            remaining.replaceSubrange(written.range, with: String(repeating: " ", count: remaining[written.range].count))
            query.badges.append(written.filter)
            if !labelled.contains(where: { $0.label == written.filter.label }) {
                labelled.append((position, written.filter.label))
            }
        }
        query.terms = remaining.split(whereSeparator: \.isWhitespace).map(String.init)
        query.filterLabels = labelled.sorted { $0.position < $1.position }.map(\.label)
        return query
    }

    /// The text with every word or phrase that was read as `label` taken out: what un-picking a filter
    /// leaves. "photos from safari" without "Images" is "from safari", and without "From Safari" "photos".
    public static func removing(_ label: String, from text: String, apps: [SourceApp] = []) -> String {
        func titled(_ phrase: String) -> String { phrase.prefix(1).uppercased() + phrase.dropFirst() }
        let read = apps.isEmpty ? [] : parse(text, apps: apps).apps
        let appPhrases = Set(read.map(\.phrase))
        let phrases = (typeWords.filter { $0.value.label == label }.map(\.key)
            + badgeWords.filter { $0.value.label == label }.map(\.key)
            + (datePhrases + weekdays).filter { titled($0) == label }).filter { !appPhrases.contains($0) }
            + read.filter { $0.label == label }.map(\.phrase)
        var remaining = " " + text + " "
        for phrase in phrases.sorted(by: { $0.count > $1.count }) {
            while let range = remaining.range(of: " " + phrase + " ", options: [.caseInsensitive, .diacriticInsensitive]) {
                remaining.replaceSubrange(range, with: "  ")
            }
        }
        while let written = firstWrittenBadge(in: remaining, label: label) {
            remaining.replaceSubrange(written.range, with: " ")
        }
        return remaining.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func dateRange(for phrase: String, now: Date, calendar: Calendar) -> DateInterval? {
        switch phrase {
        case "this morning": return hours(5, to: 12, of: now, calendar: calendar)
        case "this afternoon": return hours(12, to: 17, of: now, calendar: calendar)
        case "this evening": return hours(17, to: 21, of: now, calendar: calendar)
        case "last night":
            return calendar.date(byAdding: .day, value: -1, to: now).flatMap { hours(21, to: 29, of: $0, calendar: calendar) }
        case "today": return calendar.dateInterval(of: .day, for: now)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: now).flatMap { calendar.dateInterval(of: .day, for: $0) }
        case "this week": return calendar.dateInterval(of: .weekOfYear, for: now)
        case "last week":
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now).flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        case "this month": return calendar.dateInterval(of: .month, for: now)
        case "last month":
            return calendar.date(byAdding: .month, value: -1, to: now).flatMap { calendar.dateInterval(of: .month, for: $0) }
        case "this year": return calendar.dateInterval(of: .year, for: now)
        case "last year":
            return calendar.date(byAdding: .year, value: -1, to: now).flatMap { calendar.dateInterval(of: .year, for: $0) }
        default: return nil
        }
    }

    /// The hours from `start` to `end` on a day; past 24 runs into the next.
    static func hours(_ start: Int, to end: Int, of day: Date, calendar: Calendar) -> DateInterval? {
        let midnight = calendar.startOfDay(for: day)
        guard let from = calendar.date(byAdding: .hour, value: start, to: midnight),
              let to = calendar.date(byAdding: .hour, value: end, to: midnight) else { return nil }
        return DateInterval(start: from, end: to)
    }

    /// The most recent day with that weekday (1 is Sunday), today included.
    static func lastWeekday(_ weekday: Int, now: Date, calendar: Calendar) -> DateInterval? {
        let today = calendar.component(.weekday, from: now)
        let back = (today - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: now).flatMap { calendar.dateInterval(of: .day, for: $0) }
    }

    /// Whether something matches: its kind is one asked for, its date falls in the span, every word left
    /// appears somewhere in what is searched (case and accents aside), it came from one of the apps asked
    /// for, and its badges are ones asked for.
    public func matches(searchText: String, category: ContentCategory, date: Date?,
                        facts: SearchFacts = SearchFacts()) -> Bool {
        if !categories.isEmpty, !categories.contains(category) { return false }
        if let dateRange {
            guard let date, dateRange.contains(date) else { return false }
        }
        guard terms.allSatisfy({ Self.contains(searchText, $0) }) else { return false }
        if !apps.isEmpty, !apps.contains(where: { $0.holds(searchText: searchText, facts: facts) }) { return false }
        guard !badges.isEmpty else { return true }
        func holds(_ filter: BadgeFilter) -> Bool {
            filter.holds(searchText: searchText, date: date, facts: facts, calendar: calendar)
        }
        let types = badges.filter(\.isType)
        let times = badges.filter(\.isTime)
        return (types.isEmpty || types.contains(where: holds)) && badges.filter(\.isSize).allSatisfy(holds)
            && (times.isEmpty || times.contains(where: holds))
    }

    /// Whether a word appears in what is searched, case and accents aside.
    static func contains(_ searchText: String, _ word: String) -> Bool {
        searchText.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
