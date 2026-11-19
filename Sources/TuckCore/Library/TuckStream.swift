import Foundation

/// A temporary filter on the stream, shown beside the notch while the fold is shallow. No lens means
/// Everything, which is what Tuck always opens on.
public enum StreamLens: String, CaseIterable, Hashable, Sendable {
    /// Tucked windows, grouped by app.
    case windows
    /// Everything dropped in: files, links, music and text.
    case files
    /// Clipboard history, while it is on.
    case copied

    public var title: String {
        switch self {
        case .windows: "Windows"
        case .files: "Files"
        case .copied: "Copied"
        }
    }

    /// The lenses offered: Copied only while clipboard history is on.
    public static func available(includingCopied: Bool) -> [StreamLens] {
        includingCopied ? allCases : [.windows, .files]
    }
}

/// One row of the stream.
public enum StreamEntry: Identifiable, Hashable, Sendable {
    /// One app's tucked windows: a single window restores on click, several expand to their titles.
    case windows(AppWindowGroup)
    case item(HeldItem)
    case copied(ClipboardEntry)

    public var id: String {
        switch self {
        case .windows(let group): "app:\(group.id)"
        case .item(let item): "item:\(item.id)"
        case .copied(let entry): "copied:\(entry.id)"
        }
    }

    /// When it last came into Tuck: an app's most recently tucked window, an item's drop, a copy.
    public var date: Date {
        switch self {
        case .windows(let group): group.mostRecentTuck
        case .item(let item): item.addedAt
        case .copied(let entry): entry.lastCopiedAt
        }
    }

    public var lens: StreamLens {
        switch self {
        case .windows: .windows
        case .item: .files
        case .copied: .copied
        }
    }
}

/// Builds the one chronological stream: windows grouped by app, held items and copies together, newest
/// first, optionally narrowed by a lens and a search. Plain value logic, rebuilt on demand while the fold
/// is open; nothing is indexed or kept in the background.
public enum TuckStream {
    /// What a held item is, for kind words in a search. The fold passes one that remembers what it has
    /// worked out and asks the disk whether a file is a folder; the default reads the name alone.
    public typealias ItemCategory = (HeldItem) -> ContentCategory
    /// How big a held item is, for size words in a search: a file's size, a stack's files together. Asked
    /// only while a search names a size. The fold passes one that reads each file's size once and
    /// remembers it; the default knows none.
    public typealias ItemSize = (HeldItem) -> Int?

