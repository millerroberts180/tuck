import SwiftUI
import TuckCore
import UniformTypeIdentifiers

/// A tile's line of details, at its foot under the title or the preview: a small mark of its kind in
/// that kind's hue (`Theme.kindMark`), then what it is and the one fact most worth a glance, "Markdown ·
/// 4 KB", in the card's quiet ink, and when it was copied or added if Settings asks. Under the pointer, in
/// keyboard focus or while the tile is open, the line adds what is worth knowing second, as far as it has
/// room: a second fact, where a file is, and the icon of the app it came from. Every fact is said in the
/// tooltip and VoiceOver too.
///
/// A line too narrow for all of it keeps the time when it is asked for, then the kind and its first fact;
/// the time shortens to "Yesterday", and the last of it ends in an ellipsis rather than being cut.
///
/// The app's icon is worn by what was copied or dropped from an app: words, links, code, colours, people
/// and places, and copied images, where the app (a browser, a design tool) tells one picture from another.
/// Files from Finder don't wear it, since nearly every file comes from there and where it is already says
/// enough; a file from any other app (a mail attachment, say) does. Screenshots don't, since the
/// Screenshot tool is all they come from, and nor does anything Tuck itself copied.
struct TileMeta: View {
    /// The line's height, the same on every card, so titles and previews above it line up across a row.
    static let height: CGFloat = 14

    let content: TileContent
    var showsTime = false
    /// Hovered, focused or open: the line shows its second facts.
    var revealsMore = false
    @State private var measured: Fact?

    var body: some View {
        let facts = Facts(content)
        let details = [facts.before, measured ?? facts.known, facts.after].compactMap { $0 }
        let first = details.first, second = details.dropFirst().first
        let time = showsTime ? BadgeText.time(content.date) : nil
        let shortTime = showsTime ? BadgeText.shortTime(content.date) : nil
        let lines: [Line] = revealsMore
            ? [Line([facts.type, first, second, facts.place], time: time, app: facts.app),
               Line([facts.type, first, second], time: time, app: facts.app),
               Line([facts.type, first], time: time, app: facts.app),
               Line([facts.type, first], time: shortTime, app: facts.app),
               Line([facts.type], time: shortTime, app: facts.app)]
            : [Line([facts.type, first], time: time), Line([facts.type, first], time: shortTime),
               Line([facts.type], time: shortTime)]
        let last = Line([facts.type, first], time: shortTime)
        MetaLine(mark: facts.type?.symbol, category: content.category, lines: lines, last: last)
            .task(id: content.id) {
                guard facts.known == nil else { return }
                measured = await facts.load()
            }
    }

    /// What VoiceOver and the tooltip add for a tile's details: "PDF", "2.4 MB", "in Downloads", "from
    /// Safari" and, while times are shown, "copied at 3:41 PM". What the tile's title already says (that it
    /// is a text, a colour) is left out, and so is a count not made yet.
    @MainActor static func spoken(_ content: TileContent, showsTime: Bool, copied: Bool) -> [String] {
        let facts = Facts(content)
        // A held file's help already says which folder it is in.
        let place = copied || content.category == .stack ? facts.place : nil
        var spoken = [facts.type, facts.before, facts.known, facts.after, place, facts.app].compactMap { $0?.spoken }
        if showsTime { spoken.append((copied ? "copied " : "added ") + BadgeText.spokenTime(content.date)) }
        return spoken
    }

    /// One fact on the line: a word or two, or an app's icon.
    struct Fact: Hashable {
        var symbol: String?
        var text: String?
        /// An app's icon, in place of words.
        var icon: NSImage?
        /// What the tooltip and VoiceOver say for it; nil when the tile's title says it already.
        var spoken: String?

        init(symbol: String? = nil, text: String? = nil, icon: NSImage? = nil) {
            self.symbol = symbol
            self.text = text
            self.icon = icon
            spoken = text
        }

