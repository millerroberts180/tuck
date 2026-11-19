import SwiftUI
import TuckCore

/// A compact list of apps, each row named by its app alone. One window is selected directly; an app
/// with several windows opens on a click to list their titles, as its row in the stream does, keeping
/// the picker short and free of window dimensions or repeated controls.
struct SuggestedWindowsView: View {
    @ObservedObject var model: TuckModel
    let picker: TuckModel.WindowPicker

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if picker.groups.isEmpty {
                if model.accessibilityTrusted {
                    EmptyCue(symbol: "macwindow.on.rectangle", text: "No other windows open on this desktop")
                } else {
                    HStack(spacing: 8) {
                        EmptyCue(symbol: "lock", text: "Listing windows needs \(AX.paneName)")
                        Button("Open Settings…", action: AX.openAccessibilitySettings)
                            .buttonStyle(PanelButtonStyle())
                    }
                    .padding(.trailing, 8)
                }
            }
            ForEach(picker.groups) { group in
                if group.windows.count == 1, let window = group.windows.first {
                    CandidateRow(window: window, app: group.app,
                                 isSelected: picker.selection.isSelected(window.id)) {
                        model.toggleCandidate(window.id)
                    }
                } else {
                    CandidateGroupRow(model: model, group: group, selection: picker.selection,
                                      isOpen: picker.isOpen(group))
                }
            }
        }
    }
}

private struct CandidateRow: View {
    let window: WindowCandidate
    let app: AppIdentity
    let isSelected: Bool
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                AppIconView(bundleID: app.bundleID)
                    .frame(width: 22, height: 22)
                Text(app.name)
                    .font(.panelBody)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(isHovering: isHovering, isActive: isSelected))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([app.name, window.pageTitle].compactMap { $0 }.joined(separator: ", "))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles this window for tucking")
        .accessibilityAddTraits(isSelected ? [.isToggle, .isSelected] : .isToggle)
    }
}

/// Several windows from one app: an app row that opens, on a click, to list each window to tick, then
/// a row that ticks them all. Closed, it says how many are ticked and keeps the tint while any are.
private struct CandidateGroupRow: View {
    @ObservedObject var model: TuckModel
    let group: CandidateGroup
    let selection: WindowSelection
    let isOpen: Bool
    @State private var isHovering = false

    private var selectedCount: Int { selection.count(in: group) }
    private var subtitle: String {
        selectedCount == 0 ? "\(group.windows.count) windows" : "\(selectedCount) of \(group.windows.count) selected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { model.toggleCandidateGroup(group) } label: {
                HStack(spacing: 10) {
                    AppIconView(bundleID: group.app.bundleID)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.app.name)
                            .font(.panelBody)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.panelMeta)
                            .foregroundStyle(Theme.secondaryText)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .animation(Theme.quick, value: selectedCount)
            }
            // Open, its window rows carry the tint; closed, the app row does while any are ticked.
            .buttonStyle(RowButtonStyle(isHovering: isHovering, isActive: !isOpen && selectedCount > 0))
            .onHover { isHovering = $0 }
            .help(isOpen ? "Hide \(group.app.name)'s windows" : "Show \(group.app.name)'s \(group.windows.count) windows")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(group.app.name), \(group.windows.count) windows")
            .accessibilityValue(isOpen ? "Expanded, \(subtitle)" : "Collapsed, \(subtitle)")
            .accessibilityHint(isOpen ? "Hides the windows" : "Shows each window to choose")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.toggleCandidateGroup(group) }
            .accessibilityActions {
                Button(selection.allSelected(in: group) ? "Deselect All" : "Select All \(group.windows.count) Windows") {
                    model.toggleCandidates(in: group)
                }
            }

            if isOpen {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(group.windows) { window in
                        CandidateWindowRow(window: window, isSelected: selection.isSelected(window.id)) {
                            model.toggleCandidate(window.id)
                        }
                    }
                    SelectAllRow(group: group, allSelected: selection.allSelected(in: group)) {
                        model.toggleCandidates(in: group)
                    }
                }
                .padding(.leading, Self.indent)
                .transition(Theme.reveal(edge: .top))
            }
        }
    }

    /// Lines a window's title up with its app's name above it (the icon and its gap).
    static let indent: CGFloat = 22 + 10
}

