import Foundation

/// Earlier versions of Tuck started with sample sessions (a Lisbon trip, a desk reply, a gift idea). A
/// library saved back then, always with sessions, still holds them, so merging it into the stream takes
/// them out: sample windows by the flag they were saved with, sample held items by their exact contents.
/// Rest records are kept.
enum EarlierSamples {
    /// Returns whether anything was removed.
    @discardableResult
    static func remove(from library: inout TuckLibrary, savedAs data: Data) -> Bool {
        var removed = false
        for id in sampleWindowIDs(in: data) {
            if library.removeWindow(id: id) != nil { removed = true }
        }
        for item in library.items where isSample(item) {
            library.removeHeldItem(id: item.id)
            removed = true
        }
        return removed
    }

    /// `isSample` is no longer part of a window, so the flag is read from the saved file itself.
    private struct Flags: Decodable {
        struct Window: Decodable { var id: UUID; var isSample: Bool? }
        struct Session: Decodable { var parkedWindows: [Window] }
        struct Library: Decodable { var sessions: [Session] }
        var library: Library
    }

    private static func sampleWindowIDs(in data: Data) -> [UUID] {
        guard let flags = try? JSONDecoder().decode(Flags.self, from: data) else { return [] }
        return flags.library.sessions.flatMap(\.parkedWindows).filter { $0.isSample == true }.map(\.id)
    }

    private static let sampleText = "Check-in opens 24 hours before departure. Seat 14A, carry-on only."
    private static let sampleLinks = [
        "https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd": "Lisbon evening playlist",
        "https://www.visitlisboa.com/en/places/alfama": "Alfama walking guide",
        "https://www.example.com/products/ceramic-pour-over": "Ceramic pour-over set",
    ]

    private static func isSample(_ item: HeldItem) -> Bool {
        switch item.kind {
        case .text: item.text == sampleText
        case .link, .music: item.url.map { sampleLinks[$0.absoluteString] == item.title } ?? false
        // The sample file was written to a TuckSamples folder in the temporary directory.
        case .file: item.url?.deletingLastPathComponent().lastPathComponent == "TuckSamples"
        case .stack: false
        }
    }
}
