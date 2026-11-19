import Foundation

/// Rules for turning one drop into held rows.
public enum DropIntake {
    /// Dropping this many files at once keeps them together as a single stack row.
    public static let stackThreshold = 3

    /// Groups the files of a single drop into one stack when there are enough of them. Links, music and
    /// text always stay as their own rows, after the stack, in drop order.
    public static func rows(for items: [HeldItem], sourceAppName: String? = nil, now: Date = Date()) -> [HeldItem] {
        let files = items.filter { $0.kind == .file }
        guard files.count >= stackThreshold else { return items }
        let others = items.filter { $0.kind != .file }
        return [.stack(files, sourceAppName: sourceAppName, addedAt: now)] + others
    }
}

/// What a drag carries, as its pasteboard's types tell before anything is read: files (promised files
/// and raw images arrive as files too), a link, or text. It names the one drop target's label.
public enum DropKind: Equatable, Sendable {
    case file, link, text

    /// What an empty Tuck says while pointed at.
    public static let invitation = "Drop into Tuck"

    public var label: String {
        switch self {
        case .file: "Drop file into Tuck"
        case .link: "Drop link into Tuck"
        case .text: "Drop text into Tuck"
        }
    }

    /// File references first, as a drop reads them, then a link, then whatever arrives as a file
    /// (promised files, raw images), and text otherwise.
    public static func kind(hasFiles: Bool, hasLink: Bool, arrivesAsFile: Bool) -> DropKind {
        if hasFiles { return .file }
        if hasLink { return .link }
        return arrivesAsFile ? .file : .text
    }
}

/// Keeps file items pointing at the right place. Tuck stores files as references: the path for speed
/// and a bookmark so a file that is renamed or moved after the drop is still found.
public enum FileReferences {
    public enum Resolution: Equatable {
        case unchanged
        case moved(URL)
        case missing
    }

    /// A plain (not security-scoped) bookmark. Tuck ships unsandboxed, so no scope is needed.
    public static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Adds bookmarks to file items (and stack members) that do not have one yet.
    public static func withBookmarks(_ item: HeldItem) -> HeldItem {
        var item = item
        switch item.kind {
        case .file:
            if item.bookmark == nil, let url = item.url { item.bookmark = bookmark(for: url) }
        case .stack:
            item.children = item.children?.map(withBookmarks)
        case .link, .music, .text:
            break
        }
        return item
    }

    /// Checks one file item. A file still at its path is unchanged; otherwise the bookmark is resolved
    /// without mounting volumes or showing UI. Neither path nor bookmark: the file is gone. A file on a
    /// disk that isn't connected right now (an external or network volume) is kept as it is, so
    /// unplugging a drive never empties Tuck of its files.
    public static func resolve(_ item: HeldItem, fileManager: FileManager = .default) -> Resolution {
        guard item.kind == .file, let url = item.url else { return .unchanged }
        if fileManager.fileExists(atPath: url.path) { return .unchanged }
        if isOnDisconnectedVolume(url, fileManager: fileManager) { return .unchanged }
        guard let data = item.bookmark else { return .missing }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                      relativeTo: nil, bookmarkDataIsStale: &stale),
              fileManager.fileExists(atPath: resolved.path) else { return .missing }
        return .moved(resolved.standardizedFileURL)
    }

    /// Under /Volumes/<name>, with no such volume mounted.
    static func isOnDisconnectedVolume(_ url: URL, fileManager: FileManager = .default) -> Bool {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > 2, parts[0] == "/", parts[1] == "Volumes" else { return false }
        return !fileManager.fileExists(atPath: "/Volumes/" + parts[2])
    }

    /// Follows moved files and removes files that no longer exist anywhere. Returns how many were removed.
    @discardableResult
    public static func reconcile(_ library: inout TuckLibrary, fileManager: FileManager = .default) -> Int {
        library.reconcileHeldItems { item in
            switch resolve(item, fileManager: fileManager) {
            case .unchanged:
                return item
            case .moved(let url):
                var moved = item
                moved.url = url
                moved.title = url.lastPathComponent
                moved.bookmark = bookmark(for: url) ?? item.bookmark
                return moved
            case .missing:
                return nil
            }
        }
    }
}

/// Files that exist only because Tuck received them: promised files (Mail messages, Photos and similar
/// sources hand over a file only on drop) and raw image data. Each drop gets its own folder so names
/// never collide. Everything here is owned by Tuck and deleted when its row is removed.
public struct ReceivedFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    /// A fresh, empty folder for one drop.
    public func makeSlot(fileManager: FileManager = .default) throws -> URL {
        let slot = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: slot, withIntermediateDirectories: true)
        return slot
    }

    public func owns(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directory.path + "/")
    }

    /// Deletes a received file and its drop folder once that folder is empty. Ignores files Tuck does
    /// not own, so a reference to the person's own file can never be deleted through here.
    public func discard(_ url: URL, fileManager: FileManager = .default) {
        guard owns(url) else { return }
        try? fileManager.removeItem(at: url)
        let slot = url.deletingLastPathComponent()
        if owns(slot), (try? fileManager.contentsOfDirectory(atPath: slot.path))?.isEmpty == true {
            try? fileManager.removeItem(at: slot)
        }
    }

    /// Removes drop folders that no held item refers to any more (for example after a crash).
    public func sweep(keeping referenced: [URL], fileManager: FileManager = .default) {
        let keep = Set(referenced.filter(owns).map { $0.standardizedFileURL.deletingLastPathComponent().path })
        guard let slots = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for slot in slots where !keep.contains(slot.standardizedFileURL.path) {
            try? fileManager.removeItem(at: slot)
        }
    }
}

/// Names and places zip archives made from held files, following the Finder's conventions: one item
/// becomes "Name.zip", several become "Archive.zip", and a clash adds " 2", " 3" and so on.
public enum ArchiveNaming {
    public static func archiveURL(
        for sources: [URL],
        fallbackDirectory: URL,
        isWritable: (URL) -> Bool,
        exists: (URL) -> Bool
    ) -> URL? {
        guard let first = sources.first else { return nil }
        let base = sources.count == 1 ? first.lastPathComponent : "Archive"
        let parents = Set(sources.map { $0.deletingLastPathComponent().standardizedFileURL })
        let directory: URL
        if parents.count == 1, let parent = parents.first, isWritable(parent) {
            directory = parent
        } else {
            directory = fallbackDirectory
        }
        var candidate = directory.appendingPathComponent("\(base).zip")
        var counter = 2
        while exists(candidate) {
            candidate = directory.appendingPathComponent("\(base) \(counter).zip")
            counter += 1
        }
        return candidate
    }
}
