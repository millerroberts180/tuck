import Foundation
import Testing
@testable import TuckCore

/// A library file as Tuck wrote it while it had sessions (format 1). Windows, items and rest states are
/// encoded by their real types, so they read exactly as an earlier version saved them; only the
/// session wrapping, which no longer exists as a type, is spelt out here.
struct SessionsFile {
    struct Session {
        var id = UUID()
        var name: String?
        var intention: String?
        var createdAt: Date
        /// Most recently tucked first, as sessions kept them.
        var windows: [ParkedWindow] = []
        /// Most recently added first.
        var items: [HeldItem] = []
        var isArchived = false
    }

    var sessions: [Session] = []
    var currentSessionID: UUID?
    var looseItems: [HeldItem] = []
    var restStates: [String: RestState] = [:]
    /// Windows saved with `isSample` set, as earlier versions flagged the windows they started with.
    var sampleWindows: Set<UUID> = []
    var version = 1

    func data() throws -> Data {
        let sessions = try self.sessions.map { session -> [String: Any] in
            var object: [String: Any] = [
                "id": session.id.uuidString,
                "color": "coral",
                "createdAt": session.createdAt.timeIntervalSinceReferenceDate,
                "parkedWindows": try session.windows.map { window -> Any in
                    var object = try Self.json(window) as? [String: Any] ?? [:]
                    if sampleWindows.contains(window.id) { object["isSample"] = true }
                    return object
                },
                "heldItems": try Self.json(session.items),
                "isArchived": session.isArchived,
            ]
            object["name"] = session.name
            object["intention"] = session.intention
            return object
        }
        var library: [String: Any] = [
            "sessions": sessions,
            "looseItems": try Self.json(looseItems),
            "restStates": try Self.json(restStates),
        ]
        library["currentSessionID"] = currentSessionID?.uuidString
        return try JSONSerialization.data(withJSONObject: ["version": version, "library": library])
    }

    private static func json<Value: Encodable>(_ value: Value) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
    }
}

@Suite("Merging sessions into the stream")
struct SessionsMigrationTests {
    /// Whole seconds, so dates survive the trip through JSON exactly.
    static let start = Date(timeIntervalSinceReferenceDate: 700_000_000)
    /// Files on a drive that isn't connected are kept as they are, so these survive loading untouched.
    static let drive = "/Volumes/TuckTestsNoSuchVolume-\(UUID().uuidString)"
    static let preview = ProcessIdentity(pid: 4242, startTime: 1, executablePath: "/Applications/Preview.app",
                                         bundleID: "com.apple.Preview")

    static func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    static func window(_ app: String, _ title: String, at minutes: Double) -> ParkedWindow {
        ParkedWindow(app: AppIdentity(bundleID: "com.example.\(app)", name: app), title: title,
                     originalFrame: WindowFrame(x: 10, y: 20, width: 800, height: 600), displayID: "1",
                     tuckedAt: at(minutes), method: .offScreen)
    }

    static func file(_ name: String, at minutes: Double) -> HeldItem {
        HeldItem.file(URL(fileURLWithPath: "\(drive)/Trip/\(name)"), sourceAppName: "Finder", addedAt: at(minutes))
    }

    /// What a library with sessions held: Desk, current; Lisbon, archived with everything still in it; an
    /// empty Personal; and a few things dropped while no session was current.
    let file: SessionsFile
    /// The stream it becomes: everything, newest first.
    let windows: [ParkedWindow]
    let items: [HeldItem]
    let photos: HeldItem

