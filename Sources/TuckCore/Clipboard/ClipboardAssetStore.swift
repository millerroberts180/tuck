import Foundation

/// The folder beside the clipboard history that holds what a copy carried besides text: images, styled
/// text, page icons and map pictures (Application Support/Tuck/Clipboard in the app). Each file is named
/// by a fresh UUID, and the history names the ones it uses; anything it no longer names is deleted.
public struct ClipboardAssetStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
    }

    public func url(for name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    /// Writes data under a new name with the extension given, and returns the name.
    public func write(_ data: Data, extension ext: String, fileManager: FileManager = .default) throws -> String {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + ext
        try data.write(to: url(for: name), options: [.atomic])
        return name
    }

    /// Deletes every asset the history no longer names. A file younger than `grace` stays: it may belong to
    /// a copy being recorded right now.
    public func removeUnreferenced(keeping names: Set<String>, grace: TimeInterval = 120, now: Date = Date(),
                                   fileManager: FileManager = .default) {
        for (name, url) in assets(fileManager: fileManager) where !names.contains(name) {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) < grace { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    /// Deletes every asset, then the folder once nothing else is in it. Only files named as `write` names
    /// them go.
    public func removeAll(fileManager: FileManager = .default) {
        for (_, url) in assets(fileManager: fileManager) { try? fileManager.removeItem(at: url) }
        try? fileManager.removeItem(at: directory.appendingPathComponent(".DS_Store"))
        if (try? fileManager.contentsOfDirectory(atPath: directory.path))?.isEmpty == true {
            try? fileManager.removeItem(at: directory)
        }
    }

    /// The total size of the assets, for Settings.
    public func byteCount(fileManager: FileManager = .default) -> Int {
        assets(fileManager: fileManager).reduce(0) { total, asset in
            total + ((try? asset.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
    }

    private func assets(fileManager: FileManager) -> [(name: String, url: URL)] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.compactMap { name in
            let stem = (name as NSString).deletingPathExtension
            guard UUID(uuidString: stem) != nil else { return nil }
            return (name, url(for: name))
        }
    }
}
