import Foundation

/// The round badge an email address or a contact is drawn with: its initials on one of six colours, the
/// colour picked by a stable hash of who it is, so the same person keeps the same colour from one launch
/// (and one Mac) to the next.
public enum ContactBadge {
    /// The six badge colours, soft enough to sit together in a fold: Tuck Blue, then purple, green,
    /// orange, rose and teal at its lightness.
    public static let palette: [RGBAColor] = [0x7299C5, 0x9C8CCB, 0x7FB08E, 0xD69C64, 0xCF8A9C, 0x6CABB1].map(color)

    /// Tuck's ink, for letters on a badge light enough to take it.
    public static let ink = color(0x1D2430)

    /// Up to two initials from a name: its first word's and its last word's first letters, "Ada
    /// Lovelace" "AL". Digits and punctuation are skipped; any script's letters count. Empty when the
    /// name has no letter at all.
    public static func initials(name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).compactMap(firstLetter)
        return initials(of: words)
    }

    /// Up to two initials from an email address's name part, split where a dot, a dash or an underscore
    /// joins its words: "ada.lovelace@x.com" "AL", "j_smith99@x.com" "JS", "ada@x.com" "A". A "+tag" is
    /// left out. "@" when there is no letter to use.
    public static func initials(email: String) -> String {
        let local = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let name = local.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let words = name.split(whereSeparator: { ".-_".contains($0) }).compactMap(firstLetter)
        return words.isEmpty ? "@" : initials(of: words)
    }

    /// Which of `palette` a person's badge takes: FNV-1a over the key's lower-cased UTF-8, so it never
    /// changes between launches as `hashValue` would.
    public static func colorIndex(for key: String, count: Int = palette.count) -> Int {
        guard count > 0 else { return 0 }
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = normalized.utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
        return Int(hash % UInt64(count))
    }

    /// Whether letters on `color` read better in ink than in white, by WCAG contrast.
    public static func prefersInk(on color: RGBAColor) -> Bool {
        contrast(ink, color) >= contrast(RGBAColor(red: 1, green: 1, blue: 1), color)
    }

    /// The WCAG contrast ratio between two opaque colours, from 1 to 21.
    public static func contrast(_ first: RGBAColor, _ second: RGBAColor) -> Double {
        let lighter = max(first.luminance, second.luminance)
        let darker = min(first.luminance, second.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func firstLetter<S: StringProtocol>(_ word: S) -> Character? {
        word.first(where: \.isLetter)
    }

    private static func initials(of letters: [Character]) -> String {
        guard let first = letters.first else { return "" }
        let chosen = letters.count > 1 ? [first, letters[letters.count - 1]] : [first]
        return chosen.map { String($0).uppercased() }.joined()
    }

    private static func color(_ hex: UInt32) -> RGBAColor {
        RGBAColor(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}
