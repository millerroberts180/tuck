import AppKit
import ServiceManagement
import TuckCore

/// Hardware haptics through the system feedback performer. It only produces output on Force Touch
/// trackpads while a finger is resting on them, and respects the person's system settings; every caller
/// also changes something visible.
final class SystemHaptics: HapticFeedbackProviding {
    var isEnabled: Bool
    private var pacing = HapticPacing()

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func perform(_ event: HapticEvent) {
        guard isEnabled, pacing.allows(at: ProcessInfo.processInfo.systemUptime) else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch event {
        case .dropTargetEntered, .placementSnapped: pattern = .alignment
        case .deposited: pattern = .levelChange
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

/// Writes Tuck's copies, each marked as Tuck's (the nspasteboard.org source marker) so clipboard capture
/// knows not to record it again as a new copy from another app.
final class SystemPasteboard: PasteboardWriting {
    /// Where clipboard images and styled text are kept, to put them back.
    var assets: ClipboardAssetStore?

    static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")

    init(assets: ClipboardAssetStore? = nil) {
        self.assets = assets
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markAsTucks(pasteboard)
    }

    func copy(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let payload = entry.payload
        if let urls = payload?.fileURLs, !urls.isEmpty {
            pasteboard.writeObjects(urls as [NSURL])
        } else if let name = payload?.imageFile, let data = assets.flatMap({ try? Data(contentsOf: $0.url(for: name)) }) {
            pasteboard.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        } else {
            switch entry.category {
            case .color:
                if let color = entry.recognition?.color {
                    NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).write(to: pasteboard)
                }
                pasteboard.setString(entry.text, forType: .string)
            case .contact:
                pasteboard.setString(entry.text, forType: NSPasteboard.PasteboardType("public.vcard"))
                pasteboard.setString(entry.text, forType: .string)
            default:
                if let name = payload?.richTextFile, let rtf = assets.flatMap({ try? Data(contentsOf: $0.url(for: name)) }) {
                    pasteboard.setData(rtf, forType: .rtf)
                }
                if entry.category == .link || entry.category == .music, let url = URL(string: entry.text) {
                    pasteboard.setString(url.absoluteString, forType: .URL)
                }
                pasteboard.setString(entry.text, forType: .string)
            }
        }
        markAsTucks(pasteboard)
    }

    private func markAsTucks(_ pasteboard: NSPasteboard) {
        if let bundleID = Bundle.main.bundleIdentifier { pasteboard.setString(bundleID, forType: Self.sourceType) }
    }
}

/// Application icons, resolved once per bundle identifier and drawn to one size (see `normalized`).
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = normalized(NSWorkspace.shared.icon(forFile: url.path), side: 40)
        } else {
            image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
            image.size = NSSize(width: 40, height: 40)
        }
        cache[bundleID] = image
        return image
    }

    /// The app's icon with its art drawn to the same size as every other's. Apps place their art
    /// differently in the icon's canvas: Apple's leave a margin and a soft shadow, and some fill it to the
    /// edge or leave more room. So the art is found (pixels at least half opaque, which leaves the shadow
    /// out) and drawn centred, its longer side at Apple's grid, 824 of 1024. Art that covers less of its
    /// box than a rounded square does (a circle, a page and a pen) is drawn up to 12% larger, by the square
    /// root of the difference, so it looks as big. Measured once, on a 64-pixel drawing of the icon.
    static func normalized(_ icon: NSImage, side: CGFloat) -> NSImage {
        let pixels = 64
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return icon }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.bitmapData else { return icon }
        var minX = pixels, minY = pixels, maxX = -1, maxY = -1, opaque = 0
        for y in 0..<pixels {
            for x in 0..<pixels where data[y * rep.bytesPerRow + x * 4 + 3] >= 128 {
                opaque += 1
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard opaque > 0 else { return icon }
        // The art's box in the icon's own points; the bitmap's rows run from the top.
        let scale = icon.size.width / CGFloat(pixels)
        let width = CGFloat(maxX - minX + 1), height = CGFloat(maxY - minY + 1)
        let art = NSRect(x: CGFloat(minX) * scale, y: CGFloat(pixels - 1 - maxY) * scale,
                         width: width * scale, height: height * scale)
        let coverage = CGFloat(opaque) / (width * height)
        let longest = side * 824 / 1024 * min(1.12, max(1, (0.93 / coverage).squareRoot()))
        let fit = longest / max(art.width, art.height)
        let size = NSSize(width: art.width * fit, height: art.height * fit)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { bounds in
            icon.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                 width: size.width, height: size.height),
                      from: art, operation: .sourceOver, fraction: 1)
            return true
        }
        return image
    }
}

/// Open at login, through the system's own login-item list. Tuck stores nothing: the list is the truth,
/// read back after every change.
enum LoginItem {
    /// Only an app bundle can be a login item; a bare executable (`swift run`) can't.
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static var status: SMAppService.Status { isAvailable ? SMAppService.mainApp.status : .notFound }

    /// Registered, or waiting for the person's approval in System Settings.
    static var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    static func set(_ enabled: Bool) {
        guard isAvailable else { return }
        if enabled { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }
}
