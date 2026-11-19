import Foundation

public enum ClipboardRetention: String, CaseIterable, Codable, Identifiable, Sendable {
    case oneHour, oneDay, oneWeek, untilCleared

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneHour: return "1 hour"
        case .oneDay: return "1 day"
        case .oneWeek: return "1 week"
        case .untilCleared: return "Until cleared"
        }
    }

    public var interval: TimeInterval? {
        switch self {
        case .oneHour: return 3_600
        case .oneDay: return 86_400
        case .oneWeek: return 604_800
        case .untilCleared: return nil
        }
    }
}

public struct ClipboardEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// The copy's text. For files it is their names, and for an image it is empty: what was copied is in
    /// `payload`.
    public var text: String
    public var sourceAppName: String?
    public var sourceBundleID: String?
    public var firstCopiedAt: Date
    public var lastCopiedAt: Date
    public var copyCount: Int
    /// What the copy is, worked out once when it was recorded. Missing in history saved before Tuck
    /// recognised kinds; loading fills it in.
    public var recognition: ContentRecognition?
    /// What was copied besides text: files, an image, styling.
    public var payload: ClipPayload?
    /// What Tuck learned about it afterwards: words in an image, a song's title, a page's name.
    public var preview: ClipPreview?

    public init(
        id: UUID = UUID(),
        text: String,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        firstCopiedAt: Date,
        lastCopiedAt: Date,
        copyCount: Int = 1,
        recognition: ContentRecognition? = nil,
        payload: ClipPayload? = nil,
        preview: ClipPreview? = nil
    ) {
        self.id = id
        self.text = text
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.recognition = recognition
        self.payload = payload
        self.preview = preview
    }

    public var category: ContentCategory { recognition?.category ?? .text }

    /// Two copies are the same when this is: the files, the image's digest, or else the text.
    public var identity: String { payload?.key ?? text }

    /// Everything search looks through: the text, the app it came from, the kind's name, file names, and
    /// what was recognised in it.
    public var searchText: String {
        var parts = [text, sourceAppName ?? "", category.title]
        if let names = payload?.fileURLs?.map(\.lastPathComponent) { parts += names }
        if let recognition { parts += [recognition.name ?? "", recognition.detail ?? "", recognition.language ?? "",
                                       recognition.color?.hex ?? ""] }
        if let preview { parts += [preview.recognizedText ?? "", preview.title ?? "", preview.artist ?? ""] }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// What a copy carried besides plain text. Images and styled text are kept as files beside the history,
/// named here, so the history file stays small.
public struct ClipPayload: Hashable, Codable, Sendable {
    /// Files and folders that were copied, as they were then.
    public var fileURLs: [URL]?
    /// The image, as a PNG in the clipboard folder.
    public var imageFile: String?
    /// The styled text, as RTF in the clipboard folder, so copying it back keeps the styling.
    public var richTextFile: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    /// The image's or the files' size.
    public var byteCount: Int?
    /// What makes two copies the same, when it isn't the text.
    public var key: String?

    public init(fileURLs: [URL]? = nil, imageFile: String? = nil, richTextFile: String? = nil, pixelWidth: Int? = nil,
                pixelHeight: Int? = nil, byteCount: Int? = nil, key: String? = nil) {
        self.fileURLs = fileURLs
        self.imageFile = imageFile
        self.richTextFile = richTextFile
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.key = key
    }

    /// The asset files it names.
    public var assetNames: [String] { [imageFile, richTextFile].compactMap { $0 } }
}

/// What Tuck worked out about a copy after recording it, once, in the background.
public struct ClipPreview: Hashable, Codable, Sendable {
    /// Words read from an image, so search finds a screenshot by what it shows.
    public var recognizedText: String?
    /// A song's or video's title, or a web page's.
    public var title: String?
    public var artist: String?
    /// A song's or video's length, in seconds.
    public var duration: Double?
    /// A web page's icon, and an address's map, as PNGs in the clipboard folder. Only made when online
    /// previews are on.
    public var iconFile: String?
    public var mapFile: String?
    /// The picture a web page gives for sharing it (its `og:image`), as a JPEG in the clipboard folder,
    /// small enough for a tile. Only made when the page has one.
    public var pageImageFile: String?

    public init(recognizedText: String? = nil, title: String? = nil, artist: String? = nil, duration: Double? = nil,
                iconFile: String? = nil, mapFile: String? = nil, pageImageFile: String? = nil) {
        self.recognizedText = recognizedText
        self.title = title
        self.artist = artist
        self.duration = duration
        self.iconFile = iconFile
        self.mapFile = mapFile
        self.pageImageFile = pageImageFile
    }

    public var assetNames: [String] { [iconFile, mapFile, pageImageFile].compactMap { $0 } }
}

/// One copy as the capture service read it from the pasteboard, before history decides whether to keep it.
public struct ClipboardCapture: Sendable {
    public var text: String
    public var recognition: ContentRecognition?
    public var payload: ClipPayload?
    public var pasteboardTypes: [String]
    public var sourceBundleID: String?
    public var sourceAppName: String?

    public init(text: String, recognition: ContentRecognition? = nil, payload: ClipPayload? = nil,
                pasteboardTypes: [String] = [], sourceBundleID: String? = nil, sourceAppName: String? = nil) {
        self.text = text
        self.recognition = recognition
        self.payload = payload
        self.pasteboardTypes = pasteboardTypes
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
    }
}

/// Short-term, opt-in clipboard history.
///
/// It records what is copied while enabled (text, files, images, colours, contacts), each with its kind.
/// System pasteboard monitoring is owned by the app layer;
/// this policy type applies privacy exclusions, ignores password managers,
/// moves re-copies to the top instead of duplicating them, ages entries out by a user-chosen retention
/// window, keeps at most `maxEntries` (the least recently copied go first) and clears in one action.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public enum CaptureDecision: Hashable, Sendable {
        case recorded
        case movedToTop
        case disabled
        case empty
        case concealed
        case excludedApp
    }

    /// Pasteboard markers apps use to flag passwords and transient content (nspasteboard.org convention).
    public static let privatePasteboardTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType"
    ]

    public static let defaultExcludedBundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.1password.1password",
        "com.bitwarden.desktop"
    ]

    /// How many entries are kept when nothing else is asked for. The whole history is held in memory,
    /// shown in Tuck's stream and rewritten at each copy, so it can't grow without end.
    public static let defaultMaxEntries = 200

    /// Off until the person turns it on.
    public var isEnabled: Bool
    public var retention: ClipboardRetention
    /// Not saved with the history: a file from before the cap (which recorded no limit) is held to it.
    public var maxEntries: Int = ClipboardHistory.defaultMaxEntries
    public var excludedBundleIDs: Set<String>
    public private(set) var entries: [ClipboardEntry]

    private enum CodingKeys: String, CodingKey {
        case isEnabled, retention, excludedBundleIDs, entries
    }

    public init(
        isEnabled: Bool = false,
        retention: ClipboardRetention = .oneDay,
        maxEntries: Int = ClipboardHistory.defaultMaxEntries,
        excludedBundleIDs: Set<String> = ClipboardHistory.defaultExcludedBundleIDs,
        entries: [ClipboardEntry] = []
    ) {
        self.isEnabled = isEnabled
        self.retention = retention
        self.maxEntries = max(1, maxEntries)
        self.excludedBundleIDs = excludedBundleIDs
        self.entries = entries
    }

    @discardableResult
    public mutating func record(
        text: String,
        pasteboardTypes: [String] = [],
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        now: Date = Date()
    ) -> CaptureDecision {
        record(ClipboardCapture(text: text, pasteboardTypes: pasteboardTypes, sourceBundleID: sourceBundleID,
                                sourceAppName: sourceAppName), now: now)
    }

    /// Keeps a copy, unless history is off, it is empty or private, or it came from an excluded app. A copy
    /// that is already here moves to the top instead. Text with no kind given is recognised now.
    @discardableResult
    public mutating func record(_ capture: ClipboardCapture, now: Date = Date()) -> CaptureDecision {
        guard isEnabled else { return .disabled }
        let hasText = !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || capture.payload?.fileURLs?.isEmpty == false || capture.payload?.imageFile != nil else {
            return .empty
        }
        if capture.pasteboardTypes.contains(where: ClipboardHistory.privatePasteboardTypes.contains) { return .concealed }
        if let bundleID = capture.sourceBundleID, excludedBundleIDs.contains(bundleID) { return .excludedApp }

        prune(now: now)
        let identity = capture.payload?.key ?? capture.text
        if let index = entries.firstIndex(where: { $0.identity == identity }) {
            var entry = entries.remove(at: index)
            entry.lastCopiedAt = now
            entry.copyCount += 1
            entries.insert(entry, at: 0)
            return .movedToTop
        }
        let recognition = capture.recognition ?? ContentClassifier.recognize(
            text: capture.text, sourceBundleID: capture.sourceBundleID, hasRichText: capture.payload?.richTextFile != nil)
        entries.insert(
            ClipboardEntry(
                text: capture.text,
                sourceAppName: capture.sourceAppName,
                sourceBundleID: capture.sourceBundleID,
                firstCopiedAt: now,
                lastCopiedAt: now,
                recognition: recognition,
                payload: capture.payload
            ),
            at: 0
        )
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        return .recorded
    }

    /// Moves an entry to the top as just copied, when it is copied again from Tuck.
    public mutating func touch(id: UUID, now: Date = Date()) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries.remove(at: index)
        entry.lastCopiedAt = now
        entry.copyCount += 1
        entries.insert(entry, at: 0)
    }

    /// Adds what was learned about an entry after it was recorded. Nothing happens if it has gone since.
    public mutating func update(id: UUID, preview: ClipPreview) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].preview = preview
    }

    /// Recognises entries saved before Tuck recognised kinds.
    public mutating func recognizeUnrecognized() {
        for index in entries.indices where entries[index].recognition == nil {
            let entry = entries[index]
            entries[index].recognition = ContentClassifier.recognize(text: entry.text, sourceBundleID: entry.sourceBundleID)
        }
    }

    /// Every asset file the history still uses, so the rest can be deleted.
    public var assetNames: Set<String> {
        Set(entries.flatMap { ($0.payload?.assetNames ?? []) + ($0.preview?.assetNames ?? []) })
    }

    /// Drops entries older than the retention window, and the least recently copied beyond the cap.
    public mutating func prune(now: Date = Date()) {
        if let interval = retention.interval {
            entries.removeAll { now.timeIntervalSince($0.lastCopiedAt) > interval }
        }
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
    }

    public mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func clear() {
        entries.removeAll()
    }
}
