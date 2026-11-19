import Foundation
import Testing
@testable import TuckCore

@Suite("Clipboard history file")
struct ClipboardPersistenceTests {
    private func temporaryHistoryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TuckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("clipboard-history.json")
    }

    private func setAsideFiles(near file: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("clipboard-history-unreadable-") }
    }

    private func history(_ texts: [String]) -> ClipboardHistory {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        texts.forEach { history.record(text: $0) }
        return history
    }

    @Test func noHistoryYetIsNotTreatedAsDamage() throws {
        let file = try temporaryHistoryFile()
        let store = FileClipboardPersistence(fileURL: file)
        #expect(store.load() == nil)
        #expect(store.setAsideURL == nil)
        #expect(try setAsideFiles(near: file).isEmpty)
    }

    @Test func anUnreadableHistoryIsSetAsideNotOverwritten() throws {
        let file = try temporaryHistoryFile()
        let damaged = Data("{ this is not a clipboard history".utf8)
        try damaged.write(to: file)
        let store = FileClipboardPersistence(fileURL: file)
        #expect(store.load() == nil)
        #expect(store.setAsideURL != nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // The fresh history saved after it goes in its own file; the unreadable one is kept as it was.
        store.save(history(["fresh"]))
        store.flush()
        let kept = try setAsideFiles(near: file)
        #expect(kept.count == 1)
        #expect(try Data(contentsOf: kept[0]) == damaged)
        let saved = try JSONDecoder().decode(ClipboardHistory.self, from: Data(contentsOf: file))
        #expect(saved.entries.map(\.text) == ["fresh"])
    }

    @Test func savesAreBatchedAndAnUnchangedHistoryIsNotWritten() throws {
        let file = try temporaryHistoryFile()
        // A delay no test waits out: only the flush writes.
        let store = FileClipboardPersistence(fileURL: file, coalescingDelay: 600)
        store.save(history(["a"]))
        store.save(history(["a", "b"]))
        #expect(!FileManager.default.fileExists(atPath: file.path))
        store.flush()
        let saved = try JSONDecoder().decode(ClipboardHistory.self, from: Data(contentsOf: file))
        #expect(saved.entries.map(\.text) == ["b", "a"])

        // Saving what the file already holds writes nothing.
        try FileManager.default.removeItem(at: file)
        store.save(saved)
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func clearingRemovesSetAsideFilesAndNothingElse() throws {
        let file = try temporaryHistoryFile()
        let folder = file.deletingLastPathComponent()
        try Data("{ damaged".utf8).write(to: file)
        try Data("older".utf8).write(to: folder.appendingPathComponent("clipboard-history-unreadable-1.json"))
        let library = folder.appendingPathComponent("library-unreadable-1.json")
        try Data("library".utf8).write(to: library)
        let store = FileClipboardPersistence(fileURL: file)
        #expect(store.load() == nil)
        store.save(history(["fresh"]))
        store.flush()
        #expect(try setAsideFiles(near: file).count == 2)

        store.removeSetAsideFiles()
        store.flush()
        #expect(try setAsideFiles(near: file).isEmpty)
        #expect(store.setAsideURL == nil)
        // The history itself, and anything that isn't clipboard history, stay.
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: library.path))
    }

    /// Uninstall closes the store before deleting its folder, so nothing may be written after that.
    @Test func aClosedStoreWritesNothingMore() throws {
        let file = try temporaryHistoryFile()
        let store = FileClipboardPersistence(fileURL: file, coalescingDelay: 600)
        store.save(history(["pending"]))
        store.close()
        store.save(history(["pending", "after"]))
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aLoadedHistoryIsNotWrittenBackUnchanged() throws {
        let file = try temporaryHistoryFile()
        let writer = FileClipboardPersistence(fileURL: file)
        writer.save(history(["kept"]))
        writer.flush()

        let store = FileClipboardPersistence(fileURL: file, coalescingDelay: 600)
        let loaded = try #require(store.load())
        try FileManager.default.removeItem(at: file)
        store.save(loaded)
        store.flush()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
