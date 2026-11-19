import SwiftUI
import TuckCore

/// Search, only in the full fold and only once asked for (the magnifier in the band, ⌘F, or a chip), put
/// away with Esc. It searches the stream, within a lens when one came along from the shallow fold, and
/// reads kind and day words as filters: "screenshots yesterday", "links safari". Chips name the kinds the
/// stream holds, with how many: before a search they sit under the band on their own, and a click opens
/// the search with that kind filtered; during one they stay in the same line under the field, a click adds
/// that filter, and a chip that is on takes it out again. Return does what a click on the first match
/// does.
struct SearchBar: View {
    @ObservedObject var model: TuckModel
    let chips: [SearchChips.Chip]

    /// The chips for the fold as it is, as many as fit its width: what the search finds, or before one,
    /// everything in the stream.
    static func chips(for model: TuckModel, foldWidth: CGFloat) -> [SearchChips.Chip] {
        SearchChips.chips(categories: model.searchKinds, on: model.searchQuery.filterLabels,
                          width: Double(foldWidth - 20), measure: { Double($0.estimatedWidth) })
    }

    /// Before a search, a line of one kind says nothing, so it isn't shown.
    static func isShown(for model: TuckModel, chips: [SearchChips.Chip]) -> Bool {
        model.foldDepth == .full && model.windowPicker == nil && !model.isStreamEmpty
            && (model.isSearching || chips.count > 1)
    }

    /// An app filter's chip wears the app's icon, as the tiles' badges do.
    @MainActor private static func appIcon(for chip: SearchChips.Chip, in model: TuckModel) -> NSImage? {
        guard let app = model.searchQuery.apps.first(where: { $0.label == chip.label })?.app else { return nil }
        return ItemDetails.appIcon(bundleID: app.bundleID, name: app.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isSearching {
                SearchField(model: model)
                    .transition(Theme.reveal(edge: .top))
            }
            if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        SearchChip(chip: chip, icon: Self.appIcon(for: chip, in: model)) {
                            if model.isSearching {
                                model.toggleSearchFilter(word: chip.word, label: chip.label)
                            } else {
                                model.beginSearch(filtering: chip.word)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
        }
        .animation(Theme.quick, value: model.searchText.isEmpty)
        .animation(Theme.quick, value: model.isSearching)
    }
}

/// The field itself, there only while searching, so it takes the caret each time it opens.
private struct SearchField: View {
    @ObservedObject var model: TuckModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
            TextField("Search", text: $model.searchText, prompt: Text("Search, or try “images yesterday”"))
                .textFieldStyle(.plain)
                .font(.panelBody)
                .foregroundStyle(Theme.primaryText)
                .focused($focused)
                .onSubmit(model.openFirstMatch)
                .onExitCommand(perform: model.endSearch)
                .accessibilityLabel(model.lens.map { "Search \($0.title.lowercased())" } ?? "Search everything in Tuck")
            if !model.searchText.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") { model.searchText = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiaryText)
                    .help("Clear the search")
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            .strokeBorder(focused ? Theme.accent : Theme.hairline, lineWidth: focused ? 1.5 : 1))
        .onAppear { focused = true }
        // Opened by a click on the magnifier or a chip, the fold becomes key as this appears, and becoming
        // key takes the caret away again; asking once more, a moment later, leaves it in the field.
        .task {
            focused = true
            // Opened from a chip, the field already holds its word, and taking the caret selects it all: the
            // caret goes after it instead, so typing adds to the search rather than replacing the filter.
            guard !model.searchText.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(50))
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil)
        }
    }
}

extension SearchChips.Chip {
    /// What fits on one line, with the name and count measured in the chip's font: the padding, the
    /// name, a count and, once on, the cross that takes it out. An app's filter wears its icon too.
    var estimatedWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .callout)
        func measured(_ text: String) -> CGFloat { ceil((text as NSString).size(withAttributes: [.font: font]).width) }
        let icon: CGFloat = word.hasPrefix("from ") ? 20 : 0
        return 16 + icon + measured(label) + (count.map { 5 + measured("\($0)") + 2 } ?? 0) + (isOn ? 13 : 0)
    }
}

/// A filter as a quiet label: its name, and how many it holds in a fainter ink. Only the filter that is
/// on takes a ground, in the accent, with the cross that takes it out; the pointer gives the others a
/// stone one. An app's filter keeps the app's icon, the one picture in the line.
struct SearchChip: View {
    let chip: SearchChips.Chip
    var icon: NSImage?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .padding(.trailing, 4)
                        .accessibilityHidden(true)
                }
                Text(chip.label)
                    .foregroundStyle(chip.isOn ? Theme.accent : (isHovering ? Theme.primaryText : Theme.secondaryText))
                if let count = chip.count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(chip.isOn ? Theme.accent.opacity(0.8) : Theme.tertiaryText)
                        .padding(.leading, 5)
                }
                if chip.isOn {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.leading, 5)
                        .accessibilityHidden(true)
                }
            }
            .font(chip.isOn ? .panelControl : .panelSubtitle)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(chip.isOn ? Theme.accentTint : (isHovering ? Theme.chip : .clear)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovering = $0 }
        .animation(Theme.quick, value: chip.isOn)
        .help(chip.isOn ? "Take out \(chip.label.lowercased())" : "Show only \(chip.label.lowercased())")
        .accessibilityLabel(chip.label)
        .accessibilityValue(chip.count.map { $0 == 1 ? "1 item" : "\($0) items" } ?? "")
        .accessibilityHint(chip.isOn ? "Takes this filter out" : "Shows only these")
        .accessibilityAddTraits(chip.isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// In place of the list when a search finds nothing: says so, and where the words were found once the
/// kinds or the day typed are left out, with a click that leaves them out. A lens that found nothing has
/// already stepped aside when anything else matched.
struct NoMatches: View {
    @ObservedObject var model: TuckModel

    var body: some View {
        let hint = model.noMatchHint
        VStack(spacing: 6) {
            Label("No matches", systemImage: "magnifyingglass")
                .font(.panelTitle)
                .foregroundStyle(Theme.secondaryText)
            Text(hint.text)
                .font(.panelSubtitle)
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
            if let action = hint.action {
                Button(action.title, action: action.perform)
                    .buttonStyle(PanelButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}