        func said(_ words: String?) -> Fact {
            var fact = self
            fact.spoken = words
            return fact
        }
    }

    /// One way to set out the line: its words in order, then the time and the app's icon at its end.
    struct Line: Hashable {
        var words: [String]
        var time: String?
        var app: NSImage?

        init(_ facts: [Fact?], time: String? = nil, app: Fact? = nil) {
            var words: [String] = []
            for word in facts.compactMap({ $0?.text }) where !words.contains(word) { words.append(word) }
            self.words = words
            self.time = time
            self.app = app?.icon
        }
    }

    /// What a tile's line says, from what it holds: its kind, the facts read from it at once, the one
    /// counted or measured later, where it is and the app it came from.
    @MainActor private struct Facts {
        enum Measure {
            case none
            /// Recorded when it was copied: an image's.
            case bytes(Int?)
            case file(URL)
            /// How many things it holds.
            case folder(URL)
            /// Their sizes together.
            case files([URL])
            case words(String)
            case lines(String)
        }

        var type: Fact?
        /// Facts known at once, before and after the measured one.
        var before: Fact?
        var after: Fact?
        var measure: Measure = .none
        var place: Fact?
        var app: Fact?
        let id: UUID

        init(_ content: TileContent) {
            id = content.id
            let urls = content.fileURLs
            let recognition = content.recognition
            var wearsApp = true
            if let image = content.payload, image.imageFile != nil, urls.isEmpty {
                let isScreenshot = content.category == .screenshot
                type = Fact(symbol: isScreenshot ? "camera.viewfinder" : "photo", text: "PNG")
                // The title says the size in pixels already, for VoiceOver; on the card it is the first fact.
                before = ContentKinds.dimensions(image).map { Fact(text: $0).said(nil) }
                measure = .bytes(image.byteCount)
                wearsApp = !isScreenshot
            } else if content.category == .stack || urls.count > 1 {
                type = Fact(symbol: "square.stack.3d.up", text: BadgeText.files(max(urls.count, content.children.count)))
                measure = .files(urls)
                place = Self.place(of: urls.isEmpty ? content.children.flatMap(\.fileURLs) : urls)
                wearsApp = Self.isFromAnotherApp(content)
            } else if let url = urls.first {
                if content.category == .folder {
                    type = Fact(symbol: "folder", text: "Folder")
                    measure = .folder(url)
                } else {
                    type = Fact(symbol: Self.symbol(forExtension: url.pathExtension),
                                text: BadgeText.type(forExtension: url.pathExtension))
                    measure = .file(url)
                    before = BadgeText.duration(content.preview?.duration).map { Fact(text: $0) }
                }
                place = Self.place(of: [url])
                wearsApp = Self.isFromAnotherApp(content)
            } else {
                switch content.category {
                case .text:
                    type = Fact(symbol: "text.alignleft", text: "Text").said(nil)
                    measure = .words(content.text)
                case .richText:
                    type = Fact(symbol: "textformat", text: "Rich text").said(nil)
                    measure = .words(content.text)
                case .code:
                    type = Fact(symbol: "chevron.left.forwardslash.chevron.right", text: recognition.language ?? "Code")
                        .said(recognition.language)
                    measure = .lines(content.text)
                case .link:
                    // With a page title over it, the line names the site the title came from.
                    let site = content.title?.isEmpty == false ? TileText.site(of: content.linkURL) : nil
                    type = Fact(symbol: "link", text: site ?? "Link").said(site.map { "on " + $0 })
                    before = BadgeText.linkedType(content.linkURL).map { Fact(text: $0).said("links to a \($0)") }
                case .music:
                    type = Fact(symbol: "music.note", text: recognition.name ?? "Music").said(recognition.name)
                    before = BadgeText.musicKind(content.linkURL).map { Fact(text: $0) }
                case .email: type = Fact(symbol: "envelope", text: "Email").said(nil)
                case .phone: type = Fact(symbol: "phone", text: "Phone").said(nil)
                case .contact: type = Fact(symbol: "person.crop.circle", text: "Contact").said(nil)
                case .color:
                    type = Fact(symbol: "paintpalette", text: "Color").said(nil)
                    before = BadgeText.colourFormat(content.text).map { Fact(text: $0).said("written as \($0)") }
                    after = recognition.color.flatMap { BadgeText.opacity($0.alpha) }
                        .map { Fact(text: $0).said("\($0) opaque") }
                case .date:
                    type = Fact(symbol: "calendar", text: "Date").said(nil)
                    let distance = BadgeText.distance(to: recognition.date ?? content.date)
                    before = Fact(text: distance).said(distance.lowercased())
                case .address:
                    // The street is the title; the line says the town it is in.
                    let place = TileText.addressLines(content).place
                    type = Fact(symbol: "mappin.and.ellipse", text: place ?? "Address").said(nil)
                case .emoji:
                    // Its name is the title.
                    type = Fact(symbol: "face.smiling", text: "Emoji").said(nil)
                case .secret:
                    type = Fact(symbol: "key", text: "Key").said(nil)
                    before = BadgeText.keyMaker(recognition.name).map { Fact(text: $0).said(nil) }
                case .path:
                    let url = TileText.pathURL(content.text)
                    let status = ItemDetails.status(ofPath: url)
                    if status.isDirectory {
                        type = Fact(symbol: "folder", text: "Folder")
                        measure = .folder(url)
                    } else {
                        type = Fact(symbol: Self.symbol(forExtension: url.pathExtension),
                                    text: BadgeText.type(forExtension: url.pathExtension))
                        if status.exists { measure = .file(url) }
                    }
                    if !status.exists { before = Fact(text: "Not found").said("not found") }
                case .window: type = Fact(symbol: "macwindow", text: "Window").said(nil)
                default: type = Fact(symbol: "doc", text: content.category.title).said(nil)
                }
            }
            if wearsApp, let name = content.sourceAppName,
               let icon = ItemDetails.appIcon(bundleID: content.sourceBundleID, name: name) {
                app = Fact(icon: icon).said("from " + name)
            }
        }

