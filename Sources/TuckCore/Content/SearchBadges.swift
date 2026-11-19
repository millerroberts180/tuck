import Foundation

/// A search word read as one of the badges a tile wears: a file type ("pdf", "archives"), a size ("2 mb",
/// "over 10 mb", "large") or a time of day ("3pm", "15:00", "morning"). Like a kind word it becomes a
/// filter the field shows. It finds what wears that badge and also what says the word, so "pdf" still
/// finds a Preview window titled "Invoice.pdf", and "3pm" a note that reads "meet at 3pm".
///
/// Sizes are a million bytes to the megabyte, as Finder and the badges count them. "2 mb" finds 2 MB up to
/// 3 MB, "2.4 mb" 2.4 MB up to 2.5 MB; "large" (or "big", "huge") is 10 MB or more, and "small" (or
/// "tiny") under 100 KB. A time with minutes finds that minute, and one on the hour ("3pm", "15:00") the
/// whole hour; one written without am or pm that could be either ("3:41") finds both. The morning runs
/// from 5 to noon, the afternoon to 5, the evening to 9 and the night to 5 the next morning.
public struct BadgeFilter: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Any of these extensions, lowercased.
        case type(Set<String>)
        /// A size in bytes.
        case size(Range<Int>)
        /// Minutes after midnight. The night runs past midnight, so is two ranges.
        case time([Range<Int>])
    }

    public var kind: Kind
    /// The word or words as typed, lowercased.
    public var phrase: String
    /// What the field shows for it: "PDF", "Over 10 MB", "3 PM".
    public var label: String

    public init(kind: Kind, phrase: String, label: String) {
        self.kind = kind
        self.phrase = phrase
        self.label = label
    }

    /// Whether something wears this badge, or says the word.
    func holds(searchText: String, date: Date?, facts: SearchFacts, calendar: Calendar) -> Bool {
        if SearchQuery.contains(searchText, phrase) { return true }
        switch kind {
        case .type(let extensions):
            return !facts.extensions.isDisjoint(with: extensions)
                || extensions.contains { SearchQuery.contains(searchText, "." + $0) }
        case .size(let sizes):
            return facts.byteCount.map(sizes.contains) ?? false
        case .time(let ranges):
            guard let date else { return false }
            let clock = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
            return ranges.contains { $0.contains(minute) }
        }
    }

    var isType: Bool { if case .type = kind { true } else { false } }
    var isSize: Bool { if case .size = kind { true } else { false } }
    var isTime: Bool { if case .time = kind { true } else { false } }
}

/// What search knows about something beyond its words, for badge and app words: the extensions of its
/// files, its size and the app it came from. A copy carries all three from when it was copied; the fold
/// looks up a held file's size only when a search asks for one.
public struct SearchFacts: Hashable, Sendable {
    public var extensions: Set<String>
    public var byteCount: Int?
    public var sourceApp: String?

    public init(extensions: Set<String> = [], byteCount: Int? = nil, sourceApp: String? = nil) {
        self.extensions = extensions
        self.byteCount = byteCount
        self.sourceApp = sourceApp
    }
}

extension ClipboardEntry {
    /// A copy's badges, for search: its files' extensions (an image is kept as a PNG), the size it had
    /// when it was copied and the app it was copied in.
    public var searchFacts: SearchFacts {
        var extensions = Set((payload?.fileURLs ?? []).map { $0.pathExtension.lowercased() }.filter { !$0.isEmpty })
        if payload?.imageFile != nil { extensions.insert("png") }
        return SearchFacts(extensions: extensions, byteCount: payload?.byteCount, sourceApp: sourceAppName)
    }
}

extension HeldItem {
    /// The extensions of a held file, or of every file in a stack.
    public var fileExtensions: Set<String> {
        Set(fileURLs.map { $0.pathExtension.lowercased() }.filter { !$0.isEmpty })
    }
}

