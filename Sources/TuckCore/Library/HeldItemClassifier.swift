import Foundation

/// Turns dropped representations into held items. Music services are kept as openable links, never as
/// downloaded media.
public enum HeldItemClassifier {
    static let musicHosts: [String: String] = [
        "open.spotify.com": "Spotify",
        "music.apple.com": "Apple Music",
        "music.youtube.com": "YouTube Music",
        "soundcloud.com": "SoundCloud",
        "listen.tidal.com": "Tidal",
        "tidal.com": "Tidal",
        "www.deezer.com": "Deezer",
        "deezer.com": "Deezer",
        "bandcamp.com": "Bandcamp"
    ]

    static let musicSchemes: [String: String] = [
        "spotify": "Spotify",
        "music": "Apple Music",
        "itmss": "Apple Music"
    ]

    public static func kind(for url: URL) -> HeldItemKind {
        if url.isFileURL { return .file }
        return musicProvider(for: url) == nil ? .link : .music
    }

    public static func musicProvider(for url: URL?) -> String? {
        guard let url else { return nil }
        if let scheme = url.scheme?.lowercased(), let provider = musicSchemes[scheme] { return provider }
        guard let host = url.host?.lowercased() else { return nil }
        if let provider = musicHosts[host] { return provider }
        if host.hasSuffix(".bandcamp.com") { return "Bandcamp" }
        return nil
    }

    public static func item(for url: URL, sourceAppName: String? = nil, now: Date = Date()) -> HeldItem {
        switch kind(for: url) {
        case .file: return .file(url, sourceAppName: sourceAppName, addedAt: now)
        case .music: return .music(url, sourceAppName: sourceAppName, addedAt: now)
        case .link, .text, .stack: return .link(url, sourceAppName: sourceAppName, addedAt: now)
        }
    }

    /// Plain text becomes a text item, unless the whole payload is a single web or music URL, in which
    /// case it is held as a link. Blank text is ignored.
    public static func item(forText text: String, sourceAppName: String? = nil, now: Date = Date()) -> HeldItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(where: \.isWhitespace),
           let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) || musicSchemes[scheme] != nil {
            return item(for: url, sourceAppName: sourceAppName, now: now)
        }
        return .text(text, sourceAppName: sourceAppName, addedAt: now)
    }
}
