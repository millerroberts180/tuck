import SwiftUI
import TuckCore
import UniformTypeIdentifiers

/// A copy in the clipboard history, as a tile. Click puts it back on the clipboard as it was copied
/// (files, image, styling and all), at once; double-click also pastes it into the app in front; drag
/// forwards it in its own type; the menu holds what that kind is for: call a number, open an address in
/// Maps, copy a colour's hex.
struct ClipboardTile: View {
    @ObservedObject var model: TuckModel
    let entry: ClipboardEntry
    @State private var isHovering = false

    var body: some View {
        let content = TileContent(entry: entry, assets: model.clipboardAssets)
        let feedback = model.feedback(for: entry.id)
        let target = model.pasteTargetName
        let facts = TileMeta.spoken(content, showsTime: model.showsCopyTimes, copied: true)
        let help = ContentHelp.badged(ContentHelp.clipboard(content, pastes: true, into: target), facts)
        let label = ([content.spokenTitle] + facts).joined(separator: ", ")
        Group {
            if content.fileURLs.count > 1 {
                tile(content, feedback)
                    .overlay {
                        MultiFileDragSource(urls: content.fileURLs, onClick: {
                            if NSApp.currentEvent?.clickCount == 2 { model.paste(entry: entry) } else { model.copy(entry: entry) }
                        })
                    }
            } else {
                // The click copies without waiting; a second one, on top of it, pastes.
                tile(content, feedback)
                    .onTapGesture { model.copy(entry: entry) }
                    .simultaneousGesture(TapGesture(count: 2).onEnded { model.paste(entry: entry) })
                    .onDrag { ContentDrag.provider(for: content) }
            }
        }
        .contextMenu { ClipboardMenuItems(model: model, entry: entry, content: content) }
        .task(id: entry.id) { model.lookUpPreviewIfNeeded(entry) }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(feedback?.message ?? "Copied \(Theme.spokenRelative(entry.lastCopiedAt))")
        .accessibilityHint("Copies it again, or " + ContentHelp.pasteHint(into: target))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.copy(entry: entry) }
        .accessibilityAction(named: ContentHelp.pasteAction(into: target)) { model.paste(entry: entry) }
    }

    private func tile(_ content: TileContent, _ feedback: TuckModel.RowFeedback?) -> some View {
        ContentTileView(content: content, feedback: feedback, isHovering: isHovering, showsTime: model.showsCopyTimes)
            .onHover { isHovering = $0 }
    }
}

/// A copy's menu, on its tile and its row alike: Copy, what its kind is for, Keep in Tuck, Share, and
/// taking it out of the history.
struct ClipboardMenuItems: View {
    let model: TuckModel
    let entry: ClipboardEntry
    let content: TileContent

    var body: some View {
        Button("Copy", systemImage: "doc.on.doc") { model.copy(entry: entry) }
        KindActions(content: content, inClipboard: true) { text, label in
            model.copy(part: text, of: entry, label: label)
        }
        Divider()
        Button("Keep in Tuck", systemImage: "tray.and.arrow.down") { model.keep(entry: entry) }
        ContentShare(content: content)
        Divider()
        Button("Remove from History", systemImage: "minus.circle") { model.removeClipboardEntry(entry) }
    }
}

/// A held item, as a tile: the same faces as the clipboard's, with a held item's own actions. Click opens
/// a file or link and copies text; double-click pastes text, or a link's address, into the app in front
/// (Edit is in the menu); a stack drags out all of its files and opens beneath its row on click.
struct HeldTile: View {
    @ObservedObject var model: TuckModel
    let item: HeldItem
    @State private var isHovering = false

    private var isRevealed: Bool { model.revealedStackID == item.id }

