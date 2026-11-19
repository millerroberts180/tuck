import Foundation

/// Keeps clipboard history in a small JSON file (Application Support/Tuck/clipboard-history.json in the
/// app), written the way `FileLibraryPersistence` writes the library.
///
/// Saves are coalesced: the first change schedules one write a moment later that carries every change
/// made meanwhile, encoded and written atomically on a utility queue, so a run of copies costs one write
/// and none of it runs on the main thread. A history the same as the one in the file isn't written.
///
/// A file that exists but can't be read (damaged, or written by a newer Tuck) is never overwritten: it
/// is moved aside, and history starts empty.
///
/// After each write, the asset files the history no longer names (images and the like, see
/// `ClipboardAssetStore`) are deleted on the same queue.
public final class FileClipboardPersistence {
    public let fileURL: URL
    public let assets: ClipboardAssetStore?
    private let delay: TimeInterval
    private let queue = DispatchQueue(label: "app.tuck.clipboard-persistence", qos: .utility)
    private let lock = NSLock()
    private var pending: ClipboardHistory?
    /// What the file holds, as far as this store knows: the history it loaded or last wrote.
    private var stored: ClipboardHistory?
    /// Whether this store is holding off sudden termination until a scheduled write lands. Tuck's
    /// Info.plist allows sudden termination, which would otherwise drop an unwritten change on quit.
    private var holdsTermination = false
    private var scheduled = false
    /// Set by `close()`: no save is written after it.
    private var closed = false

    /// Where an unreadable history file was moved, if the last load found one.
    public private(set) var setAsideURL: URL?

    public init(fileURL: URL, assets: ClipboardAssetStore? = nil, coalescingDelay: TimeInterval = 0.6) {
        self.fileURL = fileURL
        self.assets = assets
        self.delay = coalescingDelay
    }

    /// The stored history. Nil when there is none yet, or when the file couldn't be read (it is then
    /// set aside). Entries saved before Tuck recognised kinds are recognised now, and saved so at the
    /// next write.
    public func load() -> ClipboardHistory? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard var history = try? JSONDecoder().decode(ClipboardHistory.self, from: data) else {
            setAside(data)
            return nil
        }
        lock.lock()
        stored = history
        lock.unlock()
        history.recognizeUnrecognized()
        return history
    }

    /// Deletes every asset file, for Clear. Runs on the store's queue, after any write under way.
    public func removeAllAssets() {
        guard let assets else { return }
        queue.async { assets.removeAll() }
    }

    /// Deletes every unreadable history file set aside beside this one. Clearing history clears these too:
    /// they hold text copied earlier, which a clear promises is gone. Runs on the store's queue.
    public func removeSetAsideFiles() {
        queue.async { [fileURL] in
            let folder = fileURL.deletingLastPathComponent()
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where name.hasPrefix(Self.setAsidePrefix) && name.hasSuffix(".json") {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        setAsideURL = nil
    }

    private static let setAsidePrefix = "clipboard-history-unreadable-"

    private func setAside(_ data: Data) {
        let stamp = Int(Date().timeIntervalSince1970)
        let name = "\(Self.setAsidePrefix)\(stamp).json"
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            setAsideURL = destination
        } catch {
            // Couldn't move it: still never write over it, by keeping a copy under the new name first.
            if (try? data.write(to: destination, options: .atomic)) != nil { setAsideURL = destination }
        }
    }

    public func save(_ history: ClipboardHistory) {
        lock.lock()
        guard !closed else { return lock.unlock() }
        // Launch and every settings change save too, mostly with nothing changed: those cost nothing.
        if !scheduled, history == stored {
            lock.unlock()
            return
        }
        pending = history
        let needsSchedule = !scheduled
        scheduled = true
        let needsHold = needsSchedule && !holdsTermination
        if needsHold { holdsTermination = true }
        lock.unlock()
        if needsHold { ProcessInfo.processInfo.disableSuddenTermination() }
        guard needsSchedule else { return }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.writePending() }
    }

    /// Writes any pending change immediately; call before the app quits.
    public func flush() {
        queue.sync { writePending() }
    }

    /// Drops anything not yet written and ignores every later save, for Uninstall, so nothing recreates
    /// the folder it removes. Returns once a write already under way has landed.
    public func close() {
        lock.lock()
        closed = true
        pending = nil
        lock.unlock()
        queue.sync {}
    }

    private func writePending() {
        lock.lock()
        let history = pending
        pending = nil
        scheduled = false
        let unchanged = history == stored
        lock.unlock()
        if let history, !unchanged {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(history).write(to: fileURL, options: [.atomic])
                lock.lock()
                stored = history
                lock.unlock()
                assets?.removeUnreferenced(keeping: history.assetNames)
            } catch {
                // Persistence is best effort; the history in memory stays authoritative.
            }
        }
        // Written (or nothing left to write): quitting suddenly can no longer lose anything.
        lock.lock()
        let release = holdsTermination && !scheduled
        if release { holdsTermination = false }
        lock.unlock()
        if release { ProcessInfo.processInfo.enableSuddenTermination() }
    }
}
