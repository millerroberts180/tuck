import Foundation

public enum HeldItemKind: String, Codable, Sendable, CaseIterable {
    case file
    case link
    case music
    case text
    /// Several files dropped together, kept as one row that drags out as all of them.
    case stack
}

/// An explicit reference or payload the person dropped or held. Files are kept as references to the
/// original location; Tuck never moves or duplicates them.
public struct HeldItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var kind: HeldItemKind
    /// File URL for `.file`, web or app URL for `.link` and `.music`.
    public var url: URL?
    /// Payload for `.text`.
    public var text: String?
    public var title: String
    public var sourceAppName: String?
    public var addedAt: Date
    /// Members of a `.stack`, in drop order.
    public var children: [HeldItem]?
    /// Bookmark for a `.file`, so a file that is moved or renamed after the drop is still found.
    public var bookmark: Data?

    public init(
        id: UUID = UUID(),
        kind: HeldItemKind,
        url: URL? = nil,
        text: String? = nil,
        title: String,
        sourceAppName: String? = nil,
        addedAt: Date = Date(),
        children: [HeldItem]? = nil,
        bookmark: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.text = text
        self.title = title
        self.sourceAppName = sourceAppName
        self.addedAt = addedAt
        self.children = children
        self.bookmark = bookmark
    }

    public static func file(_ url: URL, sourceAppName: String? = nil, addedAt: Date = Date()) -> HeldItem {
        HeldItem(kind: .file, url: url, title: url.lastPathComponent, sourceAppName: sourceAppName, addedAt: addedAt)
    }

    public static func link(_ url: URL, title: String? = nil, sourceAppName: String? = nil, addedAt: Date = Date()) -> HeldItem {
        HeldItem(kind: .link, url: url, title: title ?? HeldItem.linkTitle(for: url), sourceAppName: sourceAppName, addedAt: addedAt)
    }

    public static func music(_ url: URL, title: String? = nil, sourceAppName: String? = nil, addedAt: Date = Date()) -> HeldItem {
        HeldItem(kind: .music, url: url, title: title ?? HeldItem.musicTitle(for: url), sourceAppName: sourceAppName, addedAt: addedAt)
    }

    public static func text(_ text: String, sourceAppName: String? = nil, addedAt: Date = Date()) -> HeldItem {
        HeldItem(kind: .text, text: text, title: HeldItem.textTitle(for: text), sourceAppName: sourceAppName, addedAt: addedAt)
    }

    /// One row for several files. The title counts them; the subtitle names their shared folder.
    public static func stack(_ members: [HeldItem], sourceAppName: String? = nil, addedAt: Date = Date()) -> HeldItem {
        HeldItem(kind: .stack, title: HeldItem.stackTitle(count: members.count), sourceAppName: sourceAppName,
                 addedAt: addedAt, children: members)
    }

    /// File references carried by this item: the file itself, or every file in a stack.
    public var fileURLs: [URL] {
        switch kind {
        case .file: return url.map { [$0] } ?? []
        case .stack: return (children ?? []).flatMap(\.fileURLs)
        case .link, .music, .text: return []
        }
    }

    /// Short secondary line: folder for files, host for links, provider for music, length for text.
    public var subtitle: String {
        switch kind {
        case .file:
            return url?.deletingLastPathComponent().lastPathComponent ?? ""
        case .link:
            return url?.host ?? url?.absoluteString ?? ""
        case .music:
            return HeldItemClassifier.musicProvider(for: url) ?? "Music link"
        case .text:
            let count = text?.count ?? 0
            return count == 1 ? "1 character" : "\(count) characters"
        case .stack:
            let folders = Set(fileURLs.map { $0.deletingLastPathComponent().lastPathComponent })
            if folders.count == 1, let folder = folders.first { return folder }
            return sourceAppName.map { "From \($0)" } ?? "Several folders"
        }
    }

    public mutating func updateText(_ newValue: String) {
        guard kind == .text else { return }
        text = newValue
        title = HeldItem.textTitle(for: newValue)
    }

    static func stackTitle(count: Int) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }

    static func textTitle(for text: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return "Text" }
        return firstLine.count > 64 ? String(firstLine.prefix(63)) + "…" : firstLine
    }

    static func linkTitle(for url: URL) -> String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return host }
        let lastComponent = url.lastPathComponent.replacingOccurrences(of: "-", with: " ")
        return "\(host) · \(lastComponent)"
    }

    static func musicTitle(for url: URL) -> String {
        let provider = HeldItemClassifier.musicProvider(for: url) ?? "Music"
        let path = url.pathComponents.filter { $0 != "/" }
        if let type = path.first(where: { ["track", "album", "playlist", "song", "artist"].contains($0) }) {
            return "\(provider) \(type)"
        }
        return "\(provider) link"
    }
}
