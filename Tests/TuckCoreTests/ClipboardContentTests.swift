import Foundation
import Testing
@testable import TuckCore

@Suite("Clipboard content")
struct ClipboardContentTests {
    private func makeTemporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TuckTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func age(_ url: URL, by seconds: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-seconds)], ofItemAtPath: url.path)
    }

    @Test func aCopyWithNoKindGivenIsRecognisedWhenRecorded() {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        history.record(text: "https://apple.com")
        history.record(ClipboardCapture(text: "#2F6FED", recognition: ContentRecognition(category: .text)))
        #expect(history.entries.map(\.category) == [.text, .link])
    }

    @Test func imagesAndFilesNeedNoText() {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        #expect(history.record(ClipboardCapture(text: "")) == .empty)
        let image = ClipboardCapture(text: "", recognition: ContentRecognition(category: .image),
                                     payload: ClipPayload(imageFile: "A.png", key: "image:abc"))
        #expect(history.record(image) == .recorded)
        let files = ClipboardCapture(text: "", payload: ClipPayload(fileURLs: [URL(fileURLWithPath: "/tmp/a.txt")], key: "files:a"))
        #expect(history.record(files) == .recorded)
        #expect(history.entries.count == 2)
    }

    @Test func theSameImageOrFilesCopiedAgainMoveToTheTop() {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = ClipboardCapture(text: "", payload: ClipPayload(imageFile: "A.png", key: "image:abc"))
        history.record(first, now: start)
        history.record(text: "between", now: start.addingTimeInterval(1))
        // Same picture, written to a new file and with other text: still the same copy.
        let again = ClipboardCapture(text: "photo.png", payload: ClipPayload(imageFile: "B.png", key: "image:abc"))
        #expect(history.record(again, now: start.addingTimeInterval(2)) == .movedToTop)
        #expect(history.entries.count == 2)
        #expect(history.entries[0].payload?.imageFile == "A.png")
        #expect(history.entries[0].copyCount == 2)
        #expect(history.entries[0].lastCopiedAt == start.addingTimeInterval(2))
    }

    @Test func copyingAgainFromTuckTouchesTheEntry() {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        let start = Date(timeIntervalSince1970: 1_000_000)
        history.record(text: "first", now: start)
        history.record(text: "second", now: start)
        let id = history.entries[1].id
        history.touch(id: id, now: start.addingTimeInterval(5))
        #expect(history.entries.map(\.text) == ["first", "second"])
        #expect(history.entries[0].copyCount == 2)
        #expect(history.entries[0].lastCopiedAt == start.addingTimeInterval(5))
        history.touch(id: UUID())
        #expect(history.entries.count == 2)
    }

    @Test func whatIsLearnedLaterIsSavedAndSearched() {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        history.record(ClipboardCapture(text: "", recognition: ContentRecognition(category: .screenshot),
                                        payload: ClipPayload(imageFile: "A.png", key: "image:abc"),
                                        sourceAppName: "Screenshot"))
        let id = history.entries[0].id
        history.update(id: id, preview: ClipPreview(recognizedText: "Quarterly numbers", iconFile: "I.png"))
        history.update(id: UUID(), preview: ClipPreview(title: "Gone"))
        let entry = history.entries[0]
        #expect(entry.preview?.recognizedText == "Quarterly numbers")
        #expect(entry.searchText.contains("Quarterly numbers"))
        #expect(entry.searchText.contains("Screenshot"))
        #expect(history.assetNames == ["A.png", "I.png"])
        #expect(SearchQuery.parse("screenshots quarterly").matches(searchText: entry.searchText, category: entry.category,
                                                                    date: entry.lastCopiedAt))
    }

    /// A link's page picture is kept with its preview, and its file is kept while the link is.
    @Test func aPagePictureIsKeptWithItsLink() throws {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        history.record(ClipboardCapture(text: "https://apple.com", recognition: ContentRecognition(category: .link)))
        let id = history.entries[0].id
        history.update(id: id, preview: ClipPreview(title: "Apple", iconFile: "I.png", pageImageFile: "P.jpg"))
        #expect(history.assetNames == ["I.png", "P.jpg"])
        let decoded = try JSONDecoder().decode(ClipPreview.self, from: JSONEncoder().encode(history.entries[0].preview))
        #expect(decoded.pageImageFile == "P.jpg")
        // Saved before pages had pictures, a preview loads without one.
        let older = try JSONDecoder().decode(ClipPreview.self, from: Data(#"{"title":"Apple","iconFile":"I.png"}"#.utf8))
        #expect(older.pageImageFile == nil)
        #expect(older.iconFile == "I.png")
    }

    @Test func aFileIsFoundByItsName() {
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        let url = URL(fileURLWithPath: "/Users/Shared/Launch film.mov")
        history.record(ClipboardCapture(text: "", recognition: ContentRecognition(category: .video),
                                        payload: ClipPayload(fileURLs: [url], key: "files:film")))
        #expect(history.entries[0].searchText.contains("Launch film.mov"))
        #expect(history.entries[0].searchText.contains("Video"))
    }

    /// History saved before Tuck knew kinds has only text; it loads, and loading recognises it.
    @Test func historyFromBeforeKindsLoadsAndIsRecognised() throws {
        let id = UUID()
        let json = """
            {"isEnabled":true,"retention":"untilCleared","excludedBundleIDs":[],
             "entries":[{"id":"\(id.uuidString)","text":"https://apple.com","sourceAppName":"Safari",
                         "firstCopiedAt":800000000,"lastCopiedAt":800000000,"copyCount":3}]}
            """
        var history = try JSONDecoder().decode(ClipboardHistory.self, from: Data(json.utf8))
        #expect(history.entries.first?.recognition == nil)
        #expect(history.entries.first?.category == .text)
        history.recognizeUnrecognized()
        #expect(history.entries.first?.category == .link)
        #expect(history.entries.first?.id == id)
        #expect(history.entries.first?.copyCount == 3)
        // And it round-trips with what it now knows.
        let again = try JSONDecoder().decode(ClipboardHistory.self, from: JSONEncoder().encode(history))
        #expect(again == history)
    }

    @Test func assetsAreNamedFreshAndTheUnnamedOnesGo() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardAssetStore(directory: root.appendingPathComponent("Clipboard"))
        let kept = try store.write(Data("kept".utf8), extension: "png")
        let old = try store.write(Data("old".utf8), extension: "png")
        let young = try store.write(Data("young".utf8), extension: "rtf")
        #expect(kept.hasSuffix(".png"))
        #expect(UUID(uuidString: (kept as NSString).deletingPathExtension) != nil)
        let foreign = store.directory.appendingPathComponent("notes.txt")
        try Data("theirs".utf8).write(to: foreign)
        try age(store.url(for: kept), by: 600)
        try age(store.url(for: old), by: 600)
        try age(foreign, by: 600)

        store.removeUnreferenced(keeping: [kept])
        let left = try FileManager.default.contentsOfDirectory(atPath: store.directory.path).sorted()
        #expect(left == [kept, young, "notes.txt"].sorted())

        // Clearing takes every asset, and leaves the folder while something else is in it.
        store.removeAll()
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == ["notes.txt"])
        try FileManager.default.removeItem(at: foreign)
        _ = try store.write(Data("last".utf8), extension: "png")
        store.removeAll()
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
    }

    @Test func savingTheHistoryDeletesAssetsItNoLongerNames() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardAssetStore(directory: root.appendingPathComponent("Clipboard"))
        let used = try store.write(Data("used".utf8), extension: "png")
        let dropped = try store.write(Data("dropped".utf8), extension: "png")
        try age(store.url(for: used), by: 600)
        try age(store.url(for: dropped), by: 600)
        var history = ClipboardHistory(isEnabled: true, retention: .untilCleared)
        history.record(ClipboardCapture(text: "", payload: ClipPayload(imageFile: used, key: "image:used")))

        let persistence = FileClipboardPersistence(fileURL: root.appendingPathComponent("clipboard-history.json"),
                                                   assets: store, coalescingDelay: 600)
        persistence.save(history)
        persistence.flush()
        #expect(FileManager.default.fileExists(atPath: store.url(for: used).path))
        #expect(!FileManager.default.fileExists(atPath: store.url(for: dropped).path))
    }

    @Test func uninstallEmptiesTheClipboardFolderToo() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = SupportFolder(directory: root)
        try Data("{}".utf8).write(to: folder.clipboardHistory)
        _ = try folder.clipboardAssets.write(Data("image".utf8), extension: "png")
        _ = try folder.clipboardAssets.write(Data("styled".utf8), extension: "rtf")
        #expect(folder.removeTucksFiles())
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