    var body: some View {
        let content = TileContent(item: item)
        let feedback = model.feedback(for: item.id)
        let face = ContentTileView(content: content, feedback: feedback, isHovering: isHovering,
                                   isActive: model.editingItemID == item.id || isRevealed, showsTime: model.showsCopyTimes)
            .onHover { isHovering = $0 }
        let target = model.pasteTargetName
        let facts = TileMeta.spoken(content, showsTime: model.showsCopyTimes, copied: false)
        let help = ContentHelp.badged(ContentHelp.held(item, content, pastes: true, into: target), facts)
        let label = ([content.spokenTitle] + facts).joined(separator: ", ")
        Group {
            switch item.kind {
            case .stack:
                face.overlay { MultiFileDragSource(urls: item.fileURLs, onClick: { model.toggleStack(item) }) }
            case .text, .link, .music:
                // What can be pasted waits to see whether a click is a double-click: opening a link at
                // once would take the app in front away before the paste.
                face
                    .onDrag { model.dragProvider(for: item) }
                    .onTapGesture(count: 2) { model.paste(item: item) }
                    .onTapGesture { model.activate(item: item) }
            case .file:
                face
                    .onDrag { model.dragProvider(for: item) }
                    .onTapGesture { model.activate(item: item) }
            }
        }
        .contextMenu { HeldItemMenuItems(model: model, item: item, content: content) }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue(feedback))
        .accessibilityHint(accessibilityHint(pastingInto: target))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { item.kind == .stack ? model.toggleStack(item) : model.activate(item: item) }
        .modifier(PasteAction(isOffered: item.kind.isPastable, target: target) { model.paste(item: item) })
    }

    private func accessibilityValue(_ feedback: TuckModel.RowFeedback?) -> String {
        if let feedback { return feedback.message }
        if item.kind == .stack { return isRevealed ? "Files shown" : "Files hidden" }
        return "Added \(Theme.spokenRelative(item.addedAt))"
    }

    private func accessibilityHint(pastingInto target: String?) -> String {
        switch item.kind {
        case .text: return "Copies the text, or " + ContentHelp.pasteHint(into: target)
        case .stack: return isRevealed ? "Hides the files" : "Shows the files"
        case .link, .music: return "Opens it, or " + ContentHelp.pasteHint(into: target)
        case .file: return "Opens it"
        }
    }
}

/// VoiceOver's Paste, for what a double-click pastes.
private struct PasteAction: ViewModifier {
    let isOffered: Bool
    let target: String?
    let paste: () -> Void

    func body(content: Content) -> some View {
        if isOffered {
            content.accessibilityAction(named: ContentHelp.pasteAction(into: target), paste)
        } else {
            content
        }
    }
}

private extension HeldItemKind {
    /// Text, a link and music paste on a double-click; a file and a stack open.
    var isPastable: Bool { self == .text || self == .link || self == .music }
}

/// A held item's menu, on its tile and its row alike: what a click does, what its kind is for, Share,
/// and taking it out of Tuck.
struct HeldItemMenuItems: View {
    let model: TuckModel
    let item: HeldItem
    let content: TileContent

    private var isRevealed: Bool { model.revealedStackID == item.id }

