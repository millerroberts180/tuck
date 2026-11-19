import AppKit
import CryptoKit
import TuckCore

/// Watches the general pasteboard only while the person has explicitly enabled clipboard history.
/// Reading changeCount avoids repeatedly requesting clipboard contents from other apps.
///
/// Each copy is read once, in the order macOS offers the richest form: files, then an image, a colour, a
/// contact card, then text (with its styling when that matters). The reading happens here on the main
/// thread; turning an image into a PNG, saving it and recognising what text is happens on a serial
/// background queue, so copies still land in the order they were made.
final class ClipboardCaptureService {
    var isEnabled = false {
        didSet {
            if isEnabled { start() } else { stop() }
        }
    }

    /// Whether macOS is holding back what other apps copy, reported when capture starts and at each copy.
    var onAccessChange: ((Bool) -> Void)?

    private let onCapture: (ClipboardCapture) -> Void
    private let assets: ClipboardAssetStore
    private let pasteboard = NSPasteboard.general
    private let work = DispatchQueue(label: "app.tuck.clipboard-capture", qos: .utility)
    private var timer: Timer?
    private var lastChangeCount = 0
    private var isHeldBack: Bool?

    /// Images bigger than this aren't kept: a copy that size is a design file's canvas, not a reference.
    static let maxImageBytes = 40_000_000
    /// Styling bigger than this isn't kept; the text still is.
    static let maxRichTextBytes = 512_000

    init(assets: ClipboardAssetStore, onCapture: @escaping (ClipboardCapture) -> Void) {
        self.assets = assets
        self.onCapture = onCapture
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        report(heldBack: Self.readsAreHeldBack(pasteboard))
        // AppKit posts nothing when the pasteboard changes, and watching copy shortcuts would miss copies
        // made from menus, so its change count is checked; this is the one repeating timer Tuck keeps at
        // rest, and it runs only while history is on. Twice a second, with leeway for the system to fold
        // the check into other wakeups, records a copy before anyone can open the panel to look for it.
        // Two copies inside half a second keep only the later one.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer?.tolerance = 0.15
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        let heldBack = Self.readsAreHeldBack(pasteboard)
        report(heldBack: heldBack)
        guard !heldBack else { return }
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !types.contains(where: ClipboardPrivateTypes.values.contains) else { return }
        // Tuck marks what it copies, and records those copies itself.
        if let marker = pasteboard.string(forType: SystemPasteboard.sourceType), marker == Bundle.main.bundleIdentifier {
            return
        }
        let source = NSWorkspace.shared.frontmostApplication
        guard source?.bundleIdentifier != Bundle.main.bundleIdentifier || Bundle.main.bundleIdentifier == nil else { return }
        guard let read = read(types: types, sourceBundleID: source?.bundleIdentifier) else { return }
        let base = ClipboardCapture(text: "", pasteboardTypes: types, sourceBundleID: source?.bundleIdentifier,
                                    sourceAppName: source?.localizedName)
        work.async { [assets, onCapture] in
            guard let capture = read.capture(base: base, assets: assets) else { return }
            DispatchQueue.main.async { onCapture(capture) }
        }
    }

    /// What one copy holds, read off the pasteboard as plain values the background queue can finish.
    enum Read {
        case files([URL])
        case image(Data, alreadyPNG: Bool)
        case color(RGBAColor, text: String?)
        case contact(String)
        case text(String, rtf: Data?)

