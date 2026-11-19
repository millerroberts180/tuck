import SwiftUI
import TuckCore

/// What a tile or a row shows, gathered once from a clipboard entry or a held item, so copies and held
/// items of a kind look alike.
struct TileContent {
    let id: UUID
    let category: ContentCategory
    let text: String
    let recognition: ContentRecognition
    var fileURLs: [URL] = []
    /// The picture drawn edge to edge: a copied image, or an image or video file.
    var imageURL: URL?
    var linkURL: URL?
    var title: String?
    var preview: ClipPreview?
    var payload: ClipPayload?
    var sourceAppName: String?
    /// Held items record only the app's name.
    var sourceBundleID: String?
    let date: Date
    var children: [HeldItem] = []
    var iconURL: URL?
    var mapURL: URL?
    /// The picture a link's page gives for sharing, once its page has been looked up.
    var pageImageURL: URL?
    var richTextURL: URL?

    init(entry: ClipboardEntry, assets: ClipboardAssetStore?) {
        id = entry.id
        category = entry.category
        text = entry.text
        recognition = entry.recognition ?? .text
        fileURLs = entry.payload?.fileURLs ?? []
        preview = entry.preview
        payload = entry.payload
        sourceAppName = entry.sourceAppName
        sourceBundleID = entry.sourceBundleID
        date = entry.lastCopiedAt
        if let name = entry.payload?.imageFile { imageURL = assets?.url(for: name) }
        if let name = entry.payload?.richTextFile { richTextURL = assets?.url(for: name) }
        if let name = entry.preview?.iconFile { iconURL = assets?.url(for: name) }
        if let name = entry.preview?.mapFile { mapURL = assets?.url(for: name) }
        if let name = entry.preview?.pageImageFile { pageImageURL = assets?.url(for: name) }
        if imageURL == nil, [.image, .screenshot, .video].contains(category) { imageURL = fileURLs.first }
        if category == .link || category == .music { linkURL = ContentKinds.webURL(entry.text) }
        title = entry.preview?.title
    }

    init(item: HeldItem) {
        id = item.id
        date = item.addedAt
        sourceAppName = item.sourceAppName
        switch item.kind {
        case .file:
            let url = item.url
            category = url.map(ContentKinds.category(forFile:)) ?? .file
            recognition = ContentRecognition(category: category)
            text = item.title
            fileURLs = url.map { [$0] } ?? []
            if [.image, .screenshot, .video].contains(category) { imageURL = url }
        case .stack:
            category = .stack
            recognition = ContentRecognition(category: .stack)
            text = item.title
            fileURLs = item.fileURLs
            children = item.children ?? []
        case .link, .music:
            category = item.kind == .music ? .music : .link
            recognition = ContentRecognition(category: category, name: HeldItemClassifier.musicProvider(for: item.url))
            text = item.url?.absoluteString ?? item.title
            linkURL = item.url
            title = item.title == text || item.title == item.url?.host ? nil : item.title
        case .text:
            let value = item.text ?? ""
            recognition = ContentKinds.recognition(of: value)
            category = recognition.category
            text = value
        }
    }

    /// What VoiceOver reads first: the kind, then what it holds.
    var spokenTitle: String {
        switch category {
        case .secret: return "\(recognition.name ?? "Key"), hidden"
        case .image, .screenshot:
            return [category.title, ContentKinds.dimensions(payload)].compactMap { $0 }.joined(separator: ", ")
        case .color: return "Color \(recognition.color?.hex ?? text)"
        case .contact: return "Contact \(recognition.name ?? "")"
        default:
            let what = title ?? (fileURLs.count == 1 ? fileURLs[0].lastPathComponent : text)
            return "\(category.title), \(what.prefix(120))"
        }
    }
}

/// Kinds worked out for held items, and the small lookups tiles share. Held text is recognised once per
/// text and remembered; a file's kind comes from its name.
enum ContentKinds {
    private static var recognitions: [String: ContentRecognition] = [:]
    private static var directories: [URL: Bool] = [:]

    static func recognition(of text: String) -> ContentRecognition {
        if let known = recognitions[text] { return known }
        if recognitions.count > 400 { recognitions.removeAll() }
        let recognition = ContentClassifier.recognize(text: text)
        recognitions[text] = recognition
        return recognition
    }

    static func category(forFile url: URL) -> ContentCategory {
        let isDirectory: Bool
        if let known = directories[url] {
            isDirectory = known
        } else {
            isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            directories[url] = isDirectory
        }
        return ContentClassifier.category(forFile: url, isDirectory: isDirectory)
    }

    static func webURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed.lowercased().hasPrefix("www.") ? "https://" + trimmed : trimmed)
    }

    /// "1280 × 800".
    static func dimensions(_ payload: ClipPayload?) -> String? {
        guard let width = payload?.pixelWidth, let height = payload?.pixelHeight else { return nil }
        return "\(width) × \(height)"
    }

    /// What a held item is, as its tile shows it: a file's kind asks the disk once whether it is a folder,
    /// and a text's is recognised once.
    static func category(of item: HeldItem) -> ContentCategory {
        TileContent(item: item).category
    }

    static func purge() {
        directories.removeAll()
    }
}

extension Theme {
    /// The gap between tiles, across a row and between rows. Their ground is `tileFill`.
    static let tileSpacing = FoldLayout.cardSpacing
    static let tileRadius: CGFloat = 10
    /// From a card's edge to its words, on every side but its foot, where the line of details sits a
    /// point lower so a row's lines share one baseline under a preview or not.
    static let tilePadding: CGFloat = 10
    static let tileFootPadding: CGFloat = 9
    /// The icon, avatar, flag or calendar page beside a card's title.
    static let tileLead: CGFloat = 30
    /// What a preview leaves for the label under it: a title, the line of details and the padding round them.
    static let tileLabelHeight: CGFloat = 6 + 16 + 1 + TileMeta.height + tileFootPadding
    /// The room under a scrolling list's last row, so it scrolls whole into view above the toolbar's line.
    static let listFoot: CGFloat = 8
}

extension Font {
    /// A card's title: the body size, semibold, so it leads the quieter line under it.
    static let tileTitle = Font.system(.body).weight(.semibold)
}

