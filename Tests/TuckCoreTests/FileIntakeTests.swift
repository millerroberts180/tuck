import Foundation
import Testing
@testable import TuckCore

@Suite("File intake")
struct FileIntakeTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TuckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(name.utf8).write(to: url)
        return url.standardizedFileURL
    }

    @Test func threeOrMoreFilesBecomeOneStack() {
        let files = (1...3).map { HeldItem.file(URL(fileURLWithPath: "/tmp/f\($0).txt")) }
        let link = HeldItem.link(URL(string: "https://example.com")!)
        let rows = DropIntake.rows(for: files + [link])
        #expect(rows.count == 2)
        #expect(rows[0].kind == .stack)
        #expect(rows[0].title == "3 files")
        #expect(rows[0].fileURLs.count == 3)
        #expect(rows[1].kind == .link)

        let pair = Array(files.prefix(2))
        #expect(DropIntake.rows(for: pair) == pair)
    }

    @Test func stackSubtitleNamesASharedFolder() {
        let stack = HeldItem.stack((1...3).map { HeldItem.file(URL(fileURLWithPath: "/Users/a/Trip/f\($0).jpg")) })
        #expect(stack.subtitle == "Trip")
    }

    @Test func unstackRestoresTheMembersInPlace() {
        var library = TuckLibrary()
        let before = HeldItem.text("before")
        let members = (1...3).map { HeldItem.file(URL(fileURLWithPath: "/tmp/s\($0)")) }
        let stack = HeldItem.stack(members)
        let after = HeldItem.text("after")
        library.add(before)
        library.add(stack)
        library.add(after)
        let unstacked = library.unstack(itemID: stack.id)
        #expect(unstacked)
        #expect(library.items.map(\.id) == [after.id] + members.map(\.id) + [before.id])
        let notAStack = library.unstack(itemID: before.id)
        #expect(!notAStack)
    }

    @Test func capacityCountsHeldRowsInTheStream() {
        var library = TuckLibrary()
        #expect(TuckLibrary.heldItemLimit == 200)
        #expect(library.remainingCapacity == TuckLibrary.heldItemLimit)
        // A stack is one row, and tucked windows take no room from held items.
        library.add(.stack((1...3).map { HeldItem.file(URL(fileURLWithPath: "/tmp/c\($0)")) }))
        library.park(ParkedWindow(app: AppIdentity(bundleID: "a", name: "A"), title: "w",
                                  originalFrame: WindowFrame(x: 0, y: 0, width: 10, height: 10)))
        #expect(library.remainingCapacity == TuckLibrary.heldItemLimit - 1)
        for index in 1..<TuckLibrary.heldItemLimit { library.add(.text("\(index)")) }
        #expect(library.remainingCapacity == 0)
        // Over the limit (a library merged from sessions can be) still reads as no room, never negative.
        library.add(.text("one more"))
        #expect(library.remainingCapacity == 0)
        library.removeHeldItem(id: library.items[0].id)
        library.removeHeldItem(id: library.items[0].id)
        #expect(library.remainingCapacity == 1)
    }

    @Test func reconcileFollowsMovedFilesAndDropsDeletedOnes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = try makeFile("kept.txt", in: directory)
        let moving = try makeFile("moving.txt", in: directory)
        let deleted = try makeFile("deleted.txt", in: directory)

        var library = TuckLibrary()
        for url in [kept, moving, deleted] {
            library.add(FileReferences.withBookmarks(.file(url)))
        }
        let renamed = directory.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: moving, to: renamed)
        try FileManager.default.removeItem(at: deleted)

        let removed = FileReferences.reconcile(&library)
        #expect(removed == 1)
        #expect(library.items.map(\.title).sorted() == ["kept.txt", "renamed.txt"])
    }

    @Test func reconcileCollapsesStacksThatLoseMembers() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try (1...3).map { try makeFile("m\($0).txt", in: directory) }
        var library = TuckLibrary()
        library.add(.stack(urls.map { HeldItem.file($0) }))
        try FileManager.default.removeItem(at: urls[0])
        FileReferences.reconcile(&library)
        #expect(library.items.first?.title == "2 files")
        try FileManager.default.removeItem(at: urls[1])
        FileReferences.reconcile(&library)
        #expect(library.items.first?.kind == .file)
        #expect(library.items.count == 1)
    }

    @Test func receivedStoreOnlyDeletesWhatItOwns() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReceivedFileStore(directory: root.appendingPathComponent("Received"))
        let slot = try store.makeSlot()
        let owned = try makeFile("message.eml", in: slot)
        let personal = try makeFile("mine.txt", in: root)

        #expect(store.owns(owned))
        #expect(!store.owns(personal))
        store.discard(personal)
        #expect(FileManager.default.fileExists(atPath: personal.path))
        store.discard(owned)
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(!FileManager.default.fileExists(atPath: slot.path))
    }

    @Test func sweepRemovesUnreferencedDropFolders() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReceivedFileStore(directory: root)
        let keptFile = try makeFile("keep.png", in: try store.makeSlot())
        let orphanSlot = try store.makeSlot()
        _ = try makeFile("orphan.png", in: orphanSlot)
        store.sweep(keeping: [keptFile])
        #expect(FileManager.default.fileExists(atPath: keptFile.path))
        #expect(!FileManager.default.fileExists(atPath: orphanSlot.path))
    }

    /// Uninstall deletes what Tuck wrote and nothing else, even when Tuck was pointed at a folder of the
    /// person's own. The set-aside files are made by the real stores, so their names can't drift apart.
    @Test func uninstallDeletesOnlyTucksOwnFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = SupportFolder(directory: root)
        let damaged = Data("{ unreadable".utf8)
        try damaged.write(to: folder.library)
        try damaged.write(to: folder.clipboardHistory)
        #expect(FileLibraryPersistence(fileURL: folder.library).load() == nil)
        #expect(FileClipboardPersistence(fileURL: folder.clipboardHistory).load() == nil)
        try Data("{}".utf8).write(to: folder.library)
        try Data("{}".utf8).write(to: folder.clipboardHistory)
        _ = try makeFile("message.eml", in: try folder.received.makeSlot())
        _ = try makeFile("Image.png", in: try folder.received.makeSlot())
        let personal = try makeFile("notes.txt", in: root)
        let stranger = try makeFile("theirs.txt", in: folder.received.directory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 6)

        #expect(folder.received.fileCount() == 2)
        #expect(!folder.removeTucksFiles())
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["Received", "notes.txt"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.received.directory.path) == ["theirs.txt"])
        #expect(folder.received.fileCount() == 0)

        try FileManager.default.removeItem(at: personal)
        try FileManager.default.removeItem(at: stranger)
        #expect(folder.removeTucksFiles())
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func archiveNamesFollowFinderConventions() {
        let folder = URL(fileURLWithPath: "/Users/a/Docs")
        let downloads = URL(fileURLWithPath: "/Users/a/Downloads")
        var existing: Set<String> = ["/Users/a/Docs/Report.pdf.zip"]
        let single = ArchiveNaming.archiveURL(for: [folder.appendingPathComponent("Report.pdf")], fallbackDirectory: downloads,
                                              isWritable: { _ in true }, exists: { existing.contains($0.path) })
        #expect(single?.path == "/Users/a/Docs/Report.pdf 2.zip")

        existing = []
        let mixed = ArchiveNaming.archiveURL(
            for: [folder.appendingPathComponent("a"), URL(fileURLWithPath: "/Volumes/X/b")],
            fallbackDirectory: downloads, isWritable: { _ in true }, exists: { _ in false })
        #expect(mixed?.path == "/Users/a/Downloads/Archive.zip")

        let readOnly = ArchiveNaming.archiveURL(for: [folder.appendingPathComponent("a"), folder.appendingPathComponent("b")],
                                                fallbackDirectory: downloads, isWritable: { _ in false }, exists: { _ in false })
        #expect(readOnly?.path == "/Users/a/Downloads/Archive.zip")
        #expect(ArchiveNaming.archiveURL(for: [], fallbackDirectory: downloads, isWritable: { _ in true }, exists: { _ in false }) == nil)
    }

    @Test func persistenceRoundTripsAndCoalescesWrites() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("library.json")
        let persistence = FileLibraryPersistence(fileURL: fileURL, coalescingDelay: 30)

        var library = TuckLibrary()
        let window = ParkedWindow(app: AppIdentity(bundleID: "com.apple.Notes", name: "Notes"), title: "List",
                                  originalFrame: WindowFrame(x: 0, y: 0, width: 600, height: 400),
                                  tuckedAt: Date(timeIntervalSinceReferenceDate: 700_000_000), method: .offScreen)
        library.park(window)
        library.add(.text("one"))
        persistence.save(library)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path)) // still coalescing
        library.add(.text("two"))
        persistence.save(library)
        persistence.flush()

        let loaded = FileLibraryPersistence(fileURL: fileURL).load()
        #expect(loaded == library)
        #expect(loaded?.items.map(\.title) == ["two", "one"])
        #expect(loaded?.windows == [window])
        // Written in the stream's format.
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        #expect(saved?["version"] as? Int == FileLibraryPersistence.formatVersion)
        #expect(FileLibraryPersistence.formatVersion == 2)
    }

    @Test func persistenceIgnoresMissingOrNewerFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("library.json")
        #expect(FileLibraryPersistence(fileURL: fileURL).load() == nil)
        try Data(#"{"version":99,"library":{}}"#.utf8).write(to: fileURL)
        #expect(FileLibraryPersistence(fileURL: fileURL).load() == nil)
    }

    /// Uninstall closes the store before deleting its folder, so nothing pending or saved afterwards may
    /// bring the folder back.
    @Test func aClosedLibraryStoreWritesNothingMore() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("Tuck", isDirectory: true)
        let persistence = FileLibraryPersistence(fileURL: folder.appendingPathComponent("library.json"), coalescingDelay: 30)
        var library = TuckLibrary()
        library.add(.text("pending"))
        persistence.save(library)
        persistence.close()
        library.add(.text("after"))
        persistence.save(library)
        persistence.flush()
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }
}