        func capture(base: ClipboardCapture, assets: ClipboardAssetStore) -> ClipboardCapture? {
            var capture = base
            let fromScreenshot = ContentClassifier.isScreenshotSource(base.sourceBundleID)
            switch self {
            case .files(let urls):
                capture.text = urls.map(\.lastPathComponent).joined(separator: "\n")
                let sizes = urls.map { (try? $0.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])) }
                let total = sizes.compactMap { $0?.fileSize }.reduce(0, +)
                capture.payload = ClipPayload(fileURLs: urls, byteCount: total > 0 ? total : nil,
                                              key: "files:" + urls.map(\.path).joined(separator: "\n"))
                if urls.count == 1, let url = urls.first {
                    let category = ContentClassifier.category(forFile: url, isDirectory: sizes.first??.isDirectory == true,
                                                              fromScreenshot: fromScreenshot)
                    capture.recognition = ContentRecognition(category: category)
                } else {
                    capture.recognition = ContentRecognition(category: .stack)
                }
            case .image(let data, let alreadyPNG):
                guard let rep = NSBitmapImageRep(data: data) else { return nil }
                guard let png = alreadyPNG ? data : rep.representation(using: .png, properties: [:]),
                      let name = try? assets.write(png, extension: "png") else { return nil }
                let digest = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                capture.payload = ClipPayload(imageFile: name, pixelWidth: rep.pixelsWide, pixelHeight: rep.pixelsHigh,
                                              byteCount: png.count, key: "image:" + digest)
                capture.recognition = ContentRecognition(category: fromScreenshot ? .screenshot : .image)
            case .color(let color, let text):
                capture.text = text ?? color.hex
                capture.recognition = ContentRecognition(category: .color, color: color)
            case .contact(let card):
                capture.text = card
                capture.recognition = ContentClassifier.contact(card)
            case .text(let text, let rtf):
                capture.text = text
                var recognition = ContentClassifier.recognize(text: text, sourceBundleID: base.sourceBundleID)
                if recognition.category == .text, let rtf, RichTextStyling.isMeaningful(rtf),
                   let name = try? assets.write(rtf, extension: "rtf") {
                    recognition = ContentRecognition(category: .richText)
                    capture.payload = ClipPayload(richTextFile: name)
                }
                capture.recognition = recognition
            }
            return capture
        }
    }

    private func read(types: [String], sourceBundleID: String?) -> Read? {
        let string = pasteboard.string(forType: .string)
        let hasFileURL = types.contains(NSPasteboard.PasteboardType.fileURL.rawValue)
        if hasFileURL, let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return .files(urls)
        }
        // An image comes with text only as its address or name; text that says more is the copy.
        let stringIsIncidental = string.map { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || (!trimmed.contains(where: \.isWhitespace) && trimmed.count < 300)
        } ?? true
        if stringIsIncidental {
            if let png = pasteboard.data(forType: .png), png.count <= Self.maxImageBytes { return .image(png, alreadyPNG: true) }
            for type in [NSPasteboard.PasteboardType.tiff, NSPasteboard.PasteboardType("public.jpeg"),
                         NSPasteboard.PasteboardType("public.heic")] {
                if let data = pasteboard.data(forType: type) {
                    return data.count <= Self.maxImageBytes ? .image(data, alreadyPNG: false) : nil
                }
            }
        }
        if types.contains(NSPasteboard.PasteboardType.color.rawValue), let color = NSColor(from: pasteboard),
           let srgb = color.usingColorSpace(.sRGB) {
            let value = RGBAColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent,
                                  alpha: srgb.alphaComponent)
            return .color(value, text: string.flatMap { ContentClassifier.color(in: $0.trimmingCharacters(in: .whitespaces)) != nil ? $0 : nil })
        }
        if let card = pasteboard.string(forType: NSPasteboard.PasteboardType("public.vcard")),
           card.uppercased().contains("BEGIN:VCARD") {
            return .contact(card)
        }
        guard let string, !string.isEmpty else { return nil }
        let rtf = pasteboard.data(forType: .rtf).flatMap { $0.count <= Self.maxRichTextBytes ? $0 : nil }
        return .text(string, rtf: rtf)
    }

    private func report(heldBack: Bool) {
        guard heldBack != isHeldBack else { return }
        isHeldBack = heldBack
        onAccessChange?(heldBack)
    }

    /// From macOS 15.4 the system can ask, or refuse, before an app reads what another app copied. Asking
    /// would raise an alert at every copy, so capture waits until Tuck is allowed. Before Tuck has ever
    /// read, the behaviour is the default, and that first read's alert is what lists Tuck in Settings.
    private static func readsAreHeldBack(_ pasteboard: NSPasteboard) -> Bool {
        guard #available(macOS 15.4, *) else { return false }
        switch pasteboard.accessBehavior {
        case .ask, .alwaysDeny: return true
        default: return false
        }
    }

    /// Privacy & Security → Paste from Other Apps, where Tuck can be set to Allow.
    static func openPasteSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Whether copied styling says something the plain text doesn't: bold, italics, links, underlines or a
/// change of size. Text copied from a page in one plain font isn't rich text, whatever the pasteboard holds.
enum RichTextStyling {
    static func isMeaningful(_ rtf: Data) -> Bool {
        guard let text = NSAttributedString(rtf: rtf, documentAttributes: nil), text.length > 0 else { return false }
        var sizes = Set<CGFloat>()
        var styled = false
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, stop in
            guard range.length > 0 else { return }
            if attributes[.link] != nil || (attributes[.underlineStyle] as? Int ?? 0) != 0
                || (attributes[.strikethroughStyle] as? Int ?? 0) != 0 {
                styled = true
            }
            if let font = attributes[.font] as? NSFont {
                sizes.insert(font.pointSize.rounded())
                let traits = font.fontDescriptor.symbolicTraits
                if traits.contains(.bold) || traits.contains(.italic) { styled = true }
            }
            if styled { stop.pointee = true }
        }
        return styled || sizes.count > 1
    }
}

private enum ClipboardPrivateTypes {
    static let values: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType"
    ]
}