/// The fold's tiles: how many to a row and how big, as Settings › Notch sets them and the display allows,
/// and how far the first sits from the fold's edge. The fold hands them to everything inside it; anything
/// drawn outside a fold has three medium tiles.
struct TileMetrics: Hashable {
    static let standard = TileMetrics(.standard)

    let columns: Int
    let width: CGFloat
    let height: CGFloat
    /// From the fold's edge to its first tile.
    let sideInset: CGFloat

    init(_ fold: FoldLayout) {
        columns = fold.columns
        width = fold.cardSize.width
        height = fold.cardSize.height
        sideInset = fold.sideInset
    }

    /// One row of tiles, the gaps between them included.
    var rowWidth: CGFloat { CGFloat(columns) * width + CGFloat(columns - 1) * Theme.tileSpacing }

    /// The picture, map or colour at the top of a card that shows one, the card's full width.
    var previewHeight: CGFloat { max(height - Theme.tileLabelHeight, 24) }
}

private struct TileMetricsKey: EnvironmentKey {
    static let defaultValue = TileMetrics.standard
}

private struct TileFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var tileMetrics: TileMetrics {
        get { self[TileMetricsKey.self] }
        set { self[TileMetricsKey.self] = newValue }
    }

    /// The tile the keyboard is on (`TuckModel.tileCursor`): it wears the focus ring and shows its
    /// second details, as under the pointer.
    var isTileFocused: Bool {
        get { self[TileFocusKey.self] }
        set { self[TileFocusKey.self] = newValue }
    }
}

/// How a grid of the stream begins: with the shallow fold's strip, which scrolls sideways through all of
/// it, or with that same strip back at its start as the first of the full fold's rows, the rest under it.
enum TileStripRole {
    case scrolls
    case leads
}

/// Tiles in rows of `TileMetrics.columns`. A row can open a full-width section under it (a text being
/// edited, a stack's files, an app's window titles), so the grid is laid out by hand rather than with a
/// grid that can't span its columns. The stream's grid begins with its strip (`strip`), one view at both
/// depths, so deepening the fold keeps the first row where it is and adds the rest under it; it then
/// spans the fold and sets its own rows in from the edge. The tile the keyboard is on (`cursor`) wears
/// the focus ring, and the list scrolls just enough to show it.
struct TileGrid<Item: Identifiable, Tile: View, Detail: View>: View {
    let items: [Item]
    /// What has its detail open: text being edited, a stack's files, an app's windows. Each opens full
    /// width under its row, in the row's order.
    var openIDs: Set<Item.ID> = []
    var strip: TileStripRole?
    var cursor: Item.ID?
    @ViewBuilder let tile: (Item) -> Tile
    @ViewBuilder let detail: (Item) -> Detail
    @Environment(\.tileMetrics) private var metrics

    private struct Row: Identifiable {
        let items: [Item]
        var id: Item.ID { items[0].id }
    }

    private func rows(of items: some Collection<Item>) -> [Row] {
        let items = Array(items)
        let columns = metrics.columns
        return stride(from: 0, to: items.count, by: columns).map {
            Row(items: Array(items[$0..<min($0 + columns, items.count)]))
        }
    }

    /// What the page scrolls to when a detail opens, and to show the row the keyboard is on.
    private struct DetailAnchor: Hashable {
        let id: Item.ID
    }

    private struct RowAnchor: Hashable {
        let id: Item.ID
    }

    /// The list's foot under the last row, which the keyboard scrolls to on that row.
    private struct EndAnchor: Hashable {}

    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(alignment: .leading, spacing: Theme.tileSpacing) {
                if let strip {
                    TileStrip(items: items, scrolls: strip == .scrolls, cursor: cursor, tile: focusedTile)
                        .id(items.first.map { RowAnchor(id: $0.id) })
                    // Under the strip, what any of it has open while it scrolls; under the full fold's first
                    // row, what that row has open.
                    details(of: strip == .scrolls ? items : Array(items.prefix(metrics.columns)))
                        .padding(.horizontal, metrics.sideInset)
                    if strip == .leads {
                        grid(rows(of: items.dropFirst(metrics.columns)))
                            .padding(.horizontal, metrics.sideInset)
                    }
                } else {
                    grid(rows(of: items))
                }
            }
            // The anchor takes the list's foot under the stack, and the stack hands that room back to it.
            .padding(.bottom, Theme.listFoot)
            .overlay(alignment: .bottom) { Color.clear.frame(height: Theme.listFoot).id(EndAnchor()) }
            .padding(.bottom, -Theme.listFoot)
            // A detail opening under the last rows would open out of sight, so the page scrolls just
            // enough to show the one that just opened, once it is in.
            .onChange(of: openIDs) { old, new in reveal(items.first { new.contains($0.id) && !old.contains($0.id) }?.id, with: proxy) }
            .onAppear { reveal(items.first { openIDs.contains($0.id) }?.id, with: proxy) }
            .onChange(of: cursor) { _, cursor in show(cursor, with: proxy) }
        }
    }

    private func focusedTile(_ item: Item) -> some View {
        tile(item).environment(\.isTileFocused, cursor == item.id)
    }

    private func grid(_ rows: [Row]) -> some View {
        ForEach(rows) { row in
            HStack(spacing: Theme.tileSpacing) {
                ForEach(row.items) { focusedTile($0) }
            }
            .id(RowAnchor(id: row.id))
            details(of: row.items)
        }
    }

    private func details(of items: [Item]) -> some View {
        ForEach(items.filter { openIDs.contains($0.id) }) { open in
            detail(open)
                .id(DetailAnchor(id: open.id))
                .transition(Theme.reveal(edge: .top))
        }
    }

    private func reveal(_ id: Item.ID?, with proxy: ScrollViewProxy) {
        guard let id else { return }
        DispatchQueue.main.async {
            withAnimation(Theme.reduceMotion ? nil : Theme.quick) { proxy.scrollTo(DetailAnchor(id: id)) }
        }
    }

    /// Scrolls the least that shows the row the keyboard moved to. The last row, with nothing open under
    /// it, goes up to the list's foot, so it keeps the room above the toolbar's line that a hand scroll to
    /// the end leaves. In the shallow fold the strip scrolls sideways to it instead (`TileStrip`).
    private func show(_ id: Item.ID?, with proxy: ScrollViewProxy) {
        guard strip != .scrolls, let id, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let columns = metrics.columns
        let start = index - index % columns
        let isLast = start == (items.count - 1) - (items.count - 1) % columns
            && !items[start...].contains { openIDs.contains($0.id) }
        withAnimation(Theme.reduceMotion ? nil : Theme.quick) {
            if isLast { proxy.scrollTo(EndAnchor()) } else { proxy.scrollTo(RowAnchor(id: items[start].id)) }
        }
    }
}

