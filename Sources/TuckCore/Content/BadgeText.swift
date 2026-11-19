import Foundation

/// The words a tile's line of details shows: a file's type, its size, how many things a folder or stack
/// holds, where it is, how long a text or a song is, and when it was copied. Worked out here, beside
/// search, so a word typed in the field reads back what the tiles say.
public enum BadgeText {
    /// Types better known by their app's name than by their letters.
    private static let typeNames = ["key": "Keynote", "pages": "Pages", "numbers": "Numbers", "app": "App",
                                    "markdown": "Markdown", "md": "Markdown", "webloc": "Link"]

    /// A file's type as its badge names it, from the end of its name: short ones in capitals ("PDF",
    /// "PNG", "HEIC"), longer ones as a word ("Swift", "Sketch"), and "File" for a name without one.
    public static func type(forExtension pathExtension: String) -> String {
        let ext = pathExtension.lowercased()
        if let name = typeNames[ext] { return name }
        guard !ext.isEmpty else { return "File" }
        return ext.count <= 4 ? ext.uppercased() : ext.prefix(1).uppercased() + ext.dropFirst()
    }

    /// "2.4 MB", the way Finder writes sizes (a megabyte is a million bytes). Nil for no size or none at
    /// all, so a file that has gone shows no size rather than "Zero KB".
    public static func size(_ byteCount: Int?) -> String? {
        guard let byteCount, byteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// "1 item", "12 items": what a folder holds.
    public static func items(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    /// "3 files": what a stack, or a copy of several files, holds.
    public static func files(_ count: Int) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }

    /// "1 word", "240 words": how long a text is.
    public static func words(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count) words"
    }

    /// "1 line", "12 lines": how long a piece of code is.
    public static func lines(_ count: Int) -> String {
        count == 1 ? "1 line" : "\(count) lines"
    }

