import Foundation

/// Tuck's folder in Application Support, and the names of everything Tuck keeps there. Uninstall deletes
/// only these, then the folder once nothing else is in it, so a folder Tuck was pointed at by mistake keeps
/// everything that isn't Tuck's.
public struct SupportFolder: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    public var library: URL { directory.appendingPathComponent(Self.libraryName) }
    public var clipboardHistory: URL { directory.appendingPathComponent(Self.clipboardHistoryName) }
    public var clipboardAssets: ClipboardAssetStore {
        ClipboardAssetStore(directory: directory.appendingPathComponent(Self.clipboardAssetsName, isDirectory: true))
    }
    public var received: ReceivedFileStore {
        ReceivedFileStore(directory: directory.appendingPathComponent(Self.receivedName, isDirectory: true))
    }

    private static let libraryName = "library.json"
    private static let clipboardHistoryName = "clipboard-history.json"
    private static let receivedName = "Received"
    private static let clipboardAssetsName = "Clipboard"
    // Each store sets an unreadable file aside under its own name and the time, as "library-unreadable-<stamp>.json";
    // moving to the one stream keeps the sessions file as "library-sessions-backup-<stamp>.json".
    private static let setAsidePrefixes = ["library-unreadable-", "clipboard-history-unreadable-",
                                           FileLibraryPersistence.sessionsBackupPrefix]

    /// Whether a name directly in the folder is something Tuck wrote, or the Finder's own .DS_Store.
    public static func isTucks(_ name: String) -> Bool {
        if [libraryName, clipboardHistoryName, ".DS_Store"].contains(name) { return true }
        return name.hasSuffix(".json") && setAsidePrefixes.contains { name.hasPrefix($0) }
    }

    /// Deletes what Tuck wrote, then the folder if that leaves it empty. Received is emptied the same way,
    /// one drop folder at a time, and Clipboard one asset at a time. Returns whether the folder is gone, so
    /// anything left can be pointed out.
    public func removeTucksFiles(fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return true }
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where Self.isTucks(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        if names.contains(Self.receivedName) { received.removeAll(fileManager: fileManager) }
        if names.contains(Self.clipboardAssetsName) { clipboardAssets.removeAll(fileManager: fileManager) }
        if (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
            try? fileManager.removeItem(at: directory)
        }
        return !fileManager.fileExists(atPath: directory.path)
    }
}

extension ReceivedFileStore {
    /// How many received files are kept, counting what is in each drop folder. Uninstall says so first,
    /// because these may be the only copies.
    public func fileCount(fileManager: FileManager = .default) -> Int {
        dropFolders(fileManager: fileManager).reduce(0) { count, slot in
            let files = try? fileManager.contentsOfDirectory(at: slot, includingPropertiesForKeys: nil,
                                                             options: .skipsHiddenFiles)
            return count + (files?.count ?? 0)
        }
    }

    /// Deletes every drop folder, then the folder itself once nothing else is in it. Only folders named as
    /// `makeSlot` names them go, so nothing put here by anyone else is touched.
    func removeAll(fileManager: FileManager = .default) {
        for slot in dropFolders(fileManager: fileManager) { try? fileManager.removeItem(at: slot) }
        try? fileManager.removeItem(at: directory.appendingPathComponent(".DS_Store"))
        if (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
            try? fileManager.removeItem(at: directory)
        }
    }

    private func dropFolders(fileManager: FileManager) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { UUID(uuidString: $0.lastPathComponent) != nil }
    }
}