/// The shallow fold's one row: all of the stream, the newest at the left, `TileMetrics.columns` at a time,
/// scrolled sideways with two fingers or a mouse's sideways wheel, or with the arrow keys, and made only as
/// it comes into view. While there is more beyond an end, that edge fades out, which is all that says it
/// scrolls. In the full fold it goes back to its start and leads the rows, cut after its first row.
private struct TileStrip<Item: Identifiable, Tile: View>: View {
    let items: [Item]
    let scrolls: Bool
    var cursor: Item.ID?
    @ViewBuilder let tile: (Item) -> Tile
    @Environment(\.tileMetrics) private var metrics
    @State private var edges = StripEdges()

    private struct TileAnchor: Hashable {
        let id: Item.ID
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: Theme.tileSpacing) {
                    ForEach(items) { tile($0).id(TileAnchor(id: $0.id)) }
                }
                .padding(.horizontal, FoldLayout.edgeInset)
                .id(StripEdges.start)
                .onGeometryChange(for: StripEdges.self) { proxy in
                    let frame = proxy.frame(in: .named(StripEdges.space))
                    let viewport = proxy.bounds(of: .named(StripEdges.space))?.width ?? frame.width
                    return StripEdges(moreBefore: frame.minX < -0.5, moreAfter: frame.maxX > viewport + 0.5)
                } action: { edges = $0 }
            }
            // `.never`, not `.hidden`: with a mouse attached `.hidden` still shows a scroll bar, and the bar
            // takes its height from the cards. The edge fades say there's more.
            .scrollIndicators(.never)
            .scrollDisabled(!scrolls)
            .coordinateSpace(.named(StripEdges.space))
            .frame(width: metrics.rowWidth + FoldLayout.edgeInset * 2, height: metrics.height)
            .mask { mask }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: StripFrameKey.self,
                                       value: scrolls && items.count > metrics.columns ? geometry.frame(in: .named(Theme.panelSpace)) : nil)
            })
            // A fold the notch keeps wider than its row shows only the row, so it holds as many as were chosen.
            .padding(.horizontal, metrics.sideInset - FoldLayout.edgeInset)
            // Deepening, it goes back to its start with the fold, so the first row is the full fold's.
            .onChange(of: scrolls) { _, scrolls in
                guard !scrolls else { return }
                withAnimation(Theme.reduceMotion ? nil : Theme.fold) { proxy.scrollTo(StripEdges.start, anchor: .leading) }
            }
            // Something new arrives at the left, so the strip shows it.
            .onChange(of: items.first?.id) {
                withAnimation(Theme.reduceMotion ? nil : Theme.quick) { proxy.scrollTo(StripEdges.start, anchor: .leading) }
            }
            // The keyboard moved along the strip: it scrolls that tile to the middle, clear of the faded ends.
            .onChange(of: cursor) { _, cursor in
                guard scrolls, let cursor else { return }
                withAnimation(Theme.reduceMotion ? nil : Theme.quick) { proxy.scrollTo(TileAnchor(id: cursor), anchor: .center) }
            }
        }
    }

    /// Fades an edge with more beyond it, or in the full fold cuts the strip halfway into the gap after its
    /// first row, so the next tile doesn't show at the fold's edge.
    @ViewBuilder private var mask: some View {
        if scrolls {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: edges.moreBefore ? StripEdges.fade : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: edges.moreAfter ? StripEdges.fade : 0)
            }
            .animation(Theme.quick, value: edges)
        } else {
            HStack(spacing: 0) {
                Rectangle()
                    .frame(width: FoldLayout.edgeInset + metrics.rowWidth + Theme.tileSpacing / 2)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Whether the strip has more beyond either end.
private struct StripEdges: Equatable {
    static let space = "tileStrip"
    static let start = "tileStripStart"
    /// How far in from an edge with more beyond it the strip fades out.
    static let fade: CGFloat = 28

    var moreBefore = false
    var moreAfter = false
}

/// The shallow fold's strip, in panel coordinates, while it holds more than it shows.
struct StripFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = value ?? nextValue() }
}

// MARK: - The tile

/// One tile, laid out as every card is: what it is at the top, its line of details at its foot (see
/// `TileMeta`). What it is is an icon beside a title and a quieter line under it, or the words or code
/// themselves; a picture, a page's picture, a map or a colour takes the top of the card instead, the
/// card's full width, with its title and details on the card under it, so the title never sits on the
/// picture. A ring shows while it is open or the keyboard is on it, and what a click did in a capsule
/// over its corner. All of it is said in the tooltip and VoiceOver too.
struct ContentTileView: View {
    let content: TileContent
    var feedback: TuckModel.RowFeedback?
    var isHovering = false
    var isActive = false
    /// Wear the time it was copied or added.
    var showsTime = false
    @Environment(\.tileMetrics) private var tile
    @Environment(\.isTileFocused) private var isFocused