        /// Whether a file came from somewhere other than Finder, and so wears that app's icon.
        private static func isFromAnotherApp(_ content: TileContent) -> Bool {
            content.sourceBundleID.map { $0 != "com.apple.finder" } ?? (content.sourceAppName != "Finder")
        }

        private static func place(of urls: [URL]) -> Fact? {
            BadgeText.folder(of: urls).map { folder in
                Fact(symbol: "folder", text: "in " + folder).said(folder == "~" ? "in your home folder" : "in " + folder)
            }
        }

        /// The measured fact as already known: recorded, read or counted earlier while the panel has been
        /// open, or a short text counted now.
        var known: Fact? {
            switch measure {
            case .none: return nil
            case .bytes(let bytes): return BadgeText.size(bytes).map { Fact(text: $0) }
            case .file(let url): return FileSizes.knownByteCount(of: url).flatMap { BadgeText.size($0) }.map { Fact(text: $0) }
            case .folder(let url):
                return FileSizes.knownItemCount(inFolder: url).flatMap { $0.map { Fact(text: BadgeText.items($0)) } }
            case .files(let urls):
                let known = urls.map(FileSizes.knownByteCount(of:))
                guard !known.contains(where: { $0 == nil }) else { return nil }
                return BadgeText.size(known.compactMap { $0 ?? nil }.reduce(0, +)).map { Fact(text: $0) }
            case .words(let text): return TextCounts.known(id, text, lines: false).flatMap(Self.words)
            case .lines(let text): return TextCounts.known(id, text, lines: true).flatMap(Self.lines)
            }
        }