extension SearchQuery {
    /// Words that name a badge, each with the label the field shows for it. None is a kind word, so
    /// "images" and "video" stay kinds; "pdf" and "zip" are file types.
    static let badgeWords: [String: (label: String, kind: BadgeFilter.Kind)] = {
        var table: [String: (label: String, kind: BadgeFilter.Kind)] = [:]
        func type(_ words: [String], _ label: String, _ extensions: Set<String>) {
            for word in words { table[word] = (label, .type(extensions)) }
        }
        type(["pdf", "pdfs"], "PDF", ["pdf"])
        type(["png", "pngs"], "PNG", ["png"])
        type(["jpg", "jpgs", "jpeg", "jpegs"], "JPEG", ["jpg", "jpeg"])
        type(["gif", "gifs"], "GIF", ["gif"])
        type(["heic"], "HEIC", ["heic", "heif"])
        type(["tiff", "tif"], "TIFF", ["tiff", "tif"])
        type(["webp"], "WebP", ["webp"])
        type(["svg", "svgs"], "SVG", ["svg"])
        type(["psd", "psds"], "PSD", ["psd"])
        type(["zip", "zips"], "ZIP", ["zip"])
        type(["archive", "archives"], "Archives", ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"])
        type(["dmg", "dmgs", "disk image", "disk images"], "Disk images", ["dmg", "iso"])
        type(["pkg", "pkgs", "installer", "installers"], "Installers", ["pkg", "mpkg"])
        type(["mov", "movs"], "MOV", ["mov"])
        type(["mp4", "mp4s"], "MP4", ["mp4", "m4v"])
        type(["mp3", "mp3s"], "MP3", ["mp3"])
        type(["m4a"], "M4A", ["m4a"])
        type(["wav"], "WAV", ["wav"])
        type(["aiff", "aif"], "AIFF", ["aiff", "aif"])
        type(["flac"], "FLAC", ["flac"])
        type(["csv", "csvs"], "CSV", ["csv"])
        type(["spreadsheet", "spreadsheets", "xlsx", "xls"], "Spreadsheets", ["xlsx", "xls", "numbers", "csv"])
        type(["presentation", "presentations", "slides", "pptx", "ppt", "keynote"], "Presentations", ["key", "pptx", "ppt"])
        type(["docx"], "DOCX", ["docx", "doc"])
        type(["txt"], "TXT", ["txt"])
        type(["rtf"], "RTF", ["rtf", "rtfd"])
        type(["epub", "epubs"], "EPUB", ["epub"])
        type(["md", "markdown"], "Markdown", ["md", "markdown"])
        for word in ["large", "big", "huge"] { table[word] = ("Large", .size(largeSize..<Int.max)) }
        for word in ["small", "tiny"] { table[word] = ("Small", .size(0..<smallSize)) }
        table["morning"] = ("Morning", .time([5 * 60..<12 * 60]))
        table["afternoon"] = ("Afternoon", .time([12 * 60..<17 * 60]))
        table["evening"] = ("Evening", .time([17 * 60..<21 * 60]))
        table["night"] = ("Night", .time([21 * 60..<24 * 60, 0..<5 * 60]))
        return table
    }()

    /// "Large" is 10 MB or more; "small" under 100 KB.
    static let largeSize = 10_000_000
    static let smallSize = 100_000

    /// "2 mb", "500kb", "over 10 mb", ">10mb", "at most 1 gb".
    private static let sizePattern = try! NSRegularExpression(pattern:
        "(?<= )(?:(over|above|more than|bigger than|larger than|under|below|less than|smaller than|at least|at most|>=|<=|≥|≤|>|<) ?)?"
        + "(\\d+(?:\\.\\d+)?) ?(bytes?|b|kb|kilobytes?|mb|megabytes?|megs?|gb|gigabytes?|tb|terabytes?)(?= )",
        options: [.caseInsensitive])
    /// "3pm", "3:41 pm", "15:00", "3:41". A number alone isn't a time: it needs minutes or am or pm.
    private static let clockPattern = try! NSRegularExpression(pattern:
        "(?<= )(2[0-3]|[01]?\\d)(?::([0-5]\\d))? ?(am|pm|a\\.m\\.|p\\.m\\.)?(?= )", options: [.caseInsensitive])

    /// The first size or time of day written between spaces in `text`, with what it reads as; only one
    /// that reads as `label`, when one is given.
    static func firstWrittenBadge(in text: String, label: String? = nil) -> (range: Range<String.Index>, filter: BadgeFilter)? {
        let whole = NSRange(text.startIndex..., in: text)
        var found: [(range: Range<String.Index>, filter: BadgeFilter)] = []
        for (pattern, read) in [(sizePattern, size(from:in:)), (clockPattern, clock(from:in:))] {
            for match in pattern.matches(in: text, range: whole) {
                guard let range = Range(match.range, in: text), let filter = read(match, text),
                      label == nil || filter.label == label else { continue }
                found.append((range, filter))
                break
            }
        }
        return found.min { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func size(from match: NSTextCheckingResult, in text: String) -> BadgeFilter? {
        func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { text[$0].lowercased() } }
        guard let number = group(2), let amount = Double(number), let unit = group(3) else { return nil }
        let (scale, unitLabel): (Double, String) = switch unit.prefix(1) {
        case "k": (1e3, "KB")
        case "m": (1e6, "MB")
        case "g": (1e9, "GB")
        case "t": (1e12, "TB")
        default: (1, "bytes")
        }
        let bytes = Int((amount * scale).rounded())
        let written = "\(number) \(unitLabel)"
        let phrase = Range(match.range, in: text).map { text[$0].lowercased() } ?? written
        switch group(1) {
        case "over", "above", "more than", "bigger than", "larger than", ">":
            return BadgeFilter(kind: .size(bytes + 1..<Int.max), phrase: phrase, label: "Over " + written)
        case "under", "below", "less than", "smaller than", "<":
            return BadgeFilter(kind: .size(0..<bytes), phrase: phrase, label: "Under " + written)
        case "at least", ">=", "≥":
            return BadgeFilter(kind: .size(bytes..<Int.max), phrase: phrase, label: "At least " + written)
        case "at most", "<=", "≤":
            return BadgeFilter(kind: .size(0..<bytes + 1), phrase: phrase, label: "At most " + written)
        default:
            // Up to the next step of the last digit typed: "2" to 3, "2.4" to 2.5.
            let decimals = number.split(separator: ".").dropFirst().first?.count ?? 0
            let step = pow(10, -Double(decimals))
            let upper = Int(((amount + step) * scale).rounded())
            return BadgeFilter(kind: .size(bytes..<max(upper, bytes + 1)), phrase: phrase, label: written)
        }
    }

    private static func clock(from match: NSTextCheckingResult, in text: String) -> BadgeFilter? {
        func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { text[$0].lowercased() } }
        guard let hourText = group(1), let hour = Int(hourText) else { return nil }
        let minutes = group(2)
        let meridiem = group(3)?.replacingOccurrences(of: ".", with: "")
        guard minutes != nil || meridiem != nil else { return nil }
        let minute = minutes.flatMap { Int($0) } ?? 0
        let hours: [Int]
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            hours = [hour % 12 + (meridiem == "pm" ? 12 : 0)]
        } else {
            // "3:41" could be either; "15:41" and "0:41" only one.
            hours = (1...12).contains(hour) ? [hour % 12, hour % 12 + 12] : [hour]
        }
        let ranges = hours.map { start in
            minute == 0 ? start * 60..<start * 60 + 60 : start * 60 + minute..<start * 60 + minute + 1
        }
        let label = meridiem.map { "\(hour)" + (minutes.map { ":" + $0 } ?? "") + " " + $0.uppercased() }
            ?? "\(hourText):\(minutes ?? "00")"
        let phrase = Range(match.range, in: text).map { text[$0].lowercased() } ?? label.lowercased()
        return BadgeFilter(kind: .time(ranges), phrase: phrase, label: label)
    }
}
