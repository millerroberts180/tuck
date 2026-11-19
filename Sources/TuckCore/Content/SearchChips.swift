import Foundation

/// The chips over the full fold's stream, before a search and under its field during one: the filters
/// that are on and aren't kinds the stream holds (a day, say), then the kinds it holds, most first, as
/// many as fit one line. Each kind counts what the words and day typed find of it, so a chip says what a
/// click would show.
public enum SearchChips {
    public struct Chip: Identifiable, Equatable, Sendable {
        /// The word a click adds to the search.
        public let word: String
        public let label: String
        /// How many rows of this kind the search shows; nil for a filter that isn't a kind.
        public let count: Int?
        public let isOn: Bool
        public var id: String { label }

        public init(word: String, label: String, count: Int?, isOn: Bool) {
            self.word = word
            self.label = label
            self.count = count
            self.isOn = isOn
        }
    }

    /// A kind a chip can name: the word it adds to the search, its label and the categories it finds.
    public struct Kind: Sendable {
        public let word: String
        public let label: String
        public let categories: Set<ContentCategory>
    }

    /// The words the chips add, in the order they are offered when counts tie.
    static let words = ["windows", "screenshots", "images", "links", "code", "text", "files", "folders", "colors",
                        "emails", "phones", "contacts", "addresses", "dates", "keys", "emoji", "music", "videos", "paths"]

    /// The kinds a chip can name, in the order they are offered when counts tie.
    public static let kinds: [Kind] = words.compactMap { word in
        let query = SearchQuery.parse(word)
        guard let label = query.filterLabels.first else { return nil }
        return Kind(word: word, label: label, categories: query.categories)
    }

    /// - Parameters:
    ///   - categories: the kind of every row the search would show with its kind words left out, each
    ///     window on its own.
    ///   - on: the labels of the filters that are on, in the order typed.
    ///   - width: how much room the line has.
    ///   - spacing: the room between two chips.
    ///   - measure: how wide a chip draws.
    public static func chips(categories: [ContentCategory], on: [String], width: Double, spacing: Double = 6,
                             measure: (Chip) -> Double) -> [Chip] {
        var offered: [(order: Int, chip: Chip)] = kinds.enumerated().compactMap { order, kind in
            let count = categories.filter(kind.categories.contains).count
            let isOn = on.contains(kind.label)
            guard count > 0 || isOn else { return nil }
            return (order, Chip(word: kind.word, label: kind.label, count: count, isOn: isOn))
        }
        // A kind that holds everything shown says nothing as a filter, unless it's on.
        let several = offered.count > 1
        offered.removeAll { !$0.chip.isOn && $0.chip.count == categories.count && several }
        offered.sort { a, b in
            let first = (a.chip.isOn ? 1 : 0, a.chip.count ?? 0), second = (b.chip.isOn ? 1 : 0, b.chip.count ?? 0)
            return first != second ? first > second : a.order < b.order
        }
        let others = on.filter { label in !offered.contains { $0.chip.label == label } }.map { label in
            Chip(word: label.lowercased(), label: label, count: nil, isOn: true)
        }
        var shown = others
        var used = others.reduce(0) { $0 + measure($1) + spacing }
        for (_, chip) in offered where used + measure(chip) <= width {
            shown.append(chip)
            used += measure(chip) + spacing
        }
        return shown
    }
}
