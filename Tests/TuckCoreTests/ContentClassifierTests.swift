import Foundation
import Testing
@testable import TuckCore

@Suite("Content recognition")
struct ContentClassifierTests {
    private func kind(_ text: String, from app: String? = nil) -> ContentCategory {
        ContentClassifier.recognize(text: text, sourceBundleID: app).category
    }

    @Test func eachKindIsKnownByItsText() {
        #expect(kind("https://developer.apple.com/design") == .link)
        #expect(kind("www.example.com") == .link)
        #expect(kind("https://open.spotify.com/album/2Kh43m04B1UkVcpcRa1Zug") == .music)
        #expect(kind("hello@tuck.app") == .email)
        #expect(kind("mailto:hello@tuck.app") == .email)
        #expect(kind("+1 (415) 555-0132") == .phone)
        #expect(kind("#2F6FED") == .color)
        #expect(kind("rgb(47, 111, 237)") == .color)
        #expect(kind("~/Desktop/Tuck/Package.swift") == .path)
        #expect(kind("/usr/local/bin") == .path)
        #expect(kind("🎉") == .emoji)
        #expect(kind("BEGIN:VCARD\nVERSION:3.0\nFN:Ada Lovelace\nEND:VCARD") == .contact)
        #expect(kind("func greet() {\n    return\n}") == .code)
        #expect(kind("git status -sb") == .code)
        #expect(kind("[1, 2, 3, 4, 5]") == .code)
        #expect(kind("Pick up the prints before 6, and ask about the frame.") == .text)
        #expect(kind("   ") == .text)
    }

    @Test func datesAndAddressesAreTheWholeCopyNotAPartOfIt() {
        #expect(kind("Tuesday 17 November 2026 at 15:00") == .date)
        #expect(kind("2026-11-08") == .date)
        #expect(kind("1 Infinite Loop, Cupertino, CA 95014") == .address)
        // A sentence that mentions a day is still text.
        #expect(kind("Let's meet on Tuesday 17 November to go through the deck together.") == .text)
    }

    @Test func aDateSaysWhetherItNamedATime() {
        let timed = ContentClassifier.recognize(text: "Tuesday 17 November 2026 at 15:00")
        let day = ContentClassifier.recognize(text: "17 November 2026")
        #expect(timed.includesTime == true)
        #expect(day.includesTime == false)
        #expect(timed.date != nil)
    }

    @Test func keysAreNamedAndOrdinaryWordsAreNot() {
        // Made-up keys that only start like real ones, put together here so no scanner takes them for real.
        #expect(ContentClassifier.recognize(text: "sk-ant-" + "api03-EXAMPLE-NOT-A-REAL-KEY-Ab3F").name == "Anthropic API key")
        #expect(ContentClassifier.recognize(text: "ghp_" + "EXAMPLEnotARealToken0000000000000000").name == "GitHub token")
        #expect(ContentClassifier.recognize(text: "eyJ" + "hbGciOiJub25lIn0.eyJzdWIiOiJleGFtcGxlIn0.ZXhhbXBsZQ").category == .secret)
        #expect(ContentClassifier.recognize(text: "Bearer abcdefghijklmnopqrstuvwxyz").name == "Bearer token")
        // Too short to be a key, or a public key, which is meant to be shared.
        #expect(kind("sk-short") != .secret)
        #expect(kind("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl me@mac") != .secret)
    }

    @Test func coloursReadEveryCommonSpelling() {
        #expect(ContentClassifier.color(in: "#fff") == RGBAColor(red: 1, green: 1, blue: 1, alpha: 1))
        #expect(ContentClassifier.color(in: "#2F6FED80")?.alpha == Double(0x80) / 255)
        #expect(ContentClassifier.color(in: "rgba(0, 0, 0, 0.5)")?.alpha == 0.5)
        #expect(ContentClassifier.color(in: "rgb(100%, 0%, 0%)")?.red == 1)
        #expect(ContentClassifier.color(in: "rgb(300, 0, 0)") == nil)
        // Six hex digits without a "#" are as likely an ID as a colour.
        #expect(ContentClassifier.color(in: "2F6FED") == nil)
    }

    @Test func pathsNeedANameAfterTheSlash() {
        #expect(kind("/") != .path)
        #expect(kind("/24") != .path)
        #expect(kind("//comment") != .path)
        #expect(kind("~/") != .path)
        #expect(kind("file:///Users/Shared/notes.txt") == .path)
    }

    @Test func phoneNumbersNeedSevenToFifteenDigits() {
        #expect(kind("555 0132") == .phone)
        #expect(kind("12345") != .phone)
        #expect(kind("1234567890123456789") != .phone)
    }

    @Test func codeIsScoredAndTerminalsMakeCode() {
        #expect(kind("if (a == b) { run(); }") == .code)
        // One marker or two on a short line isn't enough: "a; b" is as likely prose.
        #expect(kind("let x = 1;") == .text)
        #expect(kind("This sentence has a { brace } and a semicolon; but it is prose and goes on for a while.") == .text)
        #expect(kind("make it so", from: "com.apple.Terminal") == .code)
        #expect(ContentClassifier.recognize(text: "func greet() {\n    return\n}").language == "Swift")
        #expect(ContentClassifier.recognize(text: "{\"name\": \"Tuck\", \"version\": 1}").language == "JSON")
        #expect(ContentClassifier.recognize(text: "git status -sb").language == "Shell")
    }

    @Test func emojiAreNamed() {
        #expect(ContentClassifier.recognize(text: "🎉").name == "Party popper")
        #expect(ContentClassifier.recognize(text: "🇬🇧").name == "Flag of United Kingdom")
        // Digits and letters are not emoji, even though Unicode lets some be.
        #expect(kind("#") != .emoji)
        #expect(kind("1") != .emoji)
    }

    @Test func aContactIsNamedFromItsCard() {
        let card = "BEGIN:VCARD\nVERSION:3.0\nN:Lovelace;Ada;;;\nORG:Analytical Engines;\nEND:VCARD"
        let recognition = ContentClassifier.contact(card)
        #expect(recognition.name == "Ada Lovelace")
        #expect(recognition.detail == "Analytical Engines")
    }

    @Test func richTextIsTextWithStylingWorthKeeping() {
        #expect(ContentClassifier.recognize(text: "Quarterly review", hasRichText: true).category == .richText)
        // Styling never outranks a kind: a styled link is still a link.
        #expect(ContentClassifier.recognize(text: "https://apple.com", hasRichText: true).category == .link)
    }

    @Test func filesAreKnownByTheirExtension() {
        func file(_ name: String, directory: Bool = false, screenshot: Bool = false) -> ContentCategory {
            ContentClassifier.category(forFile: URL(fileURLWithPath: "/tmp/" + name), isDirectory: directory,
                                       fromScreenshot: screenshot)
        }
        #expect(file("photo.HEIC") == .image)
        #expect(file("Screenshot 2026-11-08 at 10.00.00.png") == .screenshot)
        #expect(file("shot.png", screenshot: true) == .screenshot)
        #expect(file("song.m4a") == .audio)
        #expect(file("film.mov") == .video)
        #expect(file("notes.pdf") == .file)
        #expect(file("docs", directory: true) == .folder)
        // An app is a folder on disk but a file to the person.
        #expect(file("Tuck.app", directory: true) == .file)
    }
}