    var body: some View {
        let meta = TileMeta(content: content, showsTime: showsTime, revealsMore: isHovering || isActive || isFocused)
            .opacity(feedback == nil ? 1 : 0)
        Group {
            if let title = previewTitle {
                VStack(alignment: .leading, spacing: 0) {
                    preview
                        .frame(width: tile.width, height: tile.previewHeight)
                        .clipped()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.tileTitle)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .truncationMode(content.fileURLs.isEmpty ? .tail : .middle)
                        meta
                    }
                    .padding(.horizontal, Theme.tilePadding)
                    .padding(.bottom, Theme.tileFootPadding)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    face
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    meta
                }
                .padding([.top, .horizontal], Theme.tilePadding)
                .padding(.bottom, Theme.tileFootPadding)
            }
        }
        .modifier(TileChrome(isHovering: isHovering, isActive: isActive, isPressed: feedback != nil, feedback: feedback))
    }

    /// The title under a card's preview, for the kinds that show one: a picture's or a film's file name
    /// (a copied picture is named by its kind), a page's title, an address's street, a colour's hex.
    private var previewTitle: String? {
        switch content.category {
        case .image, .screenshot, .video: return content.fileURLs.first?.lastPathComponent ?? content.category.title
        case .color: return content.recognition.color?.hex ?? content.text
        case .address: return TileText.addressLines(content).street
        case .link, .music:
            guard content.pageImageURL != nil else { return nil }
            return content.title.flatMap(\.nilIfEmpty) ?? TileText.site(of: content.linkURL) ?? content.text
        default: return nil
        }
    }

    @ViewBuilder private var preview: some View {
        switch content.category {
        case .image, .screenshot: ImagePreview(content: content)
        case .video: VideoPreview(content: content)
        case .color: ColorPreview(content: content)
        case .address: MapPreview(content: content)
        default: PagePreview(content: content)
        }
    }

    @ViewBuilder private var face: some View {
        switch content.category {
        case .text, .window: TextFace(content: content)
        case .richText: RichTextFace(content: content)
        case .code: CodeFace(content: content)
        case .link, .music: LinkFace(content: content)
        case .email: EmailFace(content: content)
        case .phone: PhoneFace(content: content)
        case .contact: ContactFace(content: content)
        case .date: DateFace(content: content)
        case .emoji: EmojiFace(content: content)
        case .path: PathFace(content: content)
        case .secret: SecretFace(content: content)
        case .audio: AudioFace(content: content)
        case .file, .folder: FileFace(content: content)
        case .stack: StackFace(content: content)
        // Shown as previews above; a picture or a film that has none yet still has its title.
        case .image, .screenshot, .video, .color, .address: EmptyView()
        }
    }
}

/// The card every tile sits in: its size, one light grey ground whatever it holds, a step darker (or
/// lighter, on black) under the pointer, a ring while it is open or the keyboard is on it, a small press
/// when a click lands and what that click did, said in a capsule that comes and goes. The card is light
/// in both appearances, so everything on it takes the card's inks (`isOnTileCard`).
struct TileChrome: ViewModifier {
    let isHovering: Bool
    var isActive = false
    var isPressed = false
    var feedback: TuckModel.RowFeedback?
    @Environment(\.tileMetrics) private var tile
    @Environment(\.isTileFocused) private var isFocused

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
        let ground = isHovering || isFocused ? Theme.tileHover : Theme.tileFill
        content
            .frame(width: tile.width, height: tile.height, alignment: .topLeading)
            .background(ground)
            .overlay(alignment: .bottomTrailing) {
                if let feedback {
                    // Ringed in the tile's own ground, so it reads cut out of the words under it.
                    FeedbackBadge(feedback: feedback)
                        .padding(2)
                        .background(ground, in: Capsule())
                        .padding(4)
                }
            }
            .environment(\.isOnTileCard, true)
            .clipShape(shape)
            .overlay {
                // In the card's deep blue, which stands off the card and the black: thin while open, and
                // a heavier ring where the keyboard is, so the two never read alike.
                if isFocused || isActive {
                    shape.strokeBorder(Theme.accent, lineWidth: isFocused ? 2.5 : 1.5)
                        .environment(\.isOnTileCard, true)
                }
            }
            .overlay { if !isActive && !isFocused { shape.strokeBorder(Theme.tileEdge) } }
            .scaleEffect(isPressed && !Theme.reduceMotion ? 0.97 : 1)
            .animation(Theme.press, value: isPressed)
            .animation(Theme.quick, value: isHovering)
            .animation(Theme.quick, value: isFocused)
            .animation(Theme.quick, value: feedback)
            .contentShape(shape)
    }
}

/// What a card is, at its top: a picture on the left (an icon, an avatar, a flag, a calendar page) beside
/// its title and, under it, a quieter line. The title takes two lines where it needs them and the card
/// has room, then one, and the quieter line goes before the title is cut further.
private struct Headline<Lead: View>: View {
    @ViewBuilder let lead: () -> Lead
    let title: String
    var titleFont: Font = .tileTitle
    var titleLines = 2
    /// A number or a key, which reads wrong cut or broken, shrinks a little before it is cut.
    var titleScale: CGFloat = 1
    /// File names keep their ends (the extension tells the kind); names and titles read from the start.
    var truncation: Text.TruncationMode = .tail
    var subtitle: String?
    var subtitleTruncation: Text.TruncationMode?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            lead()
                .frame(width: Theme.tileLead, height: Theme.tileLead)
            ViewThatFits(in: .vertical) {
                words(titleLines: titleLines, subtitle: true)
                words(titleLines: 1, subtitle: true)
                words(titleLines: 1, subtitle: false)
            }
            .frame(minHeight: Theme.tileLead)
        }
    }

    private func words(titleLines: Int, subtitle shown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(titleFont)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(titleLines)
                .minimumScaleFactor(titleScale)
                .truncationMode(truncation)
            if shown, let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.panelSubtitle)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(subtitleTruncation ?? truncation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Faces

private struct TextFace: View {
    let content: TileContent

    var body: some View {
        WordsFace(text: AttributedString(TileText.excerpt(content.text)))
    }
}

private struct RichTextFace: View {
    let content: TileContent

    var body: some View {
        WordsFace(text: content.richTextURL.flatMap(ItemDetails.richExcerpt(at:))
                  ?? AttributedString(TileText.excerpt(content.text)))
    }
}

/// Copied words in the rounded face: up to three lines of them, fewer on a small card, ending in an
/// ellipsis.
private struct WordsFace: View {
    let text: AttributedString

    var body: some View {
        Text(text)
            .font(.panelWords)
            .foregroundStyle(Theme.primaryText)
            .lineLimit(3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Code as an editor shows it: its first lines, quietly tinted, each beside its number. Blank lines keep
/// their place, so the numbers are the lines' own, and a long line runs on to the card's padding, fading
/// out there, rather than ending in an ellipsis as words do.
private struct CodeFace: View {
    let content: TileContent
    @Environment(\.tileMetrics) private var tile
    /// The numbers' column, and the space between them and the code.
    static let gutter: CGFloat = 14
    static let codeGap: CGFloat = 7

    var body: some View {
        let most = CodeExcerpt.lines(content.text, count: CodeExcerpt.mostLines).count
        // As many of the first lines as the card has room for, and never more than a large card's.
        ViewThatFits(in: .vertical) {
            ForEach(Array(stride(from: most, through: 1, by: -1)), id: \.self) { count in
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(CodeExcerpt.lines(content.text, count: count).enumerated()), id: \.offset) { index, line in
                        CodeLine(number: index + 1, line: line, language: content.recognition.language)
                    }
                }
            }
        }
        // The card's inner width, though a long line is wider, so the fade falls at the padding.
        .frame(width: tile.width - Theme.tilePadding * 2, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .mask {
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
            }
        }
    }
}

/// One line of code beside its number, at its full length.
private struct CodeLine: View {
    let number: Int
    let line: String
    let language: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(number)")
                .font(.panelCodeGutter)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: CodeFace.gutter, alignment: .trailing)
                .accessibilityHidden(true)
            // A blank line still takes its line's height.
            Text(CodeExcerpt.highlighted(line.isEmpty ? " " : line, language: language, keyword: Theme.codeKeyword))
                .font(.panelCode)
                .fixedSize()
                .padding(.leading, CodeFace.codeGap)
        }
    }
}