    var body: some View {
        switch item.kind {
        case .text:
            Button("Copy", systemImage: "doc.on.doc") { model.activate(item: item) }
            Button("Edit", systemImage: "pencil") { model.beginEditing(item) }
            KindActions(content: content, inClipboard: false) { text, label in
                model.copy(text: text, feedbackID: item.id, label: label)
            }
            if let text = item.text {
                Divider()
                ShareLink(item: text) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
        case .stack:
            Button(isRevealed ? "Hide Files" : "Show Files", systemImage: isRevealed ? "chevron.up" : "chevron.down") {
                model.toggleStack(item)
            }
            Button("Show in Finder", systemImage: "folder") { model.activate(item: item) }
            Button("Quick Look", systemImage: "eye") { QuickLookPresenter.shared.show(item.fileURLs) }
            Button("Compress \(item.children?.count ?? 0) Files", systemImage: "doc.zipper") { model.compress(item) }
            Button("Unstack", systemImage: "square.stack.3d.down.right") { model.unstack(item) }
            Divider()
            ShareLink(items: item.fileURLs) { Label("Share…", systemImage: "square.and.arrow.up") }
        case .file:
            Button("Open", systemImage: "arrow.up.forward.app") { model.activate(item: item) }
            if let url = item.url {
                Button("Quick Look", systemImage: "eye") { QuickLookPresenter.shared.show([url]) }
            }
            Button("Show in Finder", systemImage: "folder") { model.revealInFinder(item) }
            Button("Compress", systemImage: "doc.zipper") { model.compress(item) }
            if let url = item.url {
                Divider()
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
        case .link, .music:
            Button("Open", systemImage: "arrow.up.forward.app") { model.activate(item: item) }
            if let url = item.url {
                Button("Copy Link", systemImage: "link") { model.copy(text: url.absoluteString, feedbackID: item.id) }
                Divider()
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
        }
        Divider()
        // A copy Tuck saved (a Mail message, a dropped image) is the only copy: say that it goes.
        if model.isSavedCopy(item) {
            Button("Delete Saved Copy", systemImage: "trash", role: .destructive) { model.remove(item: item) }
        } else {
            Button("Remove from Tuck", systemImage: "minus.circle") { model.remove(item: item) }
        }
    }
}

/// A stack's files, opened full width under the row that holds the stack.
struct StackContents: View {
    @ObservedObject var model: TuckModel
    let stack: HeldItem

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.tileSpacing) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .accessibilityHidden(true)
                Text("In this stack")
                Spacer(minLength: 0)
                Button("Hide") { model.toggleStack(stack) }
                    .buttonStyle(PanelButtonStyle())
            }
            .font(.panelSubtitle)
            .foregroundStyle(Theme.secondaryText)
            .padding(.leading, 4)
            TileGrid(items: stack.children ?? [], tile: { HeldTile(model: model, item: $0) }, detail: { _ in EmptyView() })
        }
        .padding(.vertical, 4)
    }
}

// MARK: - What each kind can do

/// The menu items a kind brings, after Copy: what a number, an address or a colour is for.
struct KindActions: View {
    let content: TileContent
    let inClipboard: Bool
    let copyPart: (String, String) -> Void

    var body: some View {
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch content.category {
        case .link, .music:
            if inClipboard, let url = content.linkURL {
                Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
            }
        case .email:
            let address = TileText.emailAddress(text)
            if let url = URL(string: "mailto:" + address) {
                Button("New Message", systemImage: "envelope") { NSWorkspace.shared.open(url) }
            }
        case .phone:
            let digits = text.filter { $0.isNumber || $0 == "+" }
            if let call = URL(string: "tel:" + digits) {
                Button("Call", systemImage: "phone") { NSWorkspace.shared.open(call) }
            }
            if let message = URL(string: "sms:" + digits) {
                Button("Send Message", systemImage: "message") { NSWorkspace.shared.open(message) }
            }
        case .color:
            if let color = content.recognition.color {
                Button("Copy Hex", systemImage: "number") { copyPart(color.hex, "hex") }
                Button("Copy RGB", systemImage: "paintpalette") { copyPart(color.rgb, "RGB") }
            }
        case .contact:
            if let name = content.recognition.name { Button("Copy Name", systemImage: "person") { copyPart(name, "name") } }
            if let phone = VCard.values("TEL", in: content.text).first {
                Button("Copy Number", systemImage: "phone") { copyPart(phone, "number") }
            }
            if let email = VCard.values("EMAIL", in: content.text).first {
                Button("Copy Email", systemImage: "envelope") { copyPart(email, "email") }
            }
            Button("Add to Contacts…", systemImage: "person.crop.circle.badge.plus") {
                ContentActions.addToContacts(content.text, name: content.recognition.name)
            }
        case .address:
            Button("Open in Maps", systemImage: "map") { ContentActions.openInMaps(text, directions: false) }
            Button("Get Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                ContentActions.openInMaps(text, directions: true)
            }
        case .date:
            if let date = content.recognition.date {
                Button("Add to Calendar…", systemImage: "calendar.badge.plus") {
                    ContentActions.addToCalendar(date, allDay: content.recognition.includesTime != true,
                                                 title: TileText.excerpt(content.text, limit: 80))
                }
            }
        case .path:
            let url = TileText.pathURL(text)
            if FileManager.default.fileExists(atPath: url.path) {
                Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }
                Button("Quick Look", systemImage: "eye") { QuickLookPresenter.shared.show([url]) }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        case .richText:
            Button("Copy as Plain Text", systemImage: "text.alignleft") { copyPart(content.text, "plain text") }
        case .image, .screenshot:
            if let url = content.imageURL {
                Button("Quick Look", systemImage: "eye") { QuickLookPresenter.shared.show([url]) }
            }
            if let words = content.preview?.recognizedText {
                Button("Copy Text in Image", systemImage: "text.viewfinder") { copyPart(words, "text") }
            }
            if inClipboard, content.payload?.imageFile != nil, let url = content.imageURL {
                Button("Save to Downloads", systemImage: "arrow.down.circle") {
                    ContentActions.saveToDownloads(url, kind: content.category)
                }
            }
            if !content.fileURLs.isEmpty { fileActions }
        case .file, .folder, .stack, .audio, .video:
            if inClipboard { fileActions }
        case .text, .code, .emoji, .secret, .window:
            EmptyView()
        }
    }

