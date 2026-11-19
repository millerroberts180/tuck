#if DEBUG
import AppKit
import TuckCore

/// A copy of every kind, for the snapshots: made in code, with its pictures and styling written to a
/// throwaway folder, so no snapshot reads the person's own clipboard or any file outside the repository.
@MainActor
enum TileSamples {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    static let assets = ClipboardAssetStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("TuckSnapshotAssets", isDirectory: true))

    private static let card = """
        BEGIN:VCARD
        VERSION:3.0
        N:Lovelace;Ada;;;
        FN:Ada Lovelace
        ORG:Analytical Engines
        TEL:+44 20 7946 0958
        EMAIL:ada.lovelace@example.com
        END:VCARD
        """

    /// Records the samples oldest first, so the newest (a note) is at the top, as a real history reads.
    static func record(into clipboard: inout ClipboardHistory, assets: ClipboardAssetStore, now: Date) {
        var minutes = 400.0
        func add(_ text: String, _ recognition: ContentRecognition? = nil, payload: ClipPayload? = nil,
                 from app: (String, String)? = nil, preview: ClipPreview? = nil) {
            minutes -= 13
            let capture = ClipboardCapture(text: text, recognition: recognition, payload: payload,
                                           sourceBundleID: app?.0, sourceAppName: app?.1)
            guard clipboard.record(capture, now: now.addingTimeInterval(-minutes * 60)) == .recorded,
                  let preview, let id = clipboard.entries.first?.id else { return }
            clipboard.update(id: id, preview: preview)
        }
        let safari = ("com.apple.Safari", "Safari")
        let finder = ("com.apple.finder", "Finder")
        let mail = ("com.apple.mail", "Mail")
        let docs = ["README.md", "Package.swift", "docs/architecture.md", "docs/decision-log.md"].map {
            repo.appendingPathComponent($0)
        }
        // What capture records of copied files: their sizes together.
        func bytes(_ urls: [URL]) -> Int? {
            let total = urls.compactMap { (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }.reduce(0, +)
            return total > 0 ? total : nil
        }

        add("Launch film.mov", ContentRecognition(category: .video),
            payload: ClipPayload(fileURLs: [URL(fileURLWithPath: "/Users/Shared/Launch film.mov")], key: "files:film"),
            from: finder, preview: ClipPreview(duration: 94))
        add("Get Lucky.m4a", ContentRecognition(category: .audio),
            payload: ClipPayload(fileURLs: [URL(fileURLWithPath: "/Users/Shared/Get Lucky.m4a")], key: "files:song"),
            from: finder, preview: ClipPreview(title: "Get Lucky", artist: "Daft Punk", duration: 248))
        add(docs.suffix(3).map(\.lastPathComponent).joined(separator: "\n"), ContentRecognition(category: .stack),
            payload: ClipPayload(fileURLs: Array(docs.suffix(3)), byteCount: bytes(Array(docs.suffix(3))), key: "files:stack"),
            from: finder)
        add("docs", ContentRecognition(category: .folder),
            payload: ClipPayload(fileURLs: [repo.appendingPathComponent("docs")], key: "files:docs"), from: finder)
        let logo = repo.appendingPathComponent("design/logo/png/tuck-appicon-1024.png")
        add(logo.lastPathComponent, ContentRecognition(category: .image),
            payload: ClipPayload(fileURLs: [logo], byteCount: bytes([logo]), key: "files:logo"), from: finder)
        add(docs[0].lastPathComponent, ContentRecognition(category: .file),
            payload: ClipPayload(fileURLs: [docs[0]], byteCount: bytes([docs[0]]), key: "files:readme"), from: finder)
        // A made-up key that only starts like a real one, to show how keys are masked. It is put together
        // here so no scanner takes the source for a real key.
        add("sk-ant-" + "api03-EXAMPLE-NOT-A-REAL-KEY-Ab3F")
        add("~/Developer/Tuck/Package.swift", from: ("com.apple.Terminal", "Terminal"))
        add("🎉")
        add("1 Infinite Loop, Cupertino, CA 95014", from: mail)
        add("Tuesday 17 November 2026 at 15:00", from: mail)
        add(card, ContentClassifier.contact(card), from: ("com.apple.AddressBook", "Contacts"))
        add("#2F6FED", from: ("com.figma.Desktop", "Figma"))
        add("+1 (415) 555-0132", from: safari)
        add("650.555.0199", from: ("com.apple.MobileSMS", "Messages"))
        add("+44 20 7946 0958", from: mail)
        add("hello@tuck.app", from: mail)
        // The same address as the card's, so the two share a badge.
        add("ada.lovelace@example.com", from: mail)
        // Pages as their previews keep their icons: a touch icon drawn to fill its square, and a favicon.
        let touchIcon = siteIcon(large: true).flatMap { try? assets.write($0, extension: "png") }
        let favicon = siteIcon(large: false).flatMap { try? assets.write($0, extension: "png") }
        add("https://open.spotify.com/album/2Kh43m04B1UkVcpcRa1Zug", from: ("com.spotify.client", "Spotify"),
            preview: touchIcon.map { ClipPreview(iconFile: $0) })
        add("https://developer.apple.com/design/human-interface-guidelines", from: safari,
            preview: ClipPreview(title: "Human Interface Guidelines", iconFile: favicon))
        add("func greet(_ name: String) -> String {\n    // Say hello\n    return \"Hello, \\(name)\"\n}",
            from: ("com.apple.dt.Xcode", "Xcode"))
        // Code with a blank line between its parts, longer than any card shows, and a single command.
        add("import SwiftUI\n\nstruct ContentView: View {\n    @State private var count = 0\n\n    var body: some View {\n"
            + "        Button(\"Tapped \\(count) times\") { count += 1 }\n    }\n}", from: ("com.apple.dt.Xcode", "Xcode"))
        add("git log --oneline --graph --decorate -n 20", ContentRecognition(category: .code, language: "Shell"),
            from: ("com.apple.Terminal", "Terminal"))
        if let rtf = richText(), let name = try? assets.write(rtf, extension: "rtf") {
            add("Quarterly review: notes from Thursday, and the deck to read first.", ContentRecognition(category: .richText),
                payload: ClipPayload(richTextFile: name), from: ("com.apple.iWork.Pages", "Pages"))
        }
        if let png = picture(screenshot: true), let name = try? assets.write(png, extension: "png") {
            add("", ContentRecognition(category: .screenshot),
                payload: ClipPayload(imageFile: name, pixelWidth: 2940, pixelHeight: 1912, byteCount: png.count,
                                     key: "image:shot"),
                from: ("com.apple.screencaptureui", "Screenshot"),
                preview: ClipPreview(recognizedText: "Tuck Settings General Clipboard history"))
        }
        if let png = picture(screenshot: false), let name = try? assets.write(png, extension: "png") {
            add("", ContentRecognition(category: .image),
                payload: ClipPayload(imageFile: name, pixelWidth: 1600, pixelHeight: 1000, byteCount: png.count,
                                     key: "image:photo"),
                from: safari)
        }
        // A page that gives a picture for sharing, as its preview keeps it.
        if let png = picture(screenshot: false), let image = NSImage(data: png),
           let jpeg = ClipboardEnricher.jpeg(image, width: ClipboardEnricher.pageImageWidth),
           let name = try? assets.write(jpeg, extension: "jpg") {
            add("https://www.apple.com/newsroom/", from: safari,
                preview: ClipPreview(title: "Newsroom", iconFile: favicon, pageImageFile: name))
        }
        // A page whose picture is mostly white, against the card's grey.
        if let png = brightPicture(), let image = NSImage(data: png),
           let jpeg = ClipboardEnricher.jpeg(image, width: ClipboardEnricher.pageImageWidth),
           let name = try? assets.write(jpeg, extension: "jpg") {
            add("https://github.com/", from: safari,
                preview: ClipPreview(title: "GitHub · Change is constant. GitHub keeps you ahead.", iconFile: favicon,
                                     pageImageFile: name))
        }
        add("Water the plants on Thursday, and leave the key with Ana.", from: ("com.apple.Notes", "Notes"))
    }

    /// A drawn page picture that is mostly white, as many sites' sharing pictures are: a dark headline, a
    /// line under it and a button on the left, and a pale window with coloured blocks on the right.
    private static func brightPicture() -> Data? {
        let size = CGSize(width: 640, height: 400)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        // Drawn in the middle, which a card's wide preview keeps.
        NSColor(white: 0.12, alpha: 1).setFill()
        for (row, width) in [230.0, 170].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: 48, y: 236 - CGFloat(row) * 36, width: width, height: 24),
                         xRadius: 8, yRadius: 8).fill()
        }
        NSColor(white: 0.7, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 172, width: 200, height: 10), xRadius: 5, yRadius: 5).fill()
        Theme.accentNSColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 126, width: 116, height: 32), xRadius: 16, yRadius: 16).fill()
        NSColor(white: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 320, y: 112, width: 280, height: 176), xRadius: 18, yRadius: 18).fill()
        for (index, color) in [NSColor.systemGreen, .systemOrange, .systemPurple].enumerated() {
            color.withAlphaComponent(0.8).setFill()
            NSBezierPath(roundedRect: NSRect(x: 344, y: 236 - CGFloat(index) * 48, width: 232, height: 32),
                         xRadius: 8, yRadius: 8).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func richText() -> Data? {
        let text = NSMutableAttributedString()
        let body = NSFont.systemFont(ofSize: 14)
        let italic = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        text.append(NSAttributedString(string: "Quarterly review", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]))
        text.append(NSAttributedString(string: ": notes from ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "Thursday", attributes: [.font: italic]))
        text.append(NSAttributedString(string: ", and ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "the deck", attributes: [.font: body, .link: URL(string: "https://example.com")!]))
        text.append(NSAttributedString(string: " to read first.", attributes: [.font: body]))
        return text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:])
    }

    /// A drawn site icon: a 128-pixel touch icon (white rings on green, to its edges) or a 32-pixel favicon
    /// (a dark mark on a clear ground).
    private static func siteIcon(large: Bool) -> Data? {
        let side = large ? 128 : 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        let size = CGFloat(side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if large {
            NSColor(srgbRed: 0.11, green: 0.6, blue: 0.4, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: size, height: size).fill()
            NSColor.white.setStroke()
            for radius in [18.0, 32, 46] {
                let ring = NSBezierPath(ovalIn: NSRect(x: 64 - radius, y: 64 - radius, width: radius * 2, height: radius * 2))
                ring.lineWidth = 8
                ring.stroke()
            }
        } else {
            NSColor(white: 0.12, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: 18, height: 18)).fill()
            NSBezierPath(roundedRect: NSRect(x: 15, y: 15, width: 14, height: 14), xRadius: 3, yRadius: 3).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// A drawn photograph (a dusk sky over hills) or a drawn screenshot (a window with a sidebar).
    private static func picture(screenshot: Bool) -> Data? {
        let size = CGSize(width: 640, height: 400)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if screenshot {
            NSColor(white: 0.93, alpha: 1).setFill()
            NSRect(origin: .zero, size: size).fill()
            NSColor(white: 0.86, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 170, height: size.height).fill()
            NSColor(white: 0.97, alpha: 1).setFill()
            NSRect(x: 0, y: size.height - 44, width: size.width, height: 44).fill()
            for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 16 + CGFloat(index) * 22, y: size.height - 30, width: 14, height: 14)).fill()
            }
            Theme.accentNSColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: 12, y: size.height - 96, width: 146, height: 28), xRadius: 6, yRadius: 6).fill()
            for (row, width) in [380, 300, 340, 260, 400, 220, 320].enumerated() {
                NSColor(white: 0.62, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: 200, y: size.height - 96 - CGFloat(row) * 40, width: CGFloat(width), height: 12),
                             xRadius: 6, yRadius: 6).fill()
            }
        } else {
            NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.18, blue: 0.38, alpha: 1),
                                NSColor(srgbRed: 0.55, green: 0.33, blue: 0.62, alpha: 1),
                                NSColor(srgbRed: 0.98, green: 0.62, blue: 0.36, alpha: 1)])?
                .draw(in: NSRect(origin: .zero, size: size), angle: 270)
            NSColor(srgbRed: 1, green: 0.85, blue: 0.6, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: NSRect(x: 380, y: 150, width: 90, height: 90)).fill()
            for (index, shade) in [0.22, 0.14, 0.08].enumerated() {
                let hills = NSBezierPath()
                hills.move(to: .zero)
                for step in 0...16 {
                    let x = CGFloat(step) * 40
                    let y = 150 - CGFloat(index) * 40 + sin(CGFloat(step) * 0.7 + CGFloat(index) * 2) * 26
                    hills.line(to: CGPoint(x: x, y: y))
                }
                hills.line(to: CGPoint(x: size.width, y: 0))
                hills.close()
                NSColor(srgbRed: shade, green: shade * 0.9, blue: min(shade * 1.6, 1), alpha: 1).setFill()
                hills.fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