/// A link: its site's icon (a link symbol until its page has been looked up) beside the page's title, the
/// site on the line of details. A page with no title (or not yet looked up) is named by its site, with
/// the rest of its address under it. A page that gave a picture for sharing shows that above its title
/// instead (see `PagePreview`).
private struct LinkFace: View {
    let content: TileContent

    var body: some View {
        let icon = content.iconURL.flatMap(ItemDetails.image(at:))
        let address = (content.linkURL?.absoluteString ?? content.text).trimmingCharacters(in: .whitespacesAndNewlines)
        let site = TileText.site(of: content.linkURL)
        if let title = content.title.flatMap(\.nilIfEmpty) {
            Headline(lead: { SiteIcon(image: icon, side: Theme.tileLead) }, title: title)
        } else if let site {
            // A site's name is one word to the eye, never broken across lines.
            Headline(lead: { SiteIcon(image: icon, side: Theme.tileLead) }, title: site, titleLines: 1,
                     subtitle: TileText.path(of: address, after: site), subtitleTruncation: .middle)
        } else {
            Headline(lead: { SiteIcon(image: icon, side: Theme.tileLead) }, title: address, truncation: .middle)
        }
    }
}

/// A site's icon as its page gives it. A touch icon (drawn to its edges, and sharp at this size) fills a
/// rounded square; anything else, such as a favicon, sits in the middle of a white one, so a dark mark on a
/// clear ground reads on the card. Without one, a link symbol sits on the white square.
private struct SiteIcon: View {
    let image: NSImage?
    let side: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.23, style: .continuous)
        if let image {
            icon(image, shape)
        } else {
            Image(systemName: "link")
                .font(.system(size: side * 0.42, weight: .semibold))
                .foregroundStyle(Color(white: 0.4))
                .frame(width: side, height: side)
                .background(Color.white)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5) }
                .accessibilityHidden(true)
        }
    }

    private func icon(_ image: NSImage, _ shape: RoundedRectangle) -> some View {
        let bitmap = image.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }
        let opaque = bitmap.map { rep in
            [(0, 0), (rep.pixelsWide - 1, rep.pixelsHigh - 1)].allSatisfy { (rep.colorAt(x: $0, y: $1)?.alphaComponent ?? 0) > 0.9 }
        } ?? false
        let fills = opaque && CGFloat(bitmap?.pixelsWide ?? 0) >= side * 2
        return Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: fills ? .fill : .fit)
            .frame(width: fills ? side : side * 0.64, height: fills ? side : side * 0.64)
            .frame(width: side, height: side)
            .background(fills ? Color.clear : Color.white)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5) }
            .accessibilityHidden(true)
    }
}

/// A page's own picture for sharing, filling the card's preview.
private struct PagePreview: View {
    let content: TileContent
    @Environment(\.tileMetrics) private var tile

    var body: some View {
        if let url = content.pageImageURL, let picture = ItemDetails.image(at: url) {
            Image(nsImage: picture).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .frame(width: tile.width, height: tile.previewHeight).clipped()
                .accessibilityHidden(true)
        } else {
            PreviewPlaceholder(symbol: "link")
        }
    }
}

private struct EmailFace: View {
    let content: TileContent

    var body: some View {
        let address = TileText.emailAddress(content.text)
        let parts = address.split(separator: "@", maxSplits: 1).map(String.init)
        Headline(lead: { Avatar(initials: ContactBadge.initials(email: address), key: address) },
                 title: parts.first ?? address, titleLines: 1, subtitle: parts.count > 1 ? "@" + parts[1] : nil)
    }
}

/// A number set as it is read where it rings, beside its country's flag, with the country under it.
private struct PhoneFace: View {
    let content: TileContent
    @Environment(\.locale) private var locale

    var body: some View {
        let written = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = PhoneNumberFormat.parse(written, defaultRegion: locale.region?.identifier)
        let international = number?.isInternational == true
        let country = number?.region.flatMap { locale.localizedString(forRegionCode: $0) }
        let code = number?.callingCode.map { "+" + $0 }
        Headline(lead: { PhoneBadge(flag: number?.flag) },
                 title: international ? number?.formatted ?? written : number?.nationalFormatted ?? written,
                 titleFont: .tileTitle.monospacedDigit(), titleLines: 1, titleScale: 0.8,
                 subtitle: [country, international ? nil : code].compactMap { $0 }.joined(separator: " "))
    }
}

private struct ContactFace: View {
    let content: TileContent
    @Environment(\.locale) private var locale

