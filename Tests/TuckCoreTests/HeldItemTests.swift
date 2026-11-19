import Foundation
import Testing
@testable import TuckCore

@Suite("Held items")
struct HeldItemTests {
    func window(_ title: String) -> ParkedWindow {
        ParkedWindow(app: AppIdentity(bundleID: "a", name: "A"), title: title,
                     originalFrame: WindowFrame(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func itemsJoinTheOneStreamNewestFirst() {
        var library = TuckLibrary()
        let first = HeldItem.text("first")
        let second = HeldItem.text("second")

        library.add(first)
        library.add(second)
        #expect(library.items.map(\.id) == [second.id, first.id])
        #expect(library.heldItem(id: first.id) == first)
        #expect(library.heldItem(id: UUID()) == nil)
    }

    @Test func windowsJoinTheStreamNewestFirstAndASetKeepsItsOrder() {
        var library = TuckLibrary()
        let older = window("older"), newer = window("newer")
        library.park(older)
        library.park(newer)
        #expect(library.windows.map(\.id) == [newer.id, older.id])

        // Tucked together, the first of a set ends up on top, each its own row.
        let trio = [window("one"), window("two"), window("three")]
        library.parkAll(trio)
        #expect(library.windows.map(\.title) == ["one", "two", "three", "newer", "older"])
        #expect(library.window(id: older.id) == older)
        #expect(library.removeWindow(id: newer.id) == newer)
        #expect(library.removeWindow(id: newer.id) == nil)
        #expect(library.window(id: newer.id) == nil)
    }

    @Test func everythingCountsAndAStackIsOneRow() {
        var library = TuckLibrary()
        #expect(library.isEmpty && library.totalItemCount == 0)
        library.park(window("w"))
        #expect(!library.isEmpty && library.totalItemCount == 1)
        library.add(.stack((1...3).map { HeldItem.file(URL(fileURLWithPath: "/tmp/n\($0)")) }))
        library.add(.text("note"))
        #expect(library.totalItemCount == 3)
    }

    @Test func clearingTakesEveryHeldItemAndLeavesTheWindows() {
        var library = TuckLibrary()
        let tucked = window("w")
        library.park(tucked)
        let note = HeldItem.text("note"), link = HeldItem.link(URL(string: "https://example.com")!)
        library.add(note)
        library.add(link)
        let removed = library.removeAllItems()
        #expect(removed.map(\.id) == [link.id, note.id])
        #expect(library.items.isEmpty)
        #expect(library.windows == [tucked])
    }

    @Test func textItemsCanBeEdited() {
        var library = TuckLibrary()
        let item = HeldItem.text("draft")
        let link = HeldItem.link(URL(string: "https://example.com")!)
        library.add(item)
        library.add(link)

        let updatedOK = library.updateText(itemID: item.id, to: "Final wording\nsecond line")
        #expect(updatedOK)
        let updated = library.heldItem(id: item.id)
        #expect(updated?.text == "Final wording\nsecond line")
        #expect(updated?.title == "Final wording")
        // Only text has words to edit.
        let linkEdited = library.updateText(itemID: link.id, to: "nope")
        let missingEdited = library.updateText(itemID: UUID(), to: "nope")
        #expect(!linkEdited && !missingEdited)
        #expect(library.heldItem(id: link.id) == link)
    }

    @Test func classifierDistinguishesFilesLinksAndMusic() {
        #expect(HeldItemClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.pdf")) == .file)
        #expect(HeldItemClassifier.kind(for: URL(string: "https://example.com/page")!) == .link)
        #expect(HeldItemClassifier.kind(for: URL(string: "https://open.spotify.com/track/abc")!) == .music)
        #expect(HeldItemClassifier.kind(for: URL(string: "spotify:track:abc")!) == .music)
        #expect(HeldItemClassifier.kind(for: URL(string: "https://artist.bandcamp.com/album/x")!) == .music)
    }

    @Test func textThatIsASingleURLBecomesALink() {
        let item = HeldItemClassifier.item(forText: "  https://music.apple.com/us/album/123  ")
        #expect(item?.kind == .music)
        #expect(HeldItemClassifier.item(forText: "see https://example.com later")?.kind == .text)
        #expect(HeldItemClassifier.item(forText: "   \n ") == nil)
    }
}