    /// How many words a text holds, as a word processor counts them, so text without spaces between
    /// its words (Japanese, say) is counted too.
    public static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    /// How many lines a text runs to, blank lines at its start and end aside.
    public static func lineCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .newlines)
        return trimmed.isEmpty ? 0 : trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    /// "1:34", "1:02:03": a song's or a film's length. Nil when there is none to give.
    public static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 1 else { return nil }
        let whole = Int(seconds.rounded())
        let (hours, minutes, rest) = (whole / 3600, whole % 3600 / 60, whole % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// How far a date is from today: "Today", "Tomorrow", "In 3 days", "2 weeks ago", "In 5 months",
    /// "1 year ago". Days up to a fortnight, weeks up to two months, then months and years.
    public static func distance(to date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let from = calendar.startOfDay(for: now), to = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        func say(_ count: Int, _ unit: String) -> String {
            let amount = "\(abs(count)) \(unit)\(abs(count) == 1 ? "" : "s")"
            return count > 0 ? "In " + amount : amount + " ago"
        }
        switch abs(days) {
        case 0: return "Today"
        case 1: return days > 0 ? "Tomorrow" : "Yesterday"
        case ..<14: return say(days, "day")
        case ..<60: return say(days / 7, "week")
        default:
            let months = calendar.dateComponents([.month], from: from, to: to).month ?? days / 30
            return abs(months) < 12 ? say(months, "month") : say(months / 12, "year")
        }
    }

    /// The folder something is in, by name: "Downloads", "~" for the home folder, "iCloud Drive" and
    /// "Trash". Nil when the files are in different folders, or at the top of a disk.
    public static func folder(of urls: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let parents = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL.path })
        guard parents.count == 1, let parent = parents.first, parent != "/" else { return nil }
        let home = home.standardizedFileURL.path
        switch parent {
        case home: return "~"
        case home + "/.Trash": return "Trash"
        case home + "/Library/Mobile Documents/com~apple~CloudDocs": return "iCloud Drive"
        default: return (parent as NSString).lastPathComponent
        }
    }

    /// Whose a key is, from what it was recognised as: "Anthropic", "GitHub", "AWS", "JWT". Nil for a key
    /// that could be anyone's.
    public static func keyMaker(_ name: String?) -> String? {
        guard let name else { return nil }
        if name == "JSON web token" { return "JWT" }
        for suffix in [" API key", " access key", " OAuth token", " token", " key"] where name.hasSuffix(suffix) {
            let maker = String(name.dropLast(suffix.count))
            return maker.isEmpty || maker == "API" ? nil : maker
        }
        return nil
    }

    /// What a music link opens, from its address: "Album", "Track", "Playlist", "Artist", "Episode" or
    /// "Podcast". Nil when the address doesn't say.
    public static func musicKind(_ url: URL?) -> String? {
        let kinds = ["album": "Album", "track": "Track", "song": "Track", "playlist": "Playlist", "artist": "Artist",
                     "episode": "Episode", "show": "Podcast", "podcast": "Podcast"]
        return url?.pathComponents.lazy.compactMap { kinds[$0.lowercased()] }.first
    }

    /// The type of file a link leads to, when its address ends in one: "PDF", "ZIP". Nil for a page.
    public static func linkedType(_ url: URL?) -> String? {
        let pages: Set<String> = ["html", "htm", "shtml", "xhtml", "php", "asp", "aspx", "jsp", "cgi", "cfm"]
        guard let ext = url?.pathExtension.lowercased(), !ext.isEmpty, ext.count <= 5, !pages.contains(ext),
              ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return type(forExtension: ext)
    }

    /// How a colour was written, as its badge names it: "HEX" or "RGB".
    public static func colourFormat(_ text: String) -> String? {
        let written = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if written.hasPrefix("#") { return "HEX" }
        return written.hasPrefix("rgb") ? "RGB" : nil
    }

    /// "50%": how opaque a colour is, when it isn't wholly.
    public static func opacity(_ alpha: Double) -> String? {
        alpha < 1 ? "\(Int((max(alpha, 0) * 100).rounded()))%" : nil
    }

    /// When it was copied or added, as briefly as a badge can say it: the time today, "Yesterday" and the
    /// time, the weekday within the week, and the date before that (with its year when it isn't this
    /// year's). Times follow the person's own 12- or 24-hour clock.
    public static func time(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                            locale: Locale = .current) -> String {
        let clock = date.formatted(style(locale, calendar).hour().minute())
        switch daysBefore(date, now: now, calendar: calendar) {
        case ...0: return clock
        case 1: return "Yesterday " + clock
        default: return short(date, now: now, calendar: calendar, locale: locale)
        }
    }

    /// The same, for a tile with no room for it: the time today, and otherwise the day alone.
    public static func shortTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                                 locale: Locale = .current) -> String {
        daysBefore(date, now: now, calendar: calendar) == 1 ? "Yesterday" : time(date, now: now, calendar: calendar, locale: locale)
    }

    /// The same as VoiceOver and the tooltip say it, after "Copied" or "Added": "at 3:41 PM", "yesterday
    /// at 3:41 PM", "on Monday", "on 2 November".
    public static func spokenTime(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                                  locale: Locale = .current) -> String {
        let clock = date.formatted(style(locale, calendar).hour().minute())
        let days = daysBefore(date, now: now, calendar: calendar)
        switch days {
        case ...0: return "at " + clock
        case 1: return "yesterday at " + clock
        case 2...6: return "on " + date.formatted(style(locale, calendar).weekday(.wide))
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let day = style(locale, calendar).day().month(.wide)
            return "on " + date.formatted(sameYear ? day : day.year())
        }
    }

    /// A weekday within the week, a date before that.
    private static func short(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        if daysBefore(date, now: now, calendar: calendar) < 7 {
            return date.formatted(style(locale, calendar).weekday(.abbreviated))
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = style(locale, calendar).day().month(.abbreviated)
        return date.formatted(sameYear ? day : day.year())
    }

    /// Whole days from the date's day to today's: 0 today, 1 yesterday.
    private static func daysBefore(_ date: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    }

    private static func style(_ locale: Locale, _ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