/// One window inside an opened app row, named by its title and ticked on a click.
private struct CandidateWindowRow: View {
    let window: WindowCandidate
    let isSelected: Bool
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Text(window.displayTitle)
                    .font(.panelBody)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "checkmark")
                    .font(.system(.callout, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(isSelected ? 1 : 0)
                    .scaleEffect(isSelected || Theme.reduceMotion ? 1 : 0.6)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .animation(Theme.quick, value: isSelected)
        }
        .buttonStyle(RowButtonStyle(isHovering: isHovering, isActive: isSelected))
        .onHover { isHovering = $0 }
        .help(window.displayTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.displayTitle)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Toggles this window for tucking")
        .accessibilityAddTraits(isSelected ? [.isToggle, .isSelected] : .isToggle)
    }
}

/// The last row of an opened app: ticks every window it lists, or unticks them once all are ticked. An
/// action row in blue.
private struct SelectAllRow: View {
    let group: CandidateGroup
    let allSelected: Bool
    let toggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: allSelected ? "minus.circle" : "checkmark.circle")
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(allSelected ? "Deselect All" : "Select All \(group.windows.count) Windows")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.panelControl)
            .foregroundStyle(Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .help(allSelected ? "Untick \(group.app.name)'s windows" : "Tick every \(group.app.name) window listed")
    }
}

/// Selection count and one clear action. Folding back (the chevron in the quiet line, or a swipe up)
/// cancels.
struct PickerActionBar: View {
    @ObservedObject var model: TuckModel
    let picker: TuckModel.WindowPicker

    var body: some View {
        HStack(spacing: 8) {
            Text(picker.selection.isEmpty ? "Choose windows" : "\(picker.selection.count) selected")
                .font(.panelSubtitle)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 6)
            Button(picker.selection.actionTitle, action: model.tuckSelectedWindows)
                .buttonStyle(PanelButtonStyle(role: .prominent))
                .disabled(picker.selection.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

/// A compact question asked inline, at the foot of the fold. Choices are listed with
/// the main one first; they are shown the way macOS orders a dialog's buttons, Cancel first and the main
/// action last, aligned to the trailing edge.
struct InlinePromptView: View {
    struct Choice {
        let title: String
        var emphasised = false
        var destructive = false
        var isCancel = false
        let action: () -> Void

        var role: PanelButtonStyle.Role { destructive ? .destructive : (emphasised ? .prominent : .normal) }
    }

    var symbol: String
    let title: String
    let detail: String
    let choices: [Choice]

    var body: some View {
        PromptCard(symbol: symbol, title: title, detail: detail,
                   isDestructive: choices.contains(where: \.destructive), stacksChoices: choices.count > 2) {
            // Side by side, Cancel comes first; stacked, it comes last.
            let ordered = choices.count > 2 ? choices : choices.reversed()
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, choice in
                if choice.isCancel {
                    Button(choice.title, action: choice.action)
                        .buttonStyle(PanelButtonStyle(role: choice.role, size: .large))
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button(choice.title, action: choice.action)
                        .buttonStyle(PanelButtonStyle(role: choice.role, size: .large))
                }
            }
        }
    }
}

/// A question asked inline, laid out as AirDrop asks one: a glyph, a bold title over a grey line, then
/// large capsules. Two choices share the width; three or more stack, as an alert stacks its buttons.
/// It sits on the panel itself, under a separator, with no card of its own.
struct PromptCard<Choices: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var isDestructive = false
    var stacksChoices = false
    @ViewBuilder let choices: Choices

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(.title2, weight: .medium))
                    .foregroundStyle(isDestructive ? Theme.secondaryText : Theme.accent)
                    .frame(width: RestAwareIcon.size)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.panelTitle)
                        .foregroundStyle(Theme.primaryText)
                    Text(detail)
                        .font(.panelSubtitle)
                        .foregroundStyle(Theme.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if stacksChoices {
                VStack(spacing: 6) { choices }
            } else {
                HStack(spacing: 8) { choices }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
