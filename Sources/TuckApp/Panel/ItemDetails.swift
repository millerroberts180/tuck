import QuickLookThumbnailing
import SwiftUI
import TuckCore

/// What the system knows about held files and links: icons, Quick Look thumbnails, saved pictures and
/// styled text. Asked only while the panel draws a tile and remembered, failures included, so a redraw
/// never touches the disk; everything is let go when the panel closes, so the next open reads afresh.
@MainActor
enum ItemDetails {
    private static let icons = NSCache<NSString, NSImage>()
    private static let thumbnails = NSCache<NSString, NSImage>()
    private static let pictures = NSCache<NSString, NSImage>()
    private static var excerpts: [URL: AttributedString?] = [:]
    private static var appIcons: [String: NSImage?] = [:]
    private static var appURLs: [String: URL?] = [:]
    private static var paths: [String: PathStatus] = [:]

    static func purge() {
        icons.removeAllObjects()
        thumbnails.removeAllObjects()
        pictures.removeAllObjects()
        excerpts.removeAll()
        appIcons.removeAll()
        appURLs.removeAll()
        paths.removeAll()
        ContentKinds.purge()
        FileSizes.purge()
        TextCounts.purge()
    }

    /// The icon of the app something came from: found by its bundle identifier, or for a held item, which
    /// records only a name, among the apps running now. Nil for Tuck itself and for an app that isn't on
    /// this Mac.
    static func appIcon(bundleID: String?, name: String?) -> NSImage? {
        guard let key = bundleID ?? name.map({ "name:" + $0 }) else { return nil }
        if let known = appIcons[key] { return known }
        var icon: NSImage?
        if bundleID != Bundle.main.bundleIdentifier, name != "Tuck", let url = appURL(bundleID: bundleID, name: name) {
            icon = AppIcons.normalized(NSWorkspace.shared.icon(forFile: url.path), side: 32)
        }
        appIcons[key] = icon
        return icon
    }

    private static func appURL(bundleID: String?, name: String?) -> URL? {
        guard let key = bundleID ?? name.map({ "name:" + $0 }) else { return nil }
        if let known = appURLs[key] { return known }
        let url = bundleID.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))
            ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.bundleURL
        appURLs[key] = url
        return url
    }

    /// The apps the history and held items came from, for search to read their names, with each one's
    /// bundle name too when it differs from the name it gave ("Visual Studio Code" for "Code"). Worked
    /// out once as a search begins.
    nonisolated static func sourceApps(copied: [ClipboardEntry], items: [HeldItem]) -> [SourceApp] {
        SourceApp.known(copied: copied, items: items, excludingBundleID: Bundle.main.bundleIdentifier).map { app in
            var app = app
            if let bundle = app.bundleID.flatMap(NSWorkspace.shared.urlForApplication(withBundleIdentifier:))?
                .deletingPathExtension().lastPathComponent, bundle.caseInsensitiveCompare(app.name) != .orderedSame {
                app.aliases.append(bundle)
            }
            return app
        }
    }

    /// Whether a copied path is there, and a folder.
    struct PathStatus {
        let exists: Bool
        let isDirectory: Bool
    }

    /// Asks the disk once per path while the panel is open.
    static func status(ofPath url: URL) -> PathStatus {
        if let known = paths[url.path] { return known }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let status = PathStatus(exists: exists, isDirectory: exists && isDirectory.boolValue)
        paths[url.path] = status
        return status
    }

    static func icon(for url: URL) -> NSImage {
        if let cached = icons.object(forKey: url.path as NSString) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(image, forKey: url.path as NSString)
        return image
    }

    static func thumbnail(for url: URL, side: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = "\(Int(side))@\(url.path)" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                   representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let image = representation.nsImage
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// A small picture Tuck saved itself (a page's icon, a map), read whole.
    static func image(at url: URL) -> NSImage? {
        if let cached = pictures.object(forKey: url.path as NSString) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        pictures.setObject(image, forKey: url.path as NSString)
        return image
    }

    /// Copied styled text as a tile shows it: the bold, italics, underlines and links kept, but in the card's
    /// own face, size and colours, so a styled copy reads as one without a page of fonts.
    static func richExcerpt(at url: URL) -> AttributedString? {
        if let cached = excerpts[url] { return cached }
        var excerpt: AttributedString?
        if let data = try? Data(contentsOf: url), let text = NSAttributedString(rtf: data, documentAttributes: nil) {
            var shown = AttributedString()
            text.enumerateAttributes(in: NSRange(location: 0, length: min(text.length, 400))) { attributes, range, _ in
                let piece = (text.string as NSString).substring(with: range)
                    .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
                var run = AttributedString(piece)
                // Emphasis rather than a font, so the face's own font sets the size and the bold follows it.
                let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
                var emphasis: InlinePresentationIntent = []
                if traits.contains(.bold) { emphasis.insert(.stronglyEmphasized) }
                if traits.contains(.italic) { emphasis.insert(.emphasized) }
                if !emphasis.isEmpty { run.inlinePresentationIntent = emphasis }
                if attributes[.link] != nil || (attributes[.underlineStyle] as? Int ?? 0) != 0 {
                    run.swiftUI.underlineStyle = .single
                }
                if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 {
                    run.swiftUI.strikethroughStyle = .single
                }
                shown += run
            }
            excerpt = shown
        }
        excerpts[url] = excerpt
        return excerpt
    }
}

/// How big files are and how much a folder holds, for a tile's badges and for size words in a search.
/// Each file's size is read once (a tile reads it off the main thread; a search that names a size before
/// the tile has, at once) and a folder is counted off the main thread, once. All of it is remembered,
/// failures included, until the panel closes, with `ItemDetails`.
enum FileSizes {
    private static var sizes: [URL: Int?] = [:]
    private static var counts: [URL: Int?] = [:]

