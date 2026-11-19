import Foundation

/// An app that something in Tuck came from, as search knows it: the name it gave when something was
/// copied or dropped, and any other name it goes by (its bundle's name when that differs, so "Visual
/// Studio Code" finds what Code copied).
public struct SourceApp: Hashable, Sendable {
    public var name: String
    public var bundleID: String?
    public var aliases: [String]

    public init(name: String, bundleID: String? = nil, aliases: [String] = []) {
        self.name = name
        self.bundleID = bundleID
        self.aliases = aliases
    }

    /// Every name it is known by, its own first.
    public var names: [String] { [name] + aliases }

    /// Whether something that says it came from `source` came from this app, case and accents aside.
    func isSource(_ source: String) -> Bool {
        names.contains { $0.compare(source, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    /// The apps the history and the held items came from, once each, in the order first met. Tuck's own
    /// copies are left out: Tuck isn't somewhere a person copies from.
    public static func known(copied: [ClipboardEntry], items: [HeldItem], excludingBundleID tuck: String? = nil)
        -> [SourceApp] {
        var apps: [SourceApp] = []
        var seen: Set<String> = []
        func add(_ name: String?, _ bundleID: String?) {
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name != "Tuck",
                  bundleID == nil || bundleID != tuck, seen.insert(name.lowercased()).inserted else { return }
            apps.append(SourceApp(name: name, bundleID: bundleID))
        }
        for entry in copied { add(entry.sourceAppName, entry.sourceBundleID) }
        for item in items { add(item.sourceAppName, nil) }
        return apps
    }
}

/// A search word read as an app: its name ("safari"), "from" and its name ("from safari"), or a word only
/// one known app's name has ("chrome" for Google Chrome). It finds what came from that app, and anything
/// that says the word.
public struct AppFilter: Hashable, Sendable {
    public var app: SourceApp
    /// The word or words as typed, lowercased.
    public var phrase: String

    public init(app: SourceApp, phrase: String) {
        self.app = app
        self.phrase = phrase
    }

    /// What the field shows for it: "From Safari".
    public var label: String { "From " + app.name }

    func holds(searchText: String, facts: SearchFacts) -> Bool {
        SearchQuery.contains(searchText, phrase) || facts.sourceApp.map(app.isSource) == true
    }
}

extension SearchQuery {
    /// Words in app names too common to stand for one app on their own.
    static let genericAppWords: Set<String> = [
        "the", "and", "for", "app", "apps", "pro", "plus", "max", "mini", "lite", "mac", "macos", "desktop", "studio",
        "browser", "editor", "player", "viewer", "reader", "settings", "system", "monitor", "manager", "store",
        "center", "centre", "utility", "utilities", "assistant", "edition", "developer", "beta", "canary", "nightly",
        "preview", "insiders", "community", "new", "classic", "client", "helper", "agent", "tools", "online", "cloud",
        "google", "microsoft", "adobe", "apple", "jetbrains", "mozilla"
    ]

    /// Kind words that stay kinds even when an app has that name: a chip's own word and its singular, so a
    /// chip always filters by its kind. "from music" still asks for the Music app.
    static let keptKindWords: Set<String> = Set(SearchChips.words.flatMap { word in
        [word, String(word.dropLast()), String(word.dropLast(2))].filter { typeWords[$0] != nil }
    })

    /// The phrases that read as each app, longest first: "from" and a name, then a whole name, then a word
    /// only that app's names have. A whole name that is a kind word or a badge word reads as the app
    /// ("notes" when Notes is known), unless a chip uses it; a lone word never does.
    static func appPhrases(_ apps: [SourceApp]) -> (from: [(String, SourceApp)], names: [(String, SourceApp)],
                                                   words: [(String, SourceApp)]) {
        var names: [(String, SourceApp)] = []
        var words: [String: [SourceApp]] = [:]
        for app in apps {
            var own: Set<String> = []
            for name in app.names {
                let lowered = name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
                guard lowered.count >= 2 else { continue }
                if !keptKindWords.contains(lowered) { names.append((lowered, app)) }
                let parts = lowered.split(separator: " ").map(String.init)
                guard parts.count > 1 else { continue }
                own.formUnion(parts)
            }
            for word in own { words[word, default: []].append(app) }
        }
        let wholeNames = Set(names.map(\.0))
        let distinctive: [(String, SourceApp)] = words.compactMap { word, owners in
            guard owners.count == 1, word.count >= 3, word.contains(where: \.isLetter), !wholeNames.contains(word),
                  !genericAppWords.contains(word), typeWords[word] == nil, badgeWords[word] == nil,
                  !datePhrases.contains(word), !weekdays.contains(word) else { return nil }
            return (word, owners[0])
        }
        func longestFirst(_ list: [(String, SourceApp)]) -> [(String, SourceApp)] {
            list.sorted { $0.0.count != $1.0.count ? $0.0.count > $1.0.count : $0.0 < $1.0 }
        }
        let from = (names + distinctive + keptKindWords.flatMap { word in
            apps.filter { $0.isSource(word) }.map { (word, $0) }
        }).map { ("from " + $0.0, $0.1) }
        return (longestFirst(from), longestFirst(names), longestFirst(distinctive))
    }
}
