import Foundation
import Testing
@testable import TuckCore

@Suite("Contact badges")
struct ContactBadgeTests {
    @Test func aNameGivesItsFirstAndLastWordsInitials() {
        #expect(ContactBadge.initials(name: "Ada Lovelace") == "AL")
        #expect(ContactBadge.initials(name: "Ada King Lovelace") == "AL")
        #expect(ContactBadge.initials(name: "ada") == "A")
        #expect(ContactBadge.initials(name: "  grace   hopper ") == "GH")
        #expect(ContactBadge.initials(name: "José Álvarez") == "JÁ")
        #expect(ContactBadge.initials(name: "山田 太郎") == "山太")
        // Digits and punctuation are skipped, in a word or as one.
        #expect(ContactBadge.initials(name: "(Ada) 2 Lovelace!") == "AL")
        #expect(ContactBadge.initials(name: "R2-D2") == "R")
        #expect(ContactBadge.initials(name: "123 456").isEmpty)
        #expect(ContactBadge.initials(name: "").isEmpty)
    }

    @Test func anAddressGivesItsNamePartsInitials() {
        #expect(ContactBadge.initials(email: "ada.lovelace@x.com") == "AL")
        #expect(ContactBadge.initials(email: "ada@x.com") == "A")
        #expect(ContactBadge.initials(email: "j_smith99@x.com") == "JS")
        #expect(ContactBadge.initials(email: "Mary-Jane.Watson@x.com") == "MW")
        #expect(ContactBadge.initials(email: "ada+news@x.com") == "A")
        // Nothing to make initials of: the at sign stands in.
        #expect(ContactBadge.initials(email: "99@x.com") == "@")
        #expect(ContactBadge.initials(email: "@x.com") == "@")
    }

    @Test func aPersonKeepsTheirColour() {
        let index = ContactBadge.colorIndex(for: "ada.lovelace@example.com")
        #expect(index == ContactBadge.colorIndex(for: "Ada.Lovelace@Example.com "))
        #expect(ContactBadge.palette.indices.contains(index))
        // FNV-1a, not a per-launch hash: the same address gives the same colour on every Mac.
        #expect(ContactBadge.colorIndex(for: "a") == Int((0xcbf29ce484222325 ^ 0x61) &* UInt64(0x100000001b3) % 6))
        let used = Set((0..<60).map { ContactBadge.colorIndex(for: "person\($0)@example.com") })
        #expect(used.count == ContactBadge.palette.count)
        #expect(ContactBadge.colorIndex(for: "anyone", count: 0) == 0)
    }

    @Test func lettersTakeWhicheverOfInkAndWhiteReadsBetter() {
        for color in ContactBadge.palette {
            let ink = ContactBadge.contrast(ContactBadge.ink, color)
            #expect(ContactBadge.prefersInk(on: color))
            #expect(ink >= 4.5, "\(color.hex)")
        }
        #expect(!ContactBadge.prefersInk(on: RGBAColor(red: 0.1, green: 0.2, blue: 0.5)))
        #expect(abs(ContactBadge.contrast(RGBAColor(red: 0, green: 0, blue: 0), RGBAColor(red: 1, green: 1, blue: 1)) - 21) < 0.01)
    }
}