    @ViewBuilder private var fileActions: some View {
        let urls = content.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty {
            if urls.count == 1 {
                Button("Open", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(urls[0]) }
            }
            Button("Quick Look", systemImage: "eye") { QuickLookPresenter.shared.show(urls) }
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
    }
}

/// Share, with what the kind shares as: its files, its link or its text. A key is never offered.
struct ContentShare: View {
    let content: TileContent

    var body: some View {
        if content.category == .secret {
            EmptyView()
        } else if !content.fileURLs.isEmpty {
            ShareLink(items: content.fileURLs) { Label("Share…", systemImage: "square.and.arrow.up") }
        } else if let url = content.imageURL {
            ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
        } else if let url = content.linkURL {
            ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
        } else {
            ShareLink(item: content.text) { Label("Share…", systemImage: "square.and.arrow.up") }
        }
    }
}

enum ContentHelp {
    /// A tile's help with what its badges say on a line above: "PDF · 2.4 MB".
    static func badged(_ help: String, _ facts: [String]) -> String {
        guard !facts.isEmpty else { return help }
        let line = facts.joined(separator: " · ")
        return line.prefix(1).uppercased() + line.dropFirst() + "\n" + help
    }

    /// A tile's help, carried on after what a row says first ("Added 2 minutes ago · click to open").
    static func continuing(_ help: String) -> String {
        help.prefix(1).lowercased() + help.dropFirst()
    }

    /// What a double-click does, named for the app it pastes into when that is known.
    static func doubleClick(pastingInto target: String?) -> String {
        target.map { "double-click to paste into \($0)" } ?? "double-click to paste"
    }

    /// VoiceOver's name for the same: "Paste into TextEdit".
    static func pasteAction(into target: String?) -> String {
        target.map { "Paste into \($0)" } ?? "Paste"
    }

    /// The hint's second half, after what the default action does. VoiceOver has no double-click, so it
    /// points to the action instead.
    static func pasteHint(into target: String?) -> String {
        (target.map { "pastes it into \($0)" } ?? "pastes it") + " from the actions"
    }

    /// A copy's help. Rows, which don't paste, leave the double-click out.
    static func clipboard(_ content: TileContent, pastes: Bool = false, into target: String? = nil) -> String {
        let paste = pastes ? " · " + doubleClick(pastingInto: target) : ""
        switch content.category {
        case .secret: return "Click to copy the key\(paste) · it stays hidden here · drag to forward"
        case .image, .screenshot: return "Click to copy the image\(paste) · drag to forward it as a file"
        case .file, .folder, .stack, .audio, .video: return "Click to copy the files again\(paste) · drag to forward the originals"
        case .color: return "Click to copy the colour\(paste) · right-click for hex or RGB"
        default: return "Click to copy again\(paste) · drag to forward · right-click for more"
        }
    }

