import AppKit
import AVFoundation
import CoreLocation
import LinkPresentation
import MapKit
import TuckCore
import Vision

/// Learns more about a copy once, right after it is recorded (a link again when it is copied again without
/// its page's picture): the words in an image (on this Mac, with Vision), a song's or video's title,
/// artist and length (from the file's own tags), a link's page title, icon and the picture the page gives
/// for sharing, and an address's map. What it learns is
/// saved with the entry, so tiles draw it and search finds it without doing any of this twice.
final class ClipboardEnricher {
    private let assets: ClipboardAssetStore
    var readsTextInImages = true
    private let work = DispatchQueue(label: "app.tuck.clipboard-enrich", qos: .utility)

    /// Images are read for words only up to this size; bigger ones are left as they are.
    static let maxImageBytesForText = 25_000_000

    init(assets: ClipboardAssetStore) {
        self.assets = assets
    }

    /// Whether there is anything to learn about this entry with the current settings.
    func wants(_ entry: ClipboardEntry) -> Bool {
        switch entry.category {
        case .image, .screenshot: return readsTextInImages && imageURL(for: entry) != nil
        case .audio, .video: return entry.payload?.fileURLs?.first != nil
        case .link, .music: return webURL(for: entry) != nil
        case .address: return true
        default: return false
        }
    }

    /// Learns what it can about the entry, then calls back on the main thread with it (only if anything
    /// was learned).
    func enrich(_ entry: ClipboardEntry, completion: @escaping (ClipPreview) -> Void) {
        guard wants(entry) else { return }
        let deliver: (ClipPreview?) -> Void = { preview in
            guard let preview, preview != ClipPreview() else { return }
            DispatchQueue.main.async { completion(preview) }
        }
        switch entry.category {
        case .image, .screenshot:
            guard let url = imageURL(for: entry) else { return }
            work.async { deliver(Self.recognizeText(at: url).map { ClipPreview(recognizedText: $0) }) }
        case .audio, .video:
            guard let url = entry.payload?.fileURLs?.first else { return }
            Task.detached(priority: .utility) { deliver(await Self.mediaTags(at: url)) }
        case .link, .music:
            guard let url = webURL(for: entry) else { return }
            fetchLinkPreview(url, completion: deliver)
        case .address:
            fetchMap(for: entry.text, completion: deliver)
        default:
            break
        }
    }

    private func imageURL(for entry: ClipboardEntry) -> URL? {
        if let name = entry.payload?.imageFile { return assets.url(for: name) }
        guard let url = entry.payload?.fileURLs?.first, url.isFileURL else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size <= Self.maxImageBytesForText ? url : nil
    }

    private func webURL(for entry: ClipboardEntry) -> URL? {
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = text.lowercased().hasPrefix("www.") ? "https://" + text : text
        guard let url = URL(string: candidate), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    // MARK: Words in images

    /// The image's lines of text, top to bottom, or nil when it has none.
    static func recognizeText(at url: URL) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: url, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(4_000))
    }

    // MARK: Media tags

    static func mediaTags(at url: URL) async -> ClipPreview? {
        let asset = AVURLAsset(url: url)
        guard let (metadata, duration) = try? await asset.load(.commonMetadata, .duration) else { return nil }
        var preview = ClipPreview()
        for item in metadata {
            switch item.commonKey {
            case .commonKeyTitle: preview.title = try? await item.load(.stringValue)
            case .commonKeyArtist: preview.artist = try? await item.load(.stringValue)
            default: break
            }
        }
        let seconds = duration.seconds
        if seconds.isFinite, seconds > 0 { preview.duration = seconds }
        return preview
    }

    // MARK: Online previews

    /// The page's title, its icon, and the picture it gives for sharing (`og:image` or the like), as the
    /// system's link previews read them. A page without such a picture keeps its tile of words: Tuck never
    /// renders the page itself to make one.
    private func fetchLinkPreview(_ url: URL, completion: @escaping (ClipPreview?) -> Void) {
        let provider = LPMetadataProvider()
        provider.timeout = 8
        provider.startFetchingMetadata(for: url) { [assets] metadata, _ in
            guard let metadata else { return completion(nil) }
            let title = metadata.title
            // The icon and the picture load at once, each on a queue of its own choosing.
            let loads = DispatchGroup()
            let lock = NSLock()
            var iconFile: String?
            var pageImageFile: String?
            if let icon = metadata.iconProvider, icon.canLoadObject(ofClass: NSImage.self) {
                loads.enter()
                icon.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage, let png = Self.png(image, side: 64) {
                        let name = try? assets.write(png, extension: "png")
                        lock.withLock { iconFile = name }
                    }
                    loads.leave()
                }
            }
            if let picture = metadata.imageProvider, picture.canLoadObject(ofClass: NSImage.self) {
                loads.enter()
                picture.loadObject(ofClass: NSImage.self) { image, _ in
                    if let image = image as? NSImage, let jpeg = Self.jpeg(image, width: Self.pageImageWidth) {
                        let name = try? assets.write(jpeg, extension: "jpg")
                        lock.withLock { pageImageFile = name }
                    }
                    loads.leave()
                }
            }
            loads.notify(queue: .global(qos: .utility)) {
                let files = lock.withLock { (iconFile, pageImageFile) }
                completion(ClipPreview(title: title, iconFile: files.0, pageImageFile: files.1))
            }
        }
    }

    /// A page's picture is kept this many points wide (at 2x): as wide as the largest card.
    static let pageImageWidth: CGFloat = 224

    private func fetchMap(for address: String, completion: @escaping (ClipPreview?) -> Void) {
        CLGeocoder().geocodeAddressString(address) { [assets] placemarks, _ in
            guard let location = placemarks?.first?.location else { return completion(nil) }
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 700, longitudinalMeters: 700)
            options.size = CGSize(width: 340, height: 120)
            options.appearance = NSAppearance(named: .darkAqua)
            options.pointOfInterestFilter = .excludingAll
            MKMapSnapshotter(options: options).start(with: .global(qos: .utility)) { snapshot, _ in
                guard let image = snapshot?.image, let png = Self.png(image, side: nil) else { return completion(nil) }
                completion(ClipPreview(mapFile: try? assets.write(png, extension: "png")))
            }
        }
    }

    /// The image as a JPEG, scaled down to `width` points at 2x: a page's picture is a photograph or a
    /// banner, which a JPEG keeps in a tenth of a PNG's room.
    static func jpeg(_ image: NSImage, width: CGFloat) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(width * 2 / image.size.width, 1)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // A see-through picture is set on white, as a page would show it, since a JPEG has no transparency.
        NSColor.white.setFill()
        CGRect(origin: .zero, size: size).fill()
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    /// The image as a PNG, scaled down to fit a square of `side` points at 2x when one is given.
    static func png(_ image: NSImage, side: CGFloat?) -> Data? {
        var size = image.size
        if let side, size.width > 0, size.height > 0 {
            let scale = min(side * 2 / size.width, side * 2 / size.height, 1)
            size = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        } else {
            size = CGSize(width: size.width * 2, height: size.height * 2)
        }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