    public static func entries(windows: [ParkedWindow], items: [HeldItem], copied: [ClipboardEntry] = [],
                               lens: StreamLens? = nil, query: SearchQuery = SearchQuery(),
                               category: ItemCategory = TuckStream.category(of:),
                               size: ItemSize = { _ in nil }) -> [StreamEntry] {
        var entries: [StreamEntry] = []
        if lens == nil || lens == .windows {
            for group in WindowGrouping.groups(for: windows) {
                if let matched = match(group, query) { entries.append(.windows(matched)) }
            }
        }
        if lens == nil || lens == .files {
            entries += items.filter { matches($0, query, category: category, size: size) }.map(StreamEntry.item)
        }
        if lens == nil || lens == .copied {
            entries += copied.filter { matches($0, query) }.map(StreamEntry.copied)
        }
        // Stable: equal dates keep windows, then items, then copies, each in its own order.
        return entries.enumerated().sorted { lhs, rhs in
            lhs.element.date != rhs.element.date ? lhs.element.date > rhs.element.date : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// The stream for a search as typed: kind and day words become filters, the rest must all appear.
    public static func entries(windows: [ParkedWindow], items: [HeldItem], copied: [ClipboardEntry] = [],
                               lens: StreamLens? = nil, query: String, now: Date = Date()) -> [StreamEntry] {
        entries(windows: windows, items: items, copied: copied, lens: lens, query: SearchQuery.parse(query, now: now))
    }

    /// How many rows each lens would show for a search (all of them for none): windows count each window,
    /// not each app.
    public static func counts(windows: [ParkedWindow], items: [HeldItem], copied: [ClipboardEntry] = [],
                              query: SearchQuery = SearchQuery(),
                              category: ItemCategory = TuckStream.category(of:),
                              size: ItemSize = { _ in nil }) -> [StreamLens: Int] {
        guard !query.isEmpty else { return [.windows: windows.count, .files: items.count, .copied: copied.count] }
        return [.windows: windows.filter { matches($0, query) }.count,
                .files: items.filter { matches($0, query, category: category, size: size) }.count,
                .copied: copied.filter { matches($0, query) }.count]
    }

    /// The lens a search should leave on: the same one, unless it finds nothing there but something
    /// elsewhere, when the search steps out to Everything rather than show an empty fold.
    public static func lens(_ lens: StreamLens?, keptFor counts: [StreamLens: Int]) -> StreamLens? {
        guard let lens, counts[lens, default: 0] == 0, counts.values.contains(where: { $0 > 0 }) else { return lens }
        return nil
    }

    // MARK: Search

    /// An app's group, narrowed to the windows a search finds. A search for the app's name keeps every
    /// window, since each window is found by its app's name as well as its title. Nil when nothing in it
    /// matches.
    static func match(_ group: AppWindowGroup, _ query: SearchQuery) -> AppWindowGroup? {
        guard !query.isEmpty else { return group }
        let kept = group.windows.filter { matches($0, query) }
        return kept.isEmpty ? nil : AppWindowGroup(app: group.app, windows: kept)
    }

    public static func matches(_ window: ParkedWindow, _ query: SearchQuery) -> Bool {
        let text = [window.app.name, window.title, window.displayName ?? "", ContentCategory.window.title]
        return query.matches(searchText: text.joined(separator: "\n"), category: .window, date: window.tuckedAt,
                             facts: SearchFacts(sourceApp: window.app.name))
    }

    public static func matches(_ entry: ClipboardEntry, _ query: SearchQuery) -> Bool {
        query.matches(searchText: entry.searchText, category: entry.category, date: entry.lastCopiedAt,
                      facts: entry.searchFacts)
    }

    /// Whether a held item matches. A stack is also found by what it holds: "images" finds a stack of
    /// photos, "pdf" one with a PDF in it, and its words may be found in any of its files.
    public static func matches(_ item: HeldItem, _ query: SearchQuery,
                               category: ItemCategory = TuckStream.category(of:),
                               size: ItemSize = { _ in nil }) -> Bool {
        // A stack's files came from wherever the stack did.
        func facts(_ held: HeldItem) -> SearchFacts {
            SearchFacts(extensions: held.fileExtensions, byteCount: query.asksForSize ? size(held) : nil,
                        sourceApp: held.sourceAppName ?? item.sourceAppName)
        }
        if query.matches(searchText: searchText(for: item, category: category), category: category(item),
                         date: item.addedAt, facts: facts(item)) { return true }
        guard item.kind == .stack, !query.categories.isEmpty else { return false }
        var widened = query
        widened.categories.insert(.stack)
        return (item.children ?? []).contains { child in
            query.matches(searchText: searchText(for: child, category: category), category: category(child),
                          date: item.addedAt, facts: facts(child))
        } && widened.matches(searchText: searchText(for: item, category: category), category: .stack, date: item.addedAt,
                             facts: facts(item))
    }

    /// What a held item is from what Tuck holds, without the disk: a file's kind from its name (a folder
    /// when its URL says so), a text's from what it says.
    public static func category(of item: HeldItem) -> ContentCategory {
        switch item.kind {
        case .file:
            guard let url = item.url else { return .file }
            return ContentClassifier.category(forFile: url, isDirectory: url.hasDirectoryPath)
        case .stack: return .stack
        case .link: return .link
        case .music: return .music
        case .text: return ContentClassifier.recognize(text: item.text ?? "").category
        }
    }

    /// What a held item can be found by: its title and text, a file's name and path (every file in a
    /// stack), a link's title, domain and address, the app it came from, and its kind's name.
    static func searchText(for item: HeldItem, category: ItemCategory = TuckStream.category(of:)) -> String {
        var fields = [item.title]
        if let text = item.text { fields.append(text) }
        if let url = item.url {
            if url.isFileURL {
                fields.append(url.path)
            } else {
                fields.append(url.absoluteString)
                if let host = url.host { fields.append(host) }
            }
        }
        if let source = item.sourceAppName { fields.append(source) }
        fields.append(category(item).title)
        for child in item.children ?? [] { fields.append(searchText(for: child, category: category)) }
        return fields.joined(separator: "\n")
    }
}