    init() {
        let budget = Self.window("Numbers", "Budget", at: 50)
        let inbox = Self.window("Mail", "Inbox", at: 10)
        let flights = Self.window("Safari", "Flights", at: 60)
        // Tucked at the same moment as Inbox, but saved after it.
        let hotel = Self.window("Safari", "Hotel", at: 10)
        let article = HeldItem.link(URL(string: "https://example.com/read/later")!, title: "Later", addedAt: Self.at(40))
        let photos = HeldItem.stack([Self.file("a.jpg", at: 30), Self.file("b.jpg", at: 30), Self.file("c.jpg", at: 30)],
                                    sourceAppName: "Finder", addedAt: Self.at(30))
        let ticket = Self.file("ticket.pdf", at: 45)
        let packing = HeldItem.text("Passport, charger, adapter", addedAt: Self.at(5))
        let reminder = HeldItem.text("Call the landlord", addedAt: Self.at(55))
        // Dropped at the same moment as the photos; Loose was saved first.
        let song = HeldItem.music(URL(string: "https://open.spotify.com/track/abc")!, addedAt: Self.at(30))

        let desk = SessionsFile.Session(name: "Desk", createdAt: Self.at(0), windows: [budget, inbox], items: [article, photos])
        let lisbon = SessionsFile.Session(name: "Lisbon", createdAt: Self.at(-100), windows: [flights, hotel],
                                          items: [ticket, packing], isArchived: true)
        let personal = SessionsFile.Session(intention: "personal", createdAt: Self.at(70))
        file = SessionsFile(sessions: [desk, lisbon, personal], currentSessionID: desk.id, looseItems: [reminder, song],
                            restStates: ["com.apple.Preview": .resting(since: Self.at(20), process: Self.preview),
                                         "com.apple.TextEdit": .awake])
        windows = [flights, budget, inbox, hotel]
        items = [reminder, ticket, article, song, photos, packing]
        self.photos = photos
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TuckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func backups(in folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library-sessions-backup-") }
    }

    private func savedVersion(of file: URL) throws -> Int? {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        return object?["version"] as? Int
    }

    @Test func everyWindowAndItemFromEverySessionSurvivesNewestFirst() throws {
        let url = try temporaryFolder().appendingPathComponent("library.json")
        try file.data().write(to: url)

        let loaded = try #require(FileLibraryPersistence(fileURL: url, coalescingDelay: 30).load())
        // Windows from the current and the archived session, ids and all; Inbox and Hotel were tucked at the
        // same moment and keep the order they were saved in.
        #expect(loaded.windows == windows)
        // Loose items and every session's, the stack with its members; the song and the photos tie, and
        // Loose was saved first.
        #expect(loaded.items == items)
        #expect(loaded.items.first { $0.kind == .stack }?.children?.map(\.id) == photos.children?.map(\.id))
        #expect(loaded.restStates == file.restStates)
        #expect(loaded.restState(for: "com.apple.Preview").isResting)
        // The archived session's files are still Tuck's to keep, so nothing it refers to is cleaned up.
        #expect(loaded.referencedFileURLs.count == 4)
        #expect(loaded.referencedFileURLs.contains(URL(fileURLWithPath: "\(Self.drive)/Trip/ticket.pdf")))
        // The stream's own limit is for new drops; nothing merged is dropped to fit it.
        #expect(loaded.totalItemCount == 10)
    }

    @Test func mergingIsPlainValueLogic() throws {
        let merged = try #require(LegacySessions.migrate(try file.data()))
        #expect(merged == TuckLibrary(windows: windows, items: items, restStates: file.restStates))
        // Anything that isn't a sessions library isn't merged.
        #expect(LegacySessions.migrate(Data("{ not json".utf8)) == nil)
        let stream = FileLibraryPersistence.Envelope(version: 2, library: TuckLibrary(items: [.text("mine")]))
        #expect(LegacySessions.migrate(try JSONEncoder().encode(stream)) == nil)
    }

    @Test func theSessionsFileIsBackedUpByteForByteBeforeAnythingIsWritten() throws {
        let original = try file.data()
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("library.json")
        try original.write(to: url)

        let store = FileLibraryPersistence(fileURL: url, coalescingDelay: 30)
        let before = Int(Date().timeIntervalSince1970)
        #expect(store.load() != nil)
        let backup = try #require(store.migrationBackupURL)
        #expect(try backups(in: folder).map(\.lastPathComponent) == [backup.lastPathComponent])
        #expect(backup.deletingLastPathComponent().path == folder.path)
        #expect(try Data(contentsOf: backup) == original)
        // Named for when it was made, in seconds since 1970.
        let stamp = Int(backup.deletingPathExtension().lastPathComponent.dropFirst("library-sessions-backup-".count))
        #expect(stamp.map { (before - 1...before + 60).contains($0) } == true)
        #expect(backup.pathExtension == "json")
        #expect(store.setAsideURL == nil)
    }

    @Test func theStreamIsSavedOverItOnceAndLoadsWithoutMigratingAgain() throws {
        let original = try file.data()
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("library.json")
        try original.write(to: url)

        let store = FileLibraryPersistence(fileURL: url, coalescingDelay: 30)
        let migrated = try #require(store.load())
        store.flush()
        #expect(try savedVersion(of: url) == 2)
        #expect(try Data(contentsOf: url) != original)

        let again = FileLibraryPersistence(fileURL: url, coalescingDelay: 30)
        #expect(again.load() == migrated)
        #expect(again.migrationBackupURL == nil)
        #expect(again.setAsideURL == nil)
        #expect(try backups(in: folder).count == 1)
        #expect(try savedVersion(of: url) == 2)
    }

    @Test func withoutABackupNothingIsWrittenOverTheSessionsFile() throws {
        let original = try file.data()
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("library.json")
        try original.write(to: url)
        // A folder Tuck can read but not write in, so the backup can't be made.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        let store = FileLibraryPersistence(fileURL: url, coalescingDelay: 30)
        let loaded = try #require(store.load())
        #expect(loaded.windows == windows)
        #expect(store.migrationBackupURL == nil)

        // Writable again later in the run, an edit still leaves the sessions file as it was.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        store.save(loaded)
        store.flush()
        #expect(try Data(contentsOf: url) == original)

        // The next launch migrates from it, this time with a backup.
        let next = FileLibraryPersistence(fileURL: url, coalescingDelay: 30)
        #expect(next.load() == loaded)
        #expect(next.migrationBackupURL != nil)
    }

    @Test func samplesFromEarlierVersionsAreTakenOutAsTheSessionsMerge() throws {
        let folder = try temporaryFolder()
        let samples = folder.appendingPathComponent("TuckSamples", isDirectory: true)
        try FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        let sampleNotes = samples.appendingPathComponent("Lisbon trip notes.txt")
        try Data("notes".utf8).write(to: sampleNotes)

        let sampleWindow = Self.window("Safari", "Lisbon flights — compare fares", at: 30)
        let checkIn = HeldItem.text("Check-in opens 24 hours before departure. Seat 14A, carry-on only.", addedAt: Self.at(30))
        let pourOver = HeldItem.link(URL(string: "https://www.example.com/products/ceramic-pour-over")!,
                                     title: "Ceramic pour-over set", addedAt: Self.at(30))
        var sessionsFile = file
        // A sample in the archived session, one in the current one, a sample file in Loose.
        sessionsFile.sessions[1].windows.insert(sampleWindow, at: 1)
        sessionsFile.sessions[1].items.append(checkIn)
        sessionsFile.sessions[0].items.append(pourOver)
        sessionsFile.looseItems.append(.file(sampleNotes, addedAt: Self.at(90)))
        sessionsFile.sampleWindows = [sampleWindow.id]
        let url = folder.appendingPathComponent("library.json")
        let original = try sessionsFile.data()
        try original.write(to: url)

        let store = FileLibraryPersistence(fileURL: url, coalescingDelay: 30)
        let loaded = try #require(store.load())
        #expect(loaded.windows == windows)
        #expect(loaded.items == items)
        #expect(loaded.restStates == file.restStates)
        // The backup is the file as it was, samples and all.
        #expect(try Data(contentsOf: #require(store.migrationBackupURL)) == original)
    }

    @Test func aLibraryFromANewerTuckIsSetAsideNotMigrated() throws {
        var newer = file
        newer.version = 3
        let data = try newer.data()
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("library.json")
        try data.write(to: url)

        let store = FileLibraryPersistence(fileURL: url)
        #expect(store.load() == nil)
        #expect(store.migrationBackupURL == nil)
        #expect(try backups(in: folder).isEmpty)
        let setAside = try #require(store.setAsideURL)
        #expect(try Data(contentsOf: setAside) == data)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        // Whoever it records as resting can still be woken.
        #expect(store.recoveredRestStates["com.apple.Preview"]?.isResting == true)
    }

    @Test func aSessionsFileThatCanNotBeReadIsSetAsideWithoutABackup() throws {
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("library.json")
        let damaged = Data(#"{"version":1,"library":{"sessions":"lost"}}"#.utf8)
        try damaged.write(to: url)

        let store = FileLibraryPersistence(fileURL: url)
        #expect(store.load() == nil)
        #expect(store.migrationBackupURL == nil)
        #expect(try backups(in: folder).isEmpty)
        #expect(try Data(contentsOf: #require(store.setAsideURL)) == damaged)
    }

    /// Uninstall deletes what Tuck wrote; the backup made while merging sessions is Tuck's too.
    @Test func uninstallAlsoRemovesTheSessionsBackup() throws {
        let root = try temporaryFolder()
        let folder = SupportFolder(directory: root)
        try file.data().write(to: folder.library)
        let store = FileLibraryPersistence(fileURL: folder.library, coalescingDelay: 30)
        #expect(store.load() != nil)
        store.flush()
        let backup = try #require(store.migrationBackupURL)

        #expect(SupportFolder.isTucks(backup.lastPathComponent))
        #expect(folder.removeTucksFiles())
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    /// A file `main`'s own build wrote, byte for byte but for line breaks: Work and Personal with windows
    /// and items, an archived Thesis, a Loose note and a resting Mail.
    @Test func aLibraryTheSessionsBuildWroteMergesWhole() throws {
        let url = try temporaryFolder().appendingPathComponent("library.json")
        try Data(Self.writtenBySessionsBuild.utf8).write(to: url)

        let loaded = try #require(FileLibraryPersistence(fileURL: url, coalescingDelay: 30).load())
        #expect(loaded.windows.map(\.title) == ["Chapter 3.pdf", "Inbox", "Pull request 42", "Docs – Swift"])
        #expect(loaded.windows.map(\.method) == [.offScreen, .hiddenWithApp, .offScreen, .offScreen])
        #expect(loaded.windows.allSatisfy { $0.originalFrame == WindowFrame(x: 40, y: 60, width: 900, height: 700) })
        #expect(loaded.items.map(\.kind) == [.text, .music, .stack, .link, .file, .text])
        #expect(loaded.items.map(\.title) == ["Loose note", "Random Access Memories", "2 files", "macOS", "plan.pdf",
                                               "Call the bank about the card"])
        #expect(loaded.items.first { $0.kind == .stack }?.children?.map(\.title) == ["one", "two"])
        #expect(loaded.restState(for: "com.apple.Mail").isResting)
    }

    static let writtenBySessionsBuild = #"""
        {"library":{"sessions":[{"id":"24CB68D3-9154-4269-BEF7-619C1B414B8D","color":"coral","parkedWindows":[{"hasFrozenPreview":false,
        "method":"offScreen","originalFrame":{"width":900,"y":60,"x":40,"height":700},"displayID":"1",
        "id":"79DC0AA7-0AE5-42D5-AAA8-2ECBF60DDC71","displayName":"Built-in Display","tuckedAt":800000120,
        "app":{"name":"Safari","bundleID":"com.apple.Safari"},"title":"Pull request 42"},{"title":"Docs – Swift",
        "displayID":"1","tuckedAt":800000060,"originalFrame":{"y":60,"height":700,"width":900,"x":40},
        "app":{"bundleID":"com.apple.Safari","name":"Safari"},"displayName":"Built-in Display","hasFrozenPreview":false,
        "method":"offScreen","id":"78F5CA70-4845-4ACB-B414-C12F443D9F3A"}],"isArchived":false,"heldItems":[{"sourceAppName":"Finder",
        "title":"plan.pdf","kind":"file","url":"file:\/\/\/Volumes\/NoSuchDrive-Crosscheck\/Trip\/plan.pdf",
        "addedAt":800000240,"id":"6B6A632A-5EB7-4954-8BB9-3692EE199DA4"},{"sourceAppName":"Notes","title":"Call the bank about the card",
        "kind":"text","addedAt":800000180,"text":"Call the bank about the card","id":"B6370D29-6CFB-47D4-A8A3-EC60B9C15415"}],
        "createdAt":800000000,"intention":"work"},{"heldItems":[{"id":"EE456FE2-1CFF-4C29-A3F4-1F995EACBCB0",
        "kind":"stack","title":"2 files","addedAt":800000480,"children":[{"addedAt":800000480,"kind":"text",
        "title":"one","id":"126DA899-6271-4828-A0F9-AAE1FC5CE151","text":"one"},{"addedAt":800000480,
        "kind":"text","title":"two","id":"A7AC5CCE-FBBE-4E68-8B0A-41B963D754CB","text":"two"}]},{"id":"D58A0B65-52D8-4FF0-86C5-7F6D7D2CA034",
        "kind":"link","url":"https:\/\/www.apple.com\/macos\/","title":"macOS","sourceAppName":"Safari",
        "addedAt":800000420}],"isArchived":false,"color":"yellow","parkedWindows":[{"hasFrozenPreview":false,
        "id":"D1FD3F11-5B19-43DE-96D4-37E5DC6133A3","title":"Inbox","displayID":"1","originalFrame":{"y":60,
        "width":900,"x":40,"height":700},"method":"hiddenWithApp","app":{"name":"Mail","bundleID":"com.apple.Mail"},
        "displayName":"Built-in Display","tuckedAt":800000360}],"createdAt":800000300,"id":"4885DF0F-5DC8-47F4-8469-6D51F8FD8ED0",
        "intention":"personal"},{"name":"Thesis","createdAt":800000540,"color":"amber","isArchived":true,
        "id":"79F74437-1407-41DE-903C-3276EF7F25F9","parkedWindows":[{"originalFrame":{"width":900,
        "height":700,"y":60,"x":40},"displayID":"1","method":"offScreen","displayName":"Built-in Display",
        "app":{"bundleID":"com.apple.Preview","name":"Preview"},"id":"C5DAEC8E-2F65-44CA-8C9C-C4AB49E067F0",
        "tuckedAt":800000600,"title":"Chapter 3.pdf","hasFrozenPreview":false}],"heldItems":[{"title":"Random Access Memories",
        "kind":"music","url":"https:\/\/music.apple.com\/album\/1440818584","addedAt":800000660,"id":"02AB81D1-85CF-466E-8EC6-3521A9BD8654"}]}],
        "currentSessionID":"24CB68D3-9154-4269-BEF7-619C1B414B8D","looseItems":[{"kind":"text","text":"Loose note",
        "addedAt":800000720,"id":"7F450696-3891-418B-968C-7FF8A2214251","title":"Loose note"}],"restStates":{"com.apple.Mail":{"resting":{"process":{"pid":4242,
        "startTime":1,"executablePath":"\/System\/Applications\/Mail.app","bundleID":"com.apple.Mail"},
        "since":800000780}}}},"version":1}
        """#
}