        /// The measured fact, read or counted off the main thread where it hasn't been.
        func load() async -> Fact? {
            switch measure {
            case .none, .bytes: return known
            case .file(let url): return BadgeText.size(await FileSizes.loadByteCount(of: url)).map { Fact(text: $0) }
            case .folder(let url): return await FileSizes.itemCount(inFolder: url).map { Fact(text: BadgeText.items($0)) }
            case .files(let urls):
                var total = 0
                for url in urls { total += await FileSizes.loadByteCount(of: url) ?? 0 }
                return BadgeText.size(total).map { Fact(text: $0) }
            case .words(let text): return Self.words(await TextCounts.count(id, text, lines: false))
            case .lines(let text): return Self.lines(await TextCounts.count(id, text, lines: true))
            }
        }

        /// A text of a word or two says nothing by counting them, nor a one-line command.
        private static func words(_ count: Int) -> Fact? { count > 1 ? Fact(text: BadgeText.words(count)) : nil }
        private static func lines(_ count: Int) -> Fact? { count > 1 ? Fact(text: BadgeText.lines(count)) : nil }

        /// A symbol for a file's type, from what the system knows of its extension.
        static func symbol(forExtension pathExtension: String) -> String {
            guard let type = UTType(filenameExtension: pathExtension) else { return "doc" }
            let symbols: [(UTType, String)] = [
                (.pdf, "doc.richtext"), (.image, "photo"), (.movie, "film"), (.audio, "waveform"),
                (.archive, "doc.zipper"), (.diskImage, "externaldrive"),
                (.sourceCode, "chevron.left.forwardslash.chevron.right"), (.spreadsheet, "tablecells"),
                (.presentation, "rectangle.on.rectangle"), (.application, "app"), (.font, "textformat"),
                (.text, "doc.text")
            ]
            return symbols.first { type.conforms(to: $0.0) }?.1 ?? "doc"
        }
    }

    /// The line itself: the kind's mark, then the first of `lines`, widest first, that fits, and `last`,
    /// cut short with an ellipsis, when none does.
    struct MetaLine: View {
        let mark: String?
        let category: ContentCategory
        let lines: [Line]
        let last: Line

        var body: some View {
            HStack(spacing: 5) {
                if let mark {
                    Image(systemName: mark)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.kindMark(for: category))
                        .frame(width: 13)
                }
                ViewThatFits(in: .horizontal) {
                    ForEach(Self.distinct(lines), id: \.self) { LineView(line: $0) }
                    LineView(line: last)
                }
            }
            .font(.tileMeta)
            .lineLimit(1)
            .frame(height: TileMeta.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        /// The lines to try, each once.
        private static func distinct(_ lines: [Line]) -> [Line] {
            var seen: [Line] = []
            for line in lines where !seen.contains(line) { seen.append(line) }
            return seen
        }
    }

    private struct LineView: View {
        let line: Line

        var body: some View {
            HStack(spacing: 5) {
                Text(words)
                    .foregroundStyle(Theme.secondaryText)
                    .truncationMode(.tail)
                if line.time != nil || line.app != nil { Spacer(minLength: 0) }
                if let time = line.time {
                    Text(time).foregroundStyle(Theme.tertiaryText)
                }
                if let app = line.app {
                    // An app's icon has a shape of its own, so it stands bare on the card, drawn a little
                    // past the line, since an icon's art sits inside its canvas.
                    Image(nsImage: app).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .frame(width: TileMeta.height + 2, height: TileMeta.height + 2)
                        .padding(-1)
                }
            }
        }

        /// The words with a quiet dot between them.
        private var words: AttributedString {
            var text = AttributedString()
            for (index, word) in line.words.enumerated() {
                if index > 0 {
                    var dot = AttributedString(" · ")
                    dot.foregroundColor = Theme.tertiaryText
                    text += dot
                }
                text += AttributedString(word)
            }
            return text
        }
    }
}

extension Font {
    /// A tile's line of details: the one place under 12 pt, since it is a line to glance at and its words
    /// are all in the tooltip and VoiceOver.
    static let tileMeta = Font.system(.subheadline).monospacedDigit()
}
