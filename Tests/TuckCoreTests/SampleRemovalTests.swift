import Foundation
import Testing
@testable import TuckCore

@Suite("Starting without sample data")
struct SampleRemovalTests {
    static let start = Date(timeIntervalSinceReferenceDate: 700_000_000)
    static func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    let checkIn = HeldItem.text("Check-in opens 24 hours before departure. Seat 14A, carry-on only.", addedAt: SampleRemovalTests.at(1))
    let guide = HeldItem.link(URL(string: "https://www.visitlisboa.com/en/places/alfama")!, title: "Alfama walking guide",
                              addedAt: SampleRemovalTests.at(2))
    let playlist = HeldItem.music(URL(string: "https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd")!,
                                  title: "Lisbon evening playlist", addedAt: SampleRemovalTests.at(3))
    let pourOver = HeldItem.link(URL(string: "https://www.example.com/products/ceramic-pour-over")!,
                                 title: "Ceramic pour-over set", addedAt: SampleRemovalTests.at(4))

    func window(_ title: String, at minutes: Double) -> ParkedWindow {
        ParkedWindow(app: AppIdentity(bundleID: "com.apple.Safari", name: "Safari"), title: title,
                     originalFrame: WindowFrame(x: 0, y: 0, width: 800, height: 600), tuckedAt: Self.at(minutes))
    }

    @Test func aFirstLaunchStartsWithAnEmptyStream() {
        let library = TuckLibrary()
        #expect(library.isEmpty)
        #expect(library.totalItemCount == 0)
        #expect(library.restStates.isEmpty)
    }

    @Test func samplesFromAnEarlierVersionAreRemovedAndTheRestIsKept() throws {
        let folder = try temporaryFolder()
        let samplesFolder = folder.appendingPathComponent("TuckSamples", isDirectory: true)
        try FileManager.default.createDirectory(at: samplesFolder, withIntermediateDirectories: true)
        let notes = samplesFolder.appendingPathComponent("Lisbon trip notes.txt")
        try Data("notes".utf8).write(to: notes)

        let sampleWindow = window("Lisbon flights — compare fares", at: 1), realWindow = window("Real", at: 2)
        // Same address as the sample, but saved by the person under another title: kept.
        let ownGuide = HeldItem.link(guide.url!, title: "Alfama | Visit Lisboa", addedAt: Self.at(6))
        let mine = HeldItem.text("mine", addedAt: Self.at(7))
        let trip = SessionsFile.Session(createdAt: Self.at(0), windows: [realWindow, sampleWindow],
                                        items: [mine, ownGuide, .file(notes, addedAt: Self.at(5)), playlist, checkIn])
        let gift = SessionsFile.Session(createdAt: Self.at(0), items: [guide, pourOver])
        let empty = SessionsFile.Session(createdAt: Self.at(0))
        let process = ProcessIdentity(pid: 4242, startTime: 1, executablePath: "/Applications/Preview.app", bundleID: "com.apple.Preview")
        let sessions = SessionsFile(sessions: [trip, gift, empty], currentSessionID: trip.id,
                                    restStates: ["com.apple.Preview": .resting(since: Self.at(0), process: process)],
                                    sampleWindows: [sampleWindow.id])

        let file = folder.appendingPathComponent("library.json")
        try sessions.data().write(to: file)
        let store = FileLibraryPersistence(fileURL: file, coalescingDelay: 0)
        let loaded = try #require(store.load())

        #expect(loaded.windows.map(\.id) == [realWindow.id])
        #expect(loaded.items.map(\.title) == ["mine", "Alfama | Visit Lisboa"])
        #expect(loaded.restState(for: "com.apple.Preview").isResting)

        // The cleaned library is saved, so the next launch reads it as it is.
        store.flush()
        #expect(FileLibraryPersistence(fileURL: file).load() == loaded)
    }

    @Test func aLibraryOfOnlySamplesBecomesAnEmptyStream() throws {
        let sessions = SessionsFile(sessions: [SessionsFile.Session(createdAt: Self.at(0), items: [checkIn, playlist, guide]),
                                               SessionsFile.Session(createdAt: Self.at(0), items: [pourOver])])
        let file = try temporaryFolder().appendingPathComponent("library.json")
        try sessions.data().write(to: file)
        let loaded = try #require(FileLibraryPersistence(fileURL: file).load())
        #expect(loaded.isEmpty)
    }

    @Test func aLibraryWithoutSamplesKeepsEverything() throws {
        // Every session closed, with or without something in Loose: the stream holds just what there was.
        let mine = HeldItem.text("mine", addedAt: Self.at(0))
        for loose in [[], [mine]] {
            let file = try temporaryFolder().appendingPathComponent("library.json")
            try SessionsFile(looseItems: loose).data().write(to: file)
            #expect(FileLibraryPersistence(fileURL: file).load() == TuckLibrary(items: loose))
        }
    }

    /// Samples only ever came in libraries with sessions. Text in the stream that happens to match one is
    /// the person's own.
    @Test func theStreamIsNeverCheckedForSamples() throws {
        let file = try temporaryFolder().appendingPathComponent("library.json")
        let library = TuckLibrary(items: [checkIn, guide])
        let store = FileLibraryPersistence(fileURL: file, coalescingDelay: 0)
        store.save(library)
        store.flush()
        #expect(FileLibraryPersistence(fileURL: file).load() == library)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TuckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