    /// A held item's help. Rows, which don't paste, keep the double-click that edits text.
    static func held(_ item: HeldItem, _ content: TileContent, pastes: Bool = false, into target: String? = nil) -> String {
        let paste = pastes ? " · " + doubleClick(pastingInto: target) : nil
        switch item.kind {
        case .text: return "Click to copy" + (paste ?? " · double-click to edit") + " · drag to forward"
        case .music: return "Click to open in your music app" + (paste ?? "") + " · drag to forward the link"
        case .link: return "Click to open" + (paste ?? "") + " · drag to forward the link"
        case .file:
            let folder = item.subtitle.isEmpty ? "" : " · in \(item.subtitle)"
            return "Click to open · drag to forward the original file\(folder)"
        case .stack: return "Click to show the files · drag to forward all of them"
        }
    }
}

/// What a drag out of a clipboard tile carries: the files, the image file, the link, the contact card, or
/// the text, so it lands in the next app as what it was.
enum ContentDrag {
    static func provider(for content: TileContent) -> NSItemProvider {
        if let url = content.fileURLs.first {
            return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        }
        if let url = content.imageURL {
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            provider.suggestedName = content.category == .screenshot ? "Screenshot" : "Image"
            return provider
        }
        if let url = content.linkURL {
            let provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = content.title
            return provider
        }
        if content.category == .contact {
            let provider = NSItemProvider(object: content.text as NSString)
            let card = Data(content.text.utf8)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.vCard.identifier, visibility: .all) { done in
                done(card, nil)
                return nil
            }
            provider.suggestedName = content.recognition.name
            return provider
        }
        return NSItemProvider(object: content.text as NSString)
    }
}

/// The hand-offs to other apps: a card to Contacts, a date to Calendar, an address to Maps. Each writes
/// a small file into the temporary folder and lets the system open it, so Tuck asks for no access to
/// contacts or calendars.
enum ContentActions {
    static func addToContacts(_ card: String, name: String?) {
        open(Data(card.utf8), named: (name ?? "Contact") + ".vcf")
    }

    static func addToCalendar(_ date: Date, allDay: Bool, title: String) {
        let stamp = compact(Date(), time: true)
        let start: String
        let end: String
        if allDay {
            let day = Calendar.current.startOfDay(for: date)
            start = "DTSTART;VALUE=DATE:" + compact(day, time: false)
            end = "DTEND;VALUE=DATE:" + compact(day.addingTimeInterval(86_400), time: false)
        } else {
            start = "DTSTART:" + compact(date, time: true)
            end = "DTEND:" + compact(date.addingTimeInterval(3600), time: true)
        }
        let summary = title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
        let lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Tuck//EN", "BEGIN:VEVENT",
                     "UID:\(UUID().uuidString)@tuck", "DTSTAMP:\(stamp)", start, end, "SUMMARY:\(summary)",
                     "END:VEVENT", "END:VCALENDAR"]
        open(Data(lines.joined(separator: "\r\n").utf8), named: "Event.ics")
    }

    /// "20261108T093000Z" in UTC, or "20261108" for a day.
    private static func compact(_ date: Date, time: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if time {
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else {
            formatter.dateFormat = "yyyyMMdd"
        }
        return formatter.string(from: date)
    }

    static func openInMaps(_ address: String, directions: Bool) {
        var parts = URLComponents(string: "maps://")!
        parts.queryItems = [URLQueryItem(name: directions ? "daddr" : "q", value: address)]
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }

    /// Saves a copied image beside the person's downloads, named for when it was saved, and shows it.
    static func saveToDownloads(_ url: URL, kind: ContentCategory) {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let when = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " at "
            + Date().formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
        let stem = (kind == .screenshot ? "Screenshot " : "Copied image ") + when.replacingOccurrences(of: ":", with: ".")
            .replacingOccurrences(of: "/", with: "-")
        var target = downloads.appendingPathComponent(stem).appendingPathExtension(url.pathExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = downloads.appendingPathComponent("\(stem) \(suffix)").appendingPathExtension(url.pathExtension)
            suffix += 1
        }
        guard (try? FileManager.default.copyItem(at: url, to: target)) != nil else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private static func open(_ data: Data, named name: String) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Tuck-\(UUID().uuidString)")
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent(safe)
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              (try? data.write(to: url)) != nil else { return }
        NSWorkspace.shared.open(url)
    }
}
