import SwiftUI
import TuckCore

/// The fold that drops from the notch or bubble, over everything Tuck holds in one stream, newest first.
/// Its top line sits level with the notch. In the shallow fold the Tuck button is on its left and the
/// lenses right beside the notch, over one row of tiles, the newest at the left, that scrolls sideways
/// through the rest; in the full fold it reads "Everything in Tuck", with search and fold, over the whole
/// stream in a list that scrolls and Arrange windows at its foot. How many tiles sit in a row, and how
/// big, is set in Settings › Notch, and the fold is as wide as a row of them. Questions open inline at the bottom. The fold is drawn dark on the black
/// surface, whatever the Light or Dark setting.
struct ExpandedPanelView: View {
    @ObservedObject var model: TuckModel
    let anchor: ScreenAnchor
    let onHeightChange: (CGFloat) -> Void
    @State private var listContentHeight: CGFloat = 0
    @State private var listFrame: CGRect = .zero

    /// Beyond this the list scrolls: a compact list, never a drawer down the screen.
    private var maximumListHeight: CGFloat {
        min(440, max(180, anchor.screenFrame.height - anchor.menuBarHeight - 280))
    }

    private var listViewportHeight: CGFloat {
        PanelListLayout.viewportHeight(contentHeight: listContentHeight, maximumHeight: maximumListHeight)
    }

    private var fold: FoldLayout { SurfaceMetrics(anchor: anchor, cards: model.cardLayout).fold }