    static func purge() {
        sizes.removeAll()
        counts.removeAll()
    }

    /// A file's size, nil for a folder or a file that has gone. Read now if it hasn't been.
    static func byteCount(of url: URL) -> Int? {
        if let known = sizes[url] { return known }
        let size = read(url)
        sizes[url] = size
        return size
    }

    /// A held item's size: a file's, or a stack's files together. What search measures "large" by.
    static func byteCount(of item: HeldItem) -> Int? {
        let known = item.fileURLs.compactMap(byteCount(of:))
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    /// A file's size if it has been read: nil when it hasn't, nil inside when it can't be.
    static func knownByteCount(of url: URL) -> Int?? { sizes[url] }

    /// A file's size, read off the main thread when it hasn't been.
    @MainActor static func loadByteCount(of url: URL) async -> Int? {
        if let known = sizes[url] { return known }
        let size = await Task.detached(priority: .utility) { read(url) }.value
        sizes[url] = size
        return size
    }

    /// How many things a folder shows in Finder, if it has been counted.
    static func knownItemCount(inFolder url: URL) -> Int?? { counts[url] }

    /// How many things a folder shows in Finder (hidden files aside), counted off the main thread once.
    @MainActor static func itemCount(inFolder url: URL) async -> Int? {
        if let known = counts[url] { return known }
        let count = await Task.detached(priority: .utility) {
            (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles]))?.count
        }.value
        counts[url] = count
        return count
    }

    private static func read(_ url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
              values.isDirectory != true else { return nil }
        return values.fileSize
    }
}

/// How long texts are, for their badges: a text's words, code's lines. A short text is counted at once
/// (it takes microseconds); a long one off the main thread. Remembered until the panel closes, with
/// `ItemDetails`, by the copy or held item and the text's length, so an edited text is counted again.
enum TextCounts {
    struct Key: Hashable {
        let id: UUID
        let length: Int
        let lines: Bool
    }

    private static var counts: [Key: Int] = [:]
    /// Under this many bytes, counting is quicker than handing it to another thread.
    private static let quick = 2_000

    static func purge() {
        counts.removeAll()
    }

    static func key(_ id: UUID, _ text: String, lines: Bool) -> Key { Key(id: id, length: text.utf8.count, lines: lines) }

    /// The count if it has been made, or made now for a short text.
    static func known(_ id: UUID, _ text: String, lines: Bool) -> Int? {
        let key = key(id, text, lines: lines)
        if let known = counts[key] { return known }
        guard key.length < quick else { return nil }
        let count = lines ? BadgeText.lineCount(text) : BadgeText.wordCount(text)
        counts[key] = count
        return count
    }

    @MainActor static func count(_ id: UUID, _ text: String, lines: Bool) async -> Int {
        if let known = known(id, text, lines: lines) { return known }
        let count = await Task.detached(priority: .utility) {
            lines ? BadgeText.lineCount(text) : BadgeText.wordCount(text)
        }.value
        counts[key(id, text, lines: lines)] = count
        return count
    }
}

/// A hairline around a Quick Look thumbnail, so a white page (a plain-text file's, say) keeps its edge
/// on a light card, most of all with Increase Contrast. Icons draw their own edges and get none.
struct ThumbnailEdge: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content.overlay(Rectangle().strokeBorder(Theme.hairline, lineWidth: 1 / displayScale))
    }
}

/// Drags several files out at once, which SwiftUI's single-provider `onDrag` cannot do. A click (no
/// movement) is passed to `onClick`; a right-click falls through to the row's context menu.
struct MultiFileDragSource: NSViewRepresentable {
    let urls: [URL]
    let onClick: () -> Void

    func makeNSView(context: Context) -> SourceView {
        SourceView()
    }

    func updateNSView(_ view: SourceView, context: Context) {
        view.urls = urls
        view.onClick = onClick
    }

    final class SourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var onClick: (() -> Void)?
        private var downPoint: CGPoint?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            downPoint = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = downPoint else { return }
            let point = event.locationInWindow
            guard hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            downPoint = nil
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else { return }
            let origin = convert(event.locationInWindow, from: nil)
            let items = existing.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let offset = CGFloat(min(index, 4)) * 4
                item.setDraggingFrame(CGRect(x: origin.x - 16 + offset, y: origin.y - 16 - offset, width: 32, height: 32),
                                      contents: icon)
                return item
            }
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.draggingFormation = .pile
        }

        override func mouseUp(with event: NSEvent) {
            if downPoint != nil { onClick?() }
            downPoint = nil
        }

        override func rightMouseDown(with event: NSEvent) {
            // Let the hosting view underneath show the SwiftUI context menu.
            nextResponder?.rightMouseDown(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            superview?.menu(for: event)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            // Copy or link only: a "generic" drop lets Finder move the files, and the originals must
            // never leave where the person keeps them.
            context == .outsideApplication ? [.copy, .link] : []
        }
    }
}

/// Editing a held text in its row, after a double-click: the field and its two choices, nothing else.
struct InlineTextEditor: View {
    @ObservedObject var model: TuckModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Text", text: $model.editingText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.panelWords)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2...6)
                .focused($focused)
                .onSubmit(model.commitEdit)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Theme.hairline, lineWidth: focused ? 1.5 : 1))
            HStack(spacing: 6) {
                Button("Cancel", action: model.cancelEdit)
                    .buttonStyle(PanelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: model.commitEdit)
                    .buttonStyle(PanelButtonStyle(role: .prominent))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .onAppear { focused = true }
        .transition(.opacity)
    }
}