    var body: some View {
        let name = content.recognition.name ?? "Contact"
        let phone = VCard.values("TEL", in: content.text).first
        let email = VCard.values("EMAIL", in: content.text).first
        let number = phone.flatMap { PhoneNumberFormat.parse($0, defaultRegion: locale.region?.identifier)?.formatted } ?? phone
        // Keyed by the address when the card has one, so a person's card and their address share a colour.
        Headline(lead: { Avatar(initials: ContactBadge.initials(name: name), key: email ?? name) },
                 title: name, subtitle: number ?? email ?? content.recognition.detail)
    }
}

private struct DateFace: View {
    let content: TileContent

    var body: some View {
        let date = content.recognition.date ?? content.date
        let showsTime = content.recognition.includesTime == true
        Headline(lead: { MiniCalendar(date: date) },
                 title: date.formatted(.dateTime.weekday(.wide)), titleLines: 1,
                 subtitle: showsTime ? date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
                                     : date.formatted(.dateTime.day().month(.abbreviated).year()))
    }
}

/// An emoji beside its name.
private struct EmojiFace: View {
    let content: TileContent

    var body: some View {
        let name = content.recognition.name.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        Headline(lead: {
            Text(content.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 24))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .accessibilityHidden(true)
        }, title: name ?? "Emoji")
    }
}

private struct PathFace: View {
    let content: TileContent

    var body: some View {
        let url = TileText.pathURL(content.text)
        Headline(lead: {
            Image(nsImage: ItemDetails.icon(for: url))
                .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .opacity(FileManager.default.fileExists(atPath: url.path) ? 1 : 0.5)
                .accessibilityHidden(true)
        }, title: url.lastPathComponent, titleLines: 1, truncation: .middle,
           subtitle: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
    }
}

/// A key stays hidden: its prefix and last four, beside a lock.
private struct SecretFace: View {
    let content: TileContent

    var body: some View {
        Headline(lead: {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }, title: TileText.masked(content.text), titleFont: .system(.body, design: .monospaced).weight(.semibold),
           titleLines: 1, titleScale: 0.8, truncation: .middle)
    }
}

/// The shared shape of a card's preview with nothing to show yet: its kind's symbol, quiet on the card.
private struct PreviewPlaceholder: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .regular))
            .foregroundStyle(Theme.tertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.primaryText.opacity(0.05))
            .accessibilityHidden(true)
    }
}

private struct ImagePreview: View {
    let content: TileContent

    var body: some View {
        if let url = content.imageURL {
            TilePicture(url: url)
        } else {
            PreviewPlaceholder(symbol: content.category == .screenshot ? "camera.viewfinder" : "photo")
        }
    }
}

private struct VideoPreview: View {
    let content: TileContent

    var body: some View {
        ZStack {
            // A film's first frame fills the preview; with none to show, a quiet placeholder.
            if let url = content.imageURL { TilePicture(url: url) } else { PreviewPlaceholder(symbol: "film") }
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.45), in: Circle())
                .accessibilityHidden(true)
        }
    }
}

/// A colour fills the preview, over a checkerboard where it is see-through.
private struct ColorPreview: View {
    let content: TileContent

    var body: some View {
        let color = content.recognition.color ?? RGBAColor(red: 0.5, green: 0.5, blue: 0.5)
        ZStack {
            if color.alpha < 1 { Checkerboard() }
            Color(color)
        }
        .accessibilityHidden(true)
    }
}

/// An address's map fills the preview, the pin in its middle: Apple Maps' picture once it has come, or
/// one drawn from the address until then.
private struct MapPreview: View {
    let content: TileContent
    @Environment(\.tileMetrics) private var tile

    var body: some View {
        ZStack {
            if let url = content.mapURL, let map = ItemDetails.image(at: url) {
                Image(nsImage: map).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: tile.width, height: tile.previewHeight).clipped()
            } else {
                DrawnMap(seed: content.text)
            }
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(nsColor: .systemRed))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct AudioFace: View {
    let content: TileContent

    var body: some View {
        let url = content.fileURLs.first
        Headline(lead: { Artwork(url: url) },
                 title: content.preview?.title ?? url?.deletingPathExtension().lastPathComponent ?? content.text,
                 subtitle: content.preview?.artist)
    }
}

private struct FileFace: View {
    let content: TileContent

    var body: some View {
        let url = content.fileURLs.first
        let missing = url.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true
        Headline(lead: { FileIcon(url: url, side: Theme.tileLead) },
                 title: url?.lastPathComponent ?? content.text, truncation: .middle,
                 subtitle: missing ? "No longer there" : nil, subtitleTruncation: .tail)
    }
}

/// A stack's first files fanned, the first one's name, and under it the next one's, or how many more.
private struct StackFace: View {
    let content: TileContent

    var body: some View {
        let names = content.fileURLs.map(\.lastPathComponent)
        Headline(lead: { FannedIcons(urls: content.fileURLs) }, title: names.first ?? content.text, titleLines: 1,
                 truncation: .middle, subtitle: Self.rest(names), subtitleTruncation: .middle)
    }

    /// The second name with two, and "and 3 more" with more.
    private static func rest(_ names: [String]) -> String? {
        switch names.count {
        case ..<2: nil
        case 2: names[1]
        default: "and \(names.count - 1) more"
        }
    }
}

/// An app's tucked windows as one tile: its icon beside its name and the newest window's title, and its
/// line of details saying how many. A rested app's icon greys.
struct WindowsFace: View {
    let group: AppWindowGroup
    let isResting: Bool
    var isHovering = false
    @Environment(\.isTileFocused) private var isFocused

    var body: some View {
        let count = group.windows.count
        let kind = TileMeta.Fact(text: count == 1 ? "Window" : "\(count) windows")
        let rested = isResting ? TileMeta.Fact(text: "Rested") : nil
        VStack(alignment: .leading, spacing: 4) {
            Headline(lead: {
                         AppIconView(bundleID: group.app.bundleID)
                             .saturation(isResting ? 0 : 1)
                             .opacity(isResting ? 0.55 : 1)
                     },
                     title: group.app.name, titleLines: 1, subtitle: group.windows.first?.displayTitle)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            TileMeta.MetaLine(mark: "macwindow", category: .window,
                              lines: [TileMeta.Line([kind, isHovering || isFocused ? rested : nil])],
                              last: TileMeta.Line([kind]))
        }
        .padding([.top, .horizontal], Theme.tilePadding)
        .padding(.bottom, Theme.tileFootPadding)
    }
}

// MARK: - Pieces

/// A person's round badge: their initials on their own colour, the same wherever they appear.
private struct Avatar: View {
    static let side = Theme.tileLead
    let initials: String
    /// Who it is, for the colour: their address, else their name.
    let key: String