    var body: some View {
        VStack(spacing: 0) {
            panel
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
                })
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(PanelHeightKey.self) { onHeightChange($0) }
        .onPreferenceChange(StripFrameKey.self) { model.stripFrame = $0 }
        // Icons, thumbnails and file details are kept only while the panel is open.
        .onDisappear {
            ItemDetails.purge()
            model.stripFrame = nil
        }
    }

    private var panel: some View {
        let stream = model.stream
        let isFull = model.foldDepth == .full
        let fold = fold
        return VStack(spacing: 0) {
            FoldBand(model: model, anchor: anchor)
            let chips = isFull ? SearchBar.chips(for: model, foldWidth: fold.width) : []
            if SearchBar.isShown(for: model, chips: chips) {
                SearchBar(model: model, chips: chips)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    .transition(Theme.reveal(edge: .top))
            }
            list(stream)
            if !isFull, model.windowPicker == nil, stream.count > fold.columns {
                MoreRow(model: model, total: stream.count)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
            FoldToolbar(model: model)
            prompts
            PanelFooter(model: model)
        }
        .frame(width: fold.width)
        .padding(.bottom, 4)
        .environment(\.tileMetrics, TileMetrics(fold))
        .overlay { DropTargetOverlay(model: model, anchor: anchor) }
        .coordinateSpace(.named(Theme.panelSpace))
        .onPreferenceChange(WindowRowFramesKey.self) { model.windowLandings = $0 }
        .animation(Theme.fold, value: model.foldDepth)
        .animation(Theme.quick, value: model.lens)
    }

    // MARK: List

    /// The stream, the window picker in its place while it is open, or the cue an empty Tuck shows. The
    /// stream is tiles: in the shallow fold one row that scrolls sideways, in the full fold rows of them,
    /// scrolling past `maximumListHeight`.
    @ViewBuilder
    private func list(_ stream: [StreamEntry]) -> some View {
        Group {
            if let picker = model.windowPicker {
                scrolling {
                    SuggestedWindowsView(model: model, picker: picker)
                }
            } else if model.isStreamEmpty {
                EmptyCue(symbol: "tray.and.arrow.down", text: DropKind.invitation)
            } else if stream.isEmpty, model.isSearching, !model.searchQuery.isEmpty {
                NoMatches(model: model)
            } else if stream.isEmpty {
                EmptyCue(symbol: "line.3.horizontal.decrease", text: "Nothing here yet")
            } else {
                // One grid for both depths, so deepening the fold keeps the first row where it is and adds
                // the rest under it. Fewer than a row keep their size and sit from the left, where the
                // newest always is, so a tile never moves when another arrives. The grid spans the fold, so
                // the strip scrolls from edge to edge, and sets its own rows in.
                scrolling(horizontalPadding: 0) {
                    StreamTiles(model: model, stream: stream)
                }
            }
        }
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ListFrameKey.self, value: proxy.frame(in: .named(Theme.panelSpace)))
        })
        .onPreferenceChange(ListFrameKey.self) {
            listFrame = $0
            reportScrollableList()
        }
    }

    private func scrolling<Content: View>(horizontalPadding: CGFloat = 8,
                                          @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 2)
                .padding(.bottom, Theme.listFoot)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ListHeightKey.self, value: proxy.size.height)
                })
        }
        // A mouse's scroll bar sits beside the rows rather than over them, and would cut the last card
        // short, so the list shows only the bar that floats; a row cut at the foot says there's more.
        .scrollIndicators(NSScroller.preferredScrollerStyle == .overlay ? .automatic : .never)
        .frame(width: fold.width, height: listViewportHeight, alignment: .top)
        .onPreferenceChange(ListHeightKey.self) {
            listContentHeight = $0
            reportScrollableList()
        }
    }

    /// Tells the surface where the list's rows are, and, while they can scroll, that vertical swipes over
    /// them scroll the list rather than folding it.
    private func reportScrollableList() {
        var rows = listFrame
        rows.size.height = min(rows.height, listViewportHeight)
        model.listFrame = rows
        let scrolls = PanelListLayout.scrolls(contentHeight: listContentHeight, viewportHeight: listViewportHeight)
        model.scrollableListFrame = scrolls ? rows : nil
    }

    // MARK: Prompts

    /// One question or notice at a time, inline at the foot of the fold.
    @ViewBuilder private var prompts: some View {
        Group {
            if let plan = model.clearPlan {
                ClearPromptView(model: model, plan: plan)
                    .transition(Theme.reveal(edge: .bottom))
            } else if model.clearCopiedPrompt {
                ClearCopiedPromptView(model: model)
                    .transition(Theme.reveal(edge: .bottom))
            } else if model.restoreAllPrompt {
                RestoreAllPromptView(model: model)
                    .transition(Theme.reveal(edge: .bottom))
            } else if let prompt = model.restPrompt {
                restPrompt(prompt)
                    .transition(Theme.reveal(edge: .bottom))
            } else if model.accessibilityLostWithWindows {
                accessibilityLostCard
            } else if let picker = model.windowPicker {
                PickerActionBar(model: model, picker: picker)
            } else if model.clipboardAccessHeldBack, model.clipboard.isEnabled,
                      model.lens == .copied || model.foldDepth == .full {
                InlinePromptView(symbol: "lock", title: "Copies from other apps are held back",
                                 detail: "Allow Tuck in Privacy & Security → Paste from Other Apps.",
                                 choices: [.init(title: "Open Settings…", action: ClipboardCaptureService.openPasteSettings)])
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    /// At the foot of the fold while Accessibility is off with windows tucked: without it they can't come
    /// back, so this stays until it is allowed again. Quitting can't help the ones off screen either,
    /// since moving them to the Dock takes the same permission.
    private var accessibilityLostCard: some View {
        let windows = model.library.windows
        let count = windows.count
        let detail = "Tuck needs \(AX.paneName) to bring them back. Allow Tuck there again; until then, minimised ones wait in the Dock"
            + (windows.contains(where: \.isOffScreen) ? ", and quitting Tuck leaves the rest out of sight." : ".")
        return InlinePromptView(
            symbol: "lock",
            title: count == 1 ? "1 tucked window can't come back" : "\(count) tucked windows can't come back",
            detail: detail,
            choices: [.init(title: "Open Settings…", emphasised: true, action: AX.openAccessibilitySettings)]
        )
    }

    private func restPrompt(_ prompt: TuckModel.RestPrompt) -> some View {
        let title: String
        let detail: String
        let action: String
        switch prompt.step {
        case .turnOn:
            // One question: turning Rest on and the first rest share the explanation.
            title = "Turn on Rest and rest \(prompt.app.name)?"
            detail = RestSafetyPolicy.firstUseExplanation + " Rest is experimental; turning it off in Settings wakes any rested app."
            action = "Turn On and Rest"
            return InlinePromptView(symbol: "moon.zzz", title: title, detail: detail, choices: [
                .init(title: action, emphasised: true, action: model.confirmRest),
                .init(title: "Cancel", isCancel: true, action: model.cancelRest)
            ])
        case .explain:
            detail = RestSafetyPolicy.firstUseExplanation
            action = "Rest \(prompt.app.name)"
        case .confirmBusy(let reason):
            detail = reason
            action = "Rest Anyway"
        }
        title = "Rest \(prompt.app.name)?"
        return InlinePromptView(
            symbol: "moon.zzz",
            title: title,
            detail: detail,
            choices: [
                .init(title: action, emphasised: prompt.step == .explain, destructive: prompt.step != .explain,
                      action: model.confirmRest),
                .init(title: "Cancel", isCancel: true, action: model.cancelRest)
            ]
        )
    }
}

// MARK: - Band

/// The fold's top line, level with the notch, so the fold grows wider before it grows taller. Around a
/// notch the notch itself is the middle; on a display without one the mark sits there, as in the bubble.
/// Shallow, it holds the Tuck button on the left and the lenses right beside the notch. Full, the lenses
/// recede and it reads "Everything in Tuck", with search and fold on the right. A secondary click offers
/// what acts on everything at once.
struct FoldBand: View {
    @ObservedObject var model: TuckModel
    let anchor: ScreenAnchor

    private var metrics: SurfaceMetrics { SurfaceMetrics(anchor: anchor, cards: model.cardLayout) }
    private var middleWidth: CGFloat {
        anchor.kind == .notch ? anchor.notchSize.width : metrics.restingSize.width
    }
    private var height: CGFloat {
        anchor.kind == .notch ? anchor.notchSize.height : metrics.height + 10
    }
    private var wingWidth: CGFloat { max(0, (metrics.panelWidth - middleWidth) / 2) }
    private var isFull: Bool { model.foldDepth == .full }

    var body: some View {
        // Each wing keeps its width when it shows nothing (no front window, nothing held), so the
        // middle stays over the notch.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: wingWidth)
                .overlay(alignment: .leading) {
                    leading
                        .padding(.leading, isFull ? 16 : 12)
                        .padding(.trailing, 6)
                }
            middle
                .frame(width: middleWidth)
            Color.clear
                .frame(width: wingWidth)
                .overlay(alignment: isFull ? .trailing : .leading) {
                    trailing
                        .padding(.leading, 6)
                        .padding(.trailing, 10)
                }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .contextMenu { FoldMenuItems(model: model) }
    }

    @ViewBuilder private var leading: some View {
        if isFull, model.windowPicker == nil, let lens = model.lens {
            // A search asked for from inside a lens stays in it until the lens is let go.
            LensBadge(lens: lens) { model.toggleLens(lens) }
                .transition(.opacity)
        } else if isFull {
            // A fold kept narrow by small tiles shortens its title rather than cutting it.
            ViewThatFits(in: .horizontal) {
                title(model.windowPicker != nil ? "Choose windows to tuck" : "Everything in Tuck")
                title(model.windowPicker != nil ? "Choose windows" : "Everything")
            }
            .transition(.opacity)
        } else {
            TuckFrontButton(model: model)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.panelHeadline)
            .foregroundStyle(Theme.primaryText)
            .lineLimit(1)
            .fixedSize()
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var middle: some View {
        if anchor.kind == .bubble {
            LogoLine()
                .stroke(model.isStreamEmpty ? Theme.faint : Theme.accent,
                        style: StrokeStyle(lineWidth: TuckLogo.lineWidth(side: metrics.markSide), lineCap: .round, lineJoin: .round))
                .frame(width: metrics.markSide, height: metrics.markSide)
                .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var trailing: some View {
        if isFull {
            HStack(spacing: 2) {
                if model.windowPicker == nil {
                    Button("Search", systemImage: "magnifyingglass") {
                        model.isSearching ? model.endSearch() : model.beginSearch()
                    }
                    .buttonStyle(PanelIconButtonStyle(isSelected: model.isSearching))
                    .keyboardShortcut("f", modifiers: .command)
                    .help("Search everything in Tuck · ⌘F")
                }
                Button("Fold", systemImage: "chevron.up", action: model.fold)
                    .buttonStyle(PanelIconButtonStyle())
                    .help("Fold back · or swipe up")
            }
            .labelStyle(.iconOnly)
            .transition(.opacity)
        } else if !model.isStreamEmpty {
            LensCluster(model: model)
                .transition(.opacity)
                // ⌘F from the shallow fold opens the full one with its search, without a control here.
                .background {
                    Button("Search", action: model.beginSearch)
                        .keyboardShortcut("f", modifiers: .command)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
    }
}

/// What acts on everything at once, from a secondary click on the band.
struct FoldMenuItems: View {
    @ObservedObject var model: TuckModel

    var body: some View {
        Button("Choose Windows to Tuck…", systemImage: "checklist", action: model.openWindowPicker)
            .disabled(!model.accessibilityTrusted)
        SectionClearItems(model: model)
        Divider()
        Button("Settings…", systemImage: "gearshape", action: model.openSettings)
    }
}

/// The lenses, one small cluster right beside the notch: Windows, Files and Copied (while clipboard
/// history is on), each with how many it holds. One narrows the stream; chosen again, the stream is
/// everything again. Where a notch leaves too little room for the counts, the names stand alone and
/// the counts move to the tooltip; in a fold kept narrow by small tiles, each lens is its symbol.
struct LensCluster: View {
    @ObservedObject var model: TuckModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            cluster(.counted)
            cluster(.named)
            cluster(.symbol)
        }
    }

    private func cluster(_ form: LensChip.Form) -> some View {
        let counts = model.lensCounts
        return HStack(spacing: 0) {
            ForEach(model.lenses, id: \.self) { lens in
                LensChip(lens: lens, count: counts[lens] ?? 0, form: form,
                         isSelected: model.lens == lens) { model.toggleLens(lens) }
            }
        }
        .padding(2)
        .background(Theme.stone, in: .capsule)
        .fixedSize()
    }
}

struct LensChip: View {
    /// How much of itself a lens shows: its name and count, its name, or only its symbol.
    enum Form {
        case counted, named, symbol
    }

    let lens: StreamLens
    let count: Int
    let form: Form
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    static func symbol(_ lens: StreamLens) -> String {
        switch lens {
        case .windows: "macwindow"
        case .files: "doc"
        case .copied: "doc.on.clipboard"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if form == .symbol {
                    Image(systemName: Self.symbol(lens))
                        .frame(width: 14)
                } else {
                    Text(lens.title)
                }
                if form == .counted {
                    Text(count > 99 ? "99+" : "\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Theme.accent : Theme.secondaryText)
                }
            }
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(isSelected ? Theme.accent : Theme.primaryText)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(isSelected ? Theme.accentTint : (isHovering ? Theme.primaryText.opacity(0.07) : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(count == 0 && !isSelected)
        .opacity(count == 0 && !isSelected ? 0.45 : 1)
        .onHover { isHovering = $0 }
        .animation(Theme.quick, value: isHovering)
        .help(isSelected ? "Show everything again" : "Show only \(lens.title.lowercased()) · \(count)")
        .accessibilityLabel("\(lens.title), \(count)")
        .accessibilityHint(isSelected ? "Shows everything again" : "Shows only \(lens.title.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The lens a search in the full fold is narrowed to, in the band where "Everything in Tuck" otherwise
/// reads, with the cross that lets it go.
struct LensBadge: View {
    let lens: StreamLens
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(lens.title)
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Theme.accentTint, in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .help("Search everything in Tuck")
        .accessibilityLabel("Searching \(lens.title.lowercased()) only")
        .accessibilityHint("Searches everything in Tuck")
    }
}

// MARK: - Rows around the list

/// Under the shallow fold's strip when it holds more than a row: how many there are in all, which stays
/// true however far the strip is scrolled, and a click to unfold, as one more swipe down does.
struct MoreRow: View {
    @ObservedObject var model: TuckModel
    let total: Int
    @State private var isHovering = false

    var body: some View {
        Button { model.unfold() } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: StreamIcon.size)
                    .accessibilityHidden(true)
                Text(model.lens == nil ? "\(total) in all" : "Everything in Tuck")
                    .font(.panelSubtitle)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.secondaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .help("Show everything · or swipe down")
        .accessibilityLabel(model.lens == nil ? "Show all \(total)" : "Show everything in Tuck")
    }
}

/// A short line in place of the list: the empty cue, or a lens with nothing in it. Faint, centred, one
/// line: an empty Tuck never opens into an empty panel.
struct EmptyCue: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.panelSubtitle)
            .foregroundStyle(Theme.tertiaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .padding(.horizontal, 12)
    }
}

/// The open fold as a drop target: one blue-tinted field with the drop's glyph and what it will do,
/// "Drop file into Tuck", nothing more.
struct DropTargetOverlay: View {
    @ObservedObject var model: TuckModel
    let anchor: ScreenAnchor

    var body: some View {
        if model.isOverDropTarget {
            VStack(spacing: 0) {
                Color.clear.frame(height: anchor.kind == .notch ? anchor.notchSize.height : 0)
                Label(model.dragKind.label, systemImage: SurfaceView.dropSymbol(model.dragKind))
                    .font(.panelHeadline)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        // Opaque under the tint, so the rows beneath don't show through the words.
                        RoundedRectangle(cornerRadius: Theme.foldRadius - 6, style: .continuous).fill(Theme.paper)
                        RoundedRectangle(cornerRadius: Theme.foldRadius - 6, style: .continuous).fill(Theme.accentTint)
                    }
                    .padding(6)
                    // The first row's cards reach higher than the box; this hides their tops above it.
                    .background(Theme.paper)
            }
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Clear

/// Clearing every held item, asked inline. Tucked windows are never cleared; they stay until restored.
/// It says what leaves and what stays, and that a file Tuck saved from a drop is deleted with it.
struct ClearPromptView: View {
    @ObservedObject var model: TuckModel
    let plan: ClearPlan

    private var title: String {
        plan.itemCount == 1 ? "Clear the held item?" : "Clear all \(plan.itemCount) held items?"
    }

    private var detail: String {
        var text = "Links, text and file references leave Tuck. Your own files stay where they are; tucked windows stay too."
        let saved = plan.savedFiles.count
        if saved > 0 {
            text += saved == 1
                ? " 1 file Tuck saved from a drop will be deleted."
                : " \(saved) files Tuck saved from drops will be deleted."
        }
        return text
    }

    var body: some View {
        PromptCard(symbol: "trash", title: title, detail: detail, isDestructive: true, stacksChoices: false) {
            buttons
        }
    }

    /// Cancel first, as macOS orders a dialog's buttons. Clearing is destructive, so it is plain and
    /// never the prominent choice; its name says what it does.
    @ViewBuilder private var buttons: some View {
        Button("Cancel", action: model.cancelClear)
            .buttonStyle(PanelButtonStyle(size: .large))
            .keyboardShortcut(.cancelAction)
        switch plan.question {
        case .deletesSavedFiles:
            Button("Clear and Delete", action: model.confirmClear)
                .buttonStyle(PanelButtonStyle(role: .destructive, size: .large))
        default:
            Button("Clear", action: model.confirmClear)
                .buttonStyle(PanelButtonStyle(role: .destructive, size: .large))
        }
    }
}

// MARK: - Footer

/// The full fold's foot, set off from the tiles by a hairline the fold's width: Arrange windows at the
/// left for the window in front, Clear at the right, both quiet until pointed at. The list ends above
/// it, so its last row scrolls whole into view; Arrange's placements open under it.
struct FoldToolbar: View {
    @ObservedObject var model: TuckModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let arranges = ArrangeWindowsButton.isShown(for: model)
        let clears = SectionClearButton.isShown(for: model)
        if arranges || clears {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1 / displayScale)
                    .accessibilityHidden(true)
                HStack(spacing: 6) {
                    if arranges { ArrangeWindowsButton(model: model) }
                    Spacer(minLength: 0)
                    if clears { SectionClearButton(model: model) }
                }
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
                if arranges, ArrangeWindowsButton.isOpen(model) {
                    PlacementChooserView(model: model)
                        .padding(.top, 4)
                }
            }
            .transition(.opacity)
        }
    }
}

/// What the last action did, or that Tuck is tucked away, in a short line at the foot of the fold. It is
/// there only while it has something to say; how rows behave is in their tooltips and menus.
struct PanelFooter: View {
    @ObservedObject var model: TuckModel

    private var isTuckedAway: Bool {
        guard let screen = model.expandedScreenID else { return false }
        return model.isTuckedAway(on: screen)
    }

    var body: some View {
        Group {
            if let status = model.status {
                line(symbol: status.symbol, text: status.text)
            } else if isTuckedAway {
                line(symbol: "chevron.compact.down", text: "Tucked away · swipe down to bring it back")
            }
        }
        .animation(Theme.quick, value: model.status)
    }

    private func line(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
            Text(text)
                .lineLimit(1)
                .help(text)
            Spacer(minLength: 0)
        }
        .font(.panelSubtitle)
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 18)
        .frame(height: 26)
        .transition(.opacity)
    }
}
