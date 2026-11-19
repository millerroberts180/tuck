import Foundation

/// Keeps the library in a small JSON file (Application Support/Tuck/library.json in the app). Files are
/// stored as references (path plus bookmark), never copied.
///
/// Saves are coalesced: the first edit schedules one write a moment later that carries every edit made
/// meanwhile, encoded and written atomically on a utility queue, so typing in a text item never touches
/// the disk per keystroke.
///
/// A file that exists but can't be read (damaged, or written by a newer Tuck) is never overwritten: it
/// is moved aside, any apps it records as resting are reported so they can still be woken, and
/// `setAsideURL` tells the app not to clean up files the unreadable library may still refer to.
///
/// A library saved with sessions (format 1) is merged into the one stream as it loads (see
/// `LegacySessions`). The file it came from is first copied to `library-sessions-backup-<stamp>.json`,
/// and only then is the stream saved over it, so the migration runs once and only one way. If the copy
/// can't be written, nothing is saved that run.
public final class FileLibraryPersistence: LibraryPersistence {
    struct Envelope: Codable {
        var version: Int
        var library: TuckLibrary
    }

    private struct Version: Decodable {
        var version: Int
    }

    public static let formatVersion = 2
    /// The last format that kept sessions.
    static let sessionsFormatVersion = 1
    /// The sessions file kept as it was when it was moved to the stream, with the time after it.
    static let sessionsBackupPrefix = "library-sessions-backup-"

    public let fileURL: URL
    private let delay: TimeInterval
    private let queue = DispatchQueue(label: "app.tuck.persistence", qos: .utility)
    private let lock = NSLock()
    private var pending: TuckLibrary?
    /// Whether this store is holding off sudden termination until a scheduled write lands. Tuck's
    /// Info.plist allows sudden termination, which would otherwise drop an unwritten change on quit.
    private var holdsTermination = false
    private var scheduled = false
    /// Set by `close()`, or when a sessions library couldn't be backed up: no save is written after it.
    private var closed = false

    /// Where an unreadable library file was moved, if the last load found one.
    public private(set) var setAsideURL: URL?
    /// Rest records read from an unreadable library file, so those apps can still be woken.
    public private(set) var recoveredRestStates: [String: RestState] = [:]
    /// Where the sessions library was backed up, if the last load migrated one.
    public private(set) var migrationBackupURL: URL?

    public init(fileURL: URL, coalescingDelay: TimeInterval = 0.6) {
        self.fileURL = fileURL
        self.delay = coalescingDelay
    }

    /// Loads the stored library, following moved files and dropping files that no longer exist. A
    /// library saved with sessions is backed up, merged into the stream with the samples earlier
    /// versions started with taken out, and saved. Nil when there is no library yet, or when the file
    /// couldn't be read (it is then set aside).
    public func load() -> TuckLibrary? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let version = try? JSONDecoder().decode(Version.self, from: data).version,
              version <= Self.formatVersion else {
            setAside(data)
            return nil
        }
        if version <= Self.sessionsFormatVersion {
            guard var library = LegacySessions.migrate(data) else {
                setAside(data)
                return nil
            }
            let backedUp = backUpSessions(data)
            EarlierSamples.remove(from: &library, savedAs: data)
            FileReferences.reconcile(&library)
            if backedUp {
                save(library)
            } else {
                // Without a backup the sessions file is never written over: this run shows the stream but
                // saves nothing, and the next launch migrates again from the untouched file.
                lock.lock()
                closed = true
                lock.unlock()
            }
            return library
        }
        guard var library = try? JSONDecoder().decode(Envelope.self, from: data).library else {
            setAside(data)
            return nil
        }
        FileReferences.reconcile(&library)
        return library
    }

    /// Keeps the sessions file as it was before the stream is saved over it, and says whether it did.
    /// Never over an earlier backup: a second migration in the same second takes the next free name.
    private func backUpSessions(_ data: Data) -> Bool {
        let stamp = Int(Date().timeIntervalSince1970)
        let folder = fileURL.deletingLastPathComponent()
        var destination = folder.appendingPathComponent("\(Self.sessionsBackupPrefix)\(stamp).json")
        var attempt = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            attempt += 1
            destination = folder.appendingPathComponent("\(Self.sessionsBackupPrefix)\(stamp)-\(attempt).json")
        }
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return false }
        migrationBackupURL = destination
        return true
    }

    private struct RestRecords: Decodable {
        struct Library: Decodable { var restStates: [String: RestState]? }
        var library: Library
    }

    private func setAside(_ data: Data) {
        recoveredRestStates = (try? JSONDecoder().decode(RestRecords.self, from: data))?.library.restStates ?? [:]
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent("library-unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            setAsideURL = destination
        } catch {
            // Couldn't move it: still never write over it, by keeping a copy under the new name first.
            if (try? data.write(to: destination, options: .atomic)) != nil { setAsideURL = destination }
        }
    }

    public func save(_ library: TuckLibrary) {
        lock.lock()
        guard !closed else { return lock.unlock() }
        pending = library
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
        let library = pending
        pending = nil
        scheduled = false
        lock.unlock()
        if let library {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(Envelope(version: Self.formatVersion, library: library))
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                // Persistence is best effort; the in-memory library stays authoritative.
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