    var body: some View {
        let color = ContactBadge.palette[ContactBadge.colorIndex(for: key)]
        Group {
            if initials.isEmpty {
                Image(systemName: "person.fill").font(.system(size: 13, weight: .semibold))
            } else {
                Text(initials)
                    .font(.system(size: initials.count > 1 ? 12 : 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(ContactBadge.prefersInk(on: color) ? Color(ContactBadge.ink) : .white)
        .frame(width: Self.side, height: Self.side)
        .background(Color(color), in: Circle())
        .accessibilityHidden(true)
    }
}

/// A phone number's badge: its country's flag in a circle, or a handset on green when the country
/// isn't known.
private struct PhoneBadge: View {
    let flag: String?

    var body: some View {
        Group {
            if let flag {
                Text(flag)
                    .font(.system(size: Avatar.side * 1.55))
                    .fixedSize()
                    .frame(width: Avatar.side, height: Avatar.side)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.primaryText.opacity(0.12)))
            } else {
                let green = ContactBadge.palette[2]
                Image(systemName: "phone.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ContactBadge.prefersInk(on: green) ? Color(ContactBadge.ink) : .white)
                    .frame(width: Avatar.side, height: Avatar.side)
                    .background(Color(green), in: Circle())
            }
        }
        .accessibilityHidden(true)
    }
}

/// A picture filling a card's preview: a thumbnail made while the panel is open, at the preview's size.
/// It is cropped to fill, never stretched, so it keeps its shape.
private struct TilePicture: View {
    let url: URL
    @Environment(\.displayScale) private var displayScale
    @Environment(\.tileMetrics) private var tile
    @State private var image: NSImage?

    /// A thumbnail is made again when the tiles change size, so a picture is never stretched past it.
    private struct PictureRequest: Hashable {
        let url: URL
        let side: CGFloat
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: tile.width, height: tile.previewHeight)
                    .clipped()
                    .transition(.opacity)
            } else {
                Theme.primaryText.opacity(0.05)
            }
        }
        .frame(width: tile.width, height: tile.previewHeight)
        .task(id: PictureRequest(url: url, side: tile.width)) {
            let loaded = await ItemDetails.thumbnail(for: url, side: tile.width, scale: displayScale)
            withAnimation(Theme.quick) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}

/// A file's Quick Look thumbnail, or its icon while that is made or when there is none.
private struct FileIcon: View {
    let url: URL?
    let side: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .modifier(ThumbnailEdge())
            } else if let url {
                Image(nsImage: ItemDetails.icon(for: url)).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "doc").resizable().aspectRatio(contentMode: .fit).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return }
            thumbnail = await ItemDetails.thumbnail(for: url, side: side, scale: displayScale)
        }
    }
}

/// A song's artwork, from Quick Look, on a rounded square; a note when the file carries none.
private struct Artwork: View {
    let url: URL?
    @Environment(\.displayScale) private var displayScale
    @State private var art: NSImage?

    var body: some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.tileInset)
            }
        }
        .frame(width: Theme.tileLead, height: Theme.tileLead)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url else { return }
            art = await ItemDetails.thumbnail(for: url, side: Theme.tileLead, scale: displayScale)
        }
    }
}

/// The first few files of several, fanned like a hand of cards.
private struct FannedIcons: View {
    let urls: [URL]

    var body: some View {
        ZStack {
            ForEach(Array(urls.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                Image(nsImage: ItemDetails.icon(for: url))
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(Double(index) * 9 - 9))
                    .offset(x: CGFloat(index) * 3 - 3)
            }
        }
        .frame(width: Theme.tileLead, height: Theme.tileLead)
        .accessibilityHidden(true)
    }
}

/// A calendar page: the month in a band of the card's blue over the day.
private struct MiniCalendar: View {
    let date: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 11)
                .background(Theme.accent)
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Theme.tileLead, height: Theme.tileLead)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5) }
        .accessibilityHidden(true)
    }
}

/// A few streets, a park and a stretch of water, drawn from the address itself so each address has its
/// own map, for when no map picture was fetched (before Apple Maps answers, or when it can't be reached).
private struct DrawnMap: View {
    let seed: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.tileMetrics) private var tile

    var body: some View {
        // Light, a paper map; dark, a night one.
        let isLight = colorScheme == .light
        Canvas { context, size in
            var generator = SeededGenerator(seed: seed)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: isLight ? 0.9 : 0.13)))
            let water = Path(ellipseIn: CGRect(x: size.width * CGFloat.random(in: 0.55...0.9, using: &generator),
                                               y: size.height * CGFloat.random(in: -0.4...0.2, using: &generator),
                                               width: size.width * 0.6, height: size.height * 0.9))
            context.fill(water, with: .color(isLight ? Color(red: 0.66, green: 0.8, blue: 0.93)
                                                     : Color(red: 0.2, green: 0.3, blue: 0.42).opacity(0.55)))
            let park = Path(roundedRect: CGRect(x: size.width * CGFloat.random(in: 0.05...0.4, using: &generator),
                                                y: size.height * CGFloat.random(in: 0.45...0.7, using: &generator),
                                                width: 34, height: 22), cornerRadius: 5)
            context.fill(park, with: .color(isLight ? Color(red: 0.72, green: 0.86, blue: 0.7)
                                                    : Color(red: 0.24, green: 0.36, blue: 0.27).opacity(0.6)))
            for index in 0..<7 {
                var street = Path()
                let width: CGFloat = index < 2 ? 5 : 2.5
                if index % 2 == 0 {
                    let y = size.height * CGFloat.random(in: 0.1...0.9, using: &generator)
                    street.move(to: CGPoint(x: -4, y: y))
                    street.addLine(to: CGPoint(x: size.width + 4, y: y + CGFloat.random(in: -14...14, using: &generator)))
                } else {
                    let x = size.width * CGFloat.random(in: 0.05...0.95, using: &generator)
                    street.move(to: CGPoint(x: x, y: -4))
                    street.addLine(to: CGPoint(x: x + CGFloat.random(in: -20...20, using: &generator), y: size.height + 4))
                }
                let shade: Double = isLight ? (index < 2 ? 1 : 0.97) : (index < 2 ? 0.34 : 0.24)
                context.stroke(street, with: .color(Color(white: shade)), lineWidth: width)
            }
        }
        .frame(width: tile.width, height: tile.previewHeight)
        .accessibilityHidden(true)
    }
}

