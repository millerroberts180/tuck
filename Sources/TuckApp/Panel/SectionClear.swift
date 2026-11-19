import SwiftUI
import TuckCore

/// Clearing one section at a time, at the right of the full fold's toolbar: with a lens on, one quiet
/// button for that section; with none, a small Clear menu of all three. Windows are put back where they
/// were and never closed; held items and copies leave Tuck. Each asks first, and the question opens where
/// the button was. The shallow fold has no such button: it is a glance at the newest few, and its band's
/// secondary click offers the same three.
struct SectionClearButton: View {
    @ObservedObject var model: TuckModel

    /// Out of the way while a search, the picker or a section's question is open, and when there is
    /// nothing to clear.
    static func isShown(for model: TuckModel) -> Bool {
        guard model.foldDepth == .full, model.windowPicker == nil, !model.isSearching, model.clearPlan == nil,
              !model.restoreAllPrompt, !model.clearCopiedPrompt else { return false }
        if let lens = model.lens { return model.canClear(lens) }
        return model.lenses.contains(where: model.canClear)
    }

    var body: some View {
        if let lens = model.lens {
            Button(SectionClearItems.title(lens), systemImage: SectionClearItems.symbol(lens)) {
                model.requestClear(lens)
            }
            .buttonStyle(PanelButtonStyle(role: .quiet))
            .help(SectionClearItems.help(lens))
        } else {
            Menu {
                SectionClearItems(model: model)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                    Text("Clear")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(PanelButtonStyle(role: .quiet))
            .fixedSize()
            .help("Clear windows, files or copies · each asks first")
            .accessibilityLabel("Clear")
        }
    }
}

/// Clear Windows…, Clear Files… and Clear Copied… (while clipboard history is on), each greyed out while
/// its section is empty: in the Clear menu and in the band's secondary click alike.
struct SectionClearItems: View {
    @ObservedObject var model: TuckModel

    static func title(_ section: StreamLens) -> String { SectionClearing.title(section) + "…" }

    static func symbol(_ section: StreamLens) -> String {
        switch section {
        case .windows: "arrow.uturn.backward"
        case .files: "trash"
        case .copied: "doc.on.clipboard"
        }
    }

    static func help(_ section: StreamLens) -> String {
        switch section {
        case .windows: "Put every tucked window back where it was · none is closed"
        case .files: "Take every held item out of Tuck · your own files stay where they are"
        case .copied: "Empty clipboard history"
        }
    }

    var body: some View {
        ForEach(model.lenses, id: \.self) { section in
            Button(Self.title(section), systemImage: Self.symbol(section)) { model.requestClear(section) }
                .disabled(!model.canClear(section))
        }
    }
}

/// Clearing Windows, asked inline: every tucked window goes back where it was, one after another. None
/// is closed, so the question says "put back" rather than "clear".
struct RestoreAllPromptView: View {
    @ObservedObject var model: TuckModel

    var body: some View {
        let count = model.library.windows.count
        InlinePromptView(
            symbol: "arrow.uturn.backward.circle",
            title: SectionClearing.windowsQuestion(count: count),
            detail: SectionClearing.windowsDetail(count: count),
            choices: [
                .init(title: SectionClearing.windowsConfirmation(count: count), emphasised: true, action: model.confirmRestoreAll),
                .init(title: "Cancel", isCancel: true, action: model.cancelRestoreAll)
            ]
        )
    }
}

/// Clearing Copied, asked inline as clearing held items is: Cancel first, and the clear itself plain.
struct ClearCopiedPromptView: View {
    @ObservedObject var model: TuckModel

    var body: some View {
        PromptCard(symbol: "trash", title: SectionClearing.copiedQuestion(count: model.clipboard.entries.count),
                   detail: SectionClearing.copiedDetail, isDestructive: true, stacksChoices: false) {
            Button("Cancel", action: model.cancelClearCopied)
                .buttonStyle(PanelButtonStyle(size: .large))
                .keyboardShortcut(.cancelAction)
            Button("Clear", action: model.confirmClearCopied)
                .buttonStyle(PanelButtonStyle(role: .destructive, size: .large))
        }
    }
}
