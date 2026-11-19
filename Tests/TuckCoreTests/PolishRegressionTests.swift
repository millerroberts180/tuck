import Foundation
import Testing
@testable import TuckCore

/// Bugs found in the stabilisation pass, each pinned so it can't come back.
@Suite("Stabilisation regressions")
struct PolishRegressionTests {
    private func files(_ names: [String], in folder: String = "/Users/a/Trip") -> [HeldItem] {
        names.map { HeldItem.file(URL(fileURLWithPath: "\(folder)/\($0)")) }
    }

    @Test func aFileInsideAStackCanBeRemoved() {
        var library = TuckLibrary()
        let members = files(["a.jpg", "b.jpg", "c.jpg"])
        library.add(.stack(members))

        let removed = library.removeHeldItem(id: members[1].id)
        #expect(removed?.id == members[1].id)
        let stack = library.items.first
        #expect(stack?.kind == .stack)
        #expect(stack?.children?.map(\.id) == [members[0].id, members[2].id])
        #expect(stack?.title == "2 files")
    }

    @Test func aStackLeftWithOneFileBecomesThatFile() {
        var library = TuckLibrary()
        let members = files(["a.jpg", "b.jpg"])
        library.add(.stack(members))

        library.removeHeldItem(id: members[0].id)
        #expect(library.items.map(\.id) == [members[1].id])
    }

    @Test func removingSomethingThatIsNotThereRemovesNothing() {
        var library = TuckLibrary()
        library.add(.stack(files(["a.jpg", "b.jpg", "c.jpg"])))
        let before = library
        #expect(library.removeHeldItem(id: UUID()) == nil)
        #expect(library == before)
    }

    @Test func referencedFilesIncludeStackMembers() {
        var library = TuckLibrary()
        library.add(.stack(files(["a.jpg", "b.jpg", "c.jpg"])))
        library.add(.file(URL(fileURLWithPath: "/Users/a/Notes/d.txt")))
        library.add(.link(URL(string: "https://example.com/e.jpg")!))

        let referenced = library.referencedFileURLs
        #expect(referenced.contains(URL(fileURLWithPath: "/Users/a/Trip/b.jpg")))
        #expect(referenced.contains(URL(fileURLWithPath: "/Users/a/Notes/d.txt")))
        #expect(referenced.count == 4)
    }

    @Test func aFileOnADisconnectedDriveIsKept() {
        let volume = "TuckTestsNoSuchVolume-\(UUID().uuidString)"
        let item = HeldItem.file(URL(fileURLWithPath: "/Volumes/\(volume)/Projects/plan.pdf"))
        #expect(FileReferences.resolve(item) == .unchanged)

        var library = TuckLibrary()
        library.add(item)
        #expect(FileReferences.reconcile(&library) == 0)
        #expect(library.items == [item])
    }

    @Test func aMissingFileOnTheStartupDiskStillGoes() {
        let item = HeldItem.file(URL(fileURLWithPath: "/private/tmp/TuckTests-gone-\(UUID().uuidString).txt"))
        #expect(FileReferences.resolve(item) == .missing)
    }

    private func temporaryLibraryFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TuckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("library.json")
    }

    private func setAsideFiles(near file: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library-unreadable-") }
    }

    @Test func noLibraryYetIsNotTreatedAsDamage() throws {
        let file = try temporaryLibraryFile()
        let store = FileLibraryPersistence(fileURL: file)
        #expect(store.load() == nil)
        #expect(store.setAsideURL == nil)
        #expect(try setAsideFiles(near: file).isEmpty)
    }

    @Test func anUnreadableLibraryIsSetAsideNotOverwritten() throws {
        let file = try temporaryLibraryFile()
        try Data("{ this is not a library".utf8).write(to: file)
        let store = FileLibraryPersistence(fileURL: file)
        #expect(store.load() == nil)
        #expect(store.setAsideURL != nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let kept = try setAsideFiles(near: file)
        #expect(kept.count == 1)
        #expect(try Data(contentsOf: kept[0]) == Data("{ this is not a library".utf8))
    }

    @Test func restRecordsAreRecoveredFromALibraryThatCanNotBeRead() throws {
        let file = try temporaryLibraryFile()
        var library = TuckLibrary()
        let process = ProcessIdentity(pid: 4242, startTime: 1, executablePath: "/Applications/Preview.app", bundleID: "com.apple.Preview")
        library.setRestState(.resting(since: Date(timeIntervalSince1970: 0), process: process), for: "com.apple.Preview")
        // A library from a newer Tuck: this one can't read it, but can still find who is resting.
        let newer = FileLibraryPersistence.Envelope(version: FileLibraryPersistence.formatVersion + 1, library: library)
        try JSONEncoder().encode(newer).write(to: file)

        let store = FileLibraryPersistence(fileURL: file)
        #expect(store.load() == nil)
        #expect(store.recoveredRestStates["com.apple.Preview"]?.isResting == true)
        #expect(store.setAsideURL != nil)
    }
}