/// A repeatable random sequence, so the same address always draws the same map.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        state = seed.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// The grey and white squares behind something see-through.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 6
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.32)))
            for row in 0...Int(size.height / side) {
                for column in 0...Int(size.width / side) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)),
                                 with: .color(Color(white: 0.22)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Text helpers

enum TileText {
    /// The text as a tile shows it: runs of spaces and new lines folded into single spaces.
    static func excerpt(_ text: String, limit: Int = 240) -> String {
        let folded = text.prefix(limit * 2).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(folded.prefix(limit))
    }

    /// What follows a link's site, its scheme and "www." gone: "/docs/start?id=4" after "example.com".
    static func path(of address: String, after site: String) -> String? {
        guard let range = address.range(of: site) else { return nil }
        let rest = address[range.upperBound...]
        return rest.count > 1 ? String(rest) : nil
    }

    /// A link's site as people say it: its host without "www.".
    static func site(of url: URL?) -> String? {
        guard let host = url?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func emailAddress(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("mailto:") ? String(trimmed.dropFirst(7)) : trimmed
    }

    static func pathURL(_ text: String) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) { return url }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    /// A key with only enough showing to tell it apart: its prefix and last four, "sk-ant-••••Ab3F".
    static func masked(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("-----BEGIN") { return "-----BEGIN ••••" }
        let body = trimmed.hasPrefix("Bearer ") ? String(trimmed.dropFirst(7)) : trimmed
        let prefix = ["sk-ant-", "sk-proj-", "github_pat_", "ghp_", "gho_", "xoxb-", "xoxp-", "glpat-", "AKIA", "AIza", "eyJ"]
            .first(where: body.hasPrefix) ?? String(body.prefix(3))
        return prefix + "••••" + body.suffix(4)
    }

    static func addressLines(_ content: TileContent) -> (street: String, place: String?) {
        if let street = content.recognition.name {
            return (street, content.recognition.detail)
        }
        let lines = content.text.components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (lines.first ?? content.text, lines.dropFirst().joined(separator: ", ").nilIfEmpty)
    }
}

/// Code's first lines, with the indentation they share taken off and a quiet tint: keywords in the blue,
/// strings and numbers warm, comments quieter than the code.
enum CodeExcerpt {
    /// The most lines a code card shows, on its largest size.
    static let mostLines = 6

    /// Blank lines before the first and after the last shown are left out, as the line of details' count
    /// leaves them; those between stay, empty, as an editor shows them.
    static func lines(_ code: String, count: Int) -> [String] {
        func isBlank(_ line: Substring) -> Bool { line.allSatisfy { $0 == " " || $0 == "\t" } }
        let lines = code.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let first = lines.firstIndex(where: { !isBlank($0) }) else { return [] }
        var shown = Array(lines[first...].prefix(count))
        while let last = shown.last, isBlank(last) { shown.removeLast() }
        let indent = shown.filter { !isBlank($0) }.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        return shown.map { isBlank($0) ? "" : String($0.dropFirst(indent).prefix(120)).replacingOccurrences(of: "\t", with: "  ") }
    }

    private static let keywords = "func|let|var|if|else|for|while|return|import|class|struct|enum|protocol|extension|def|"
        + "function|const|public|private|static|async|await|try|catch|guard|switch|case|break|continue|in|of|new|this|"
        + "self|true|false|nil|null|None|True|False|fn|impl|pub|mut|use|package|interface|type|export|from|select|"
        + "where|insert|update|delete|create|table|echo|sudo|git|npm|brew|cd|elif|lambda|yield|throw|throws|do|then|fi|"
        + "SELECT|FROM|WHERE|INSERT|UPDATE|DELETE|CREATE|TABLE|JOIN|ORDER|BY|GROUP|AND|OR|NOT"
    private static let pattern = try! NSRegularExpression(pattern:
        "(?<comment>//[^\\n]*|/\\*.*?\\*/)|(?<hash>#[^\\n]*)|(?<string>\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'|`[^`]*`)"
        + "|(?<keyword>\\b(?:\(keywords))\\b)|(?<number>\\b\\d+(?:\\.\\d+)?\\b)")
    private static let hashCommentLanguages: Set<String> = ["Shell", "Python", "Ruby"]

    static func highlighted(_ line: String, language: String?, keyword: Color) -> AttributedString {
        var result = AttributedString()
        let ns = line as NSString
        var cursor = 0
        func append(_ range: NSRange, _ color: Color, weight: Font.Weight? = nil) {
            var piece = AttributedString(ns.substring(with: range))
            piece.foregroundColor = color
            result += piece
        }
        for match in pattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                append(NSRange(location: cursor, length: match.range.location - cursor), Theme.primaryText)
            }
            if match.range(withName: "comment").location != NSNotFound {
                append(match.range, Theme.secondaryText)
            } else if match.range(withName: "hash").location != NSNotFound {
                append(match.range, hashCommentLanguages.contains(language ?? "") ? Theme.secondaryText : Theme.primaryText)
            } else if match.range(withName: "string").location != NSNotFound {
                append(match.range, Theme.codeString)
            } else if match.range(withName: "keyword").location != NSNotFound {
                append(match.range, keyword)
            } else {
                // In the strings' own tone: one faded below it fell under 4.5:1 on a light hover.
                append(match.range, Theme.codeString)
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { append(NSRange(location: cursor, length: ns.length - cursor), Theme.primaryText) }
        return result
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Color {
    init(_ color: RGBAColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
