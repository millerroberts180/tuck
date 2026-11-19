import SwiftUI
import TuckCore

/// One window among an app's opened windows: its title alone. Click restores just this window;
/// Command-click places it.
struct ParkedWindowChildRow: View {
    @ObservedObject var model: TuckModel
    let window: ParkedWindow
    let isResting: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.activate(window: window) } label: {
                HStack(spacing: 8) {
                    Text(window.displayTitle)
                        .font(.panelBody)
                        .foregroundStyle(isResting ? Theme.secondaryText : Theme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle(isHovering: isHovering, isActive: model.chooser.isOpen(for: window.id)))
            .background(WindowRowFrame(windows: [window]))
            .help(WindowRowHelp.text(for: window, model: model))
            .onHover { inside in withAnimation(Theme.quick) { isHovering = inside } }
            .contextMenu {
                WindowMenuItems(model: model, window: window)
                Divider()
                Button("Forget Window", systemImage: "minus.circle", role: .destructive) { model.forgetWindow(window.id) }
            }
            .modifier(WindowRowAccessibility(model: model, window: window, isResting: isResting, includesApp: false))

            if model.chooser.isOpen(for: window.id) {
                PlacementChooserView(model: model)
            }
        }
    }
}

/// An app's tucked windows in the full fold, as one tile: its icon, name, the newest title and how
/// many. A single window restores on a click and is placed on a Command-click, as its row does; several
/// open their titles full width under the tile's row, each restored on its own.
struct WindowGroupTile: View {
    @ObservedObject var model: TuckModel
    let group: AppWindowGroup
    @State private var isHovering = false

    private var isResting: Bool { model.library.restState(for: group.app.bundleID).isResting }
    private var single: ParkedWindow? { group.isMultiWindow ? nil : group.windows.first }
    private var restoreAllTitle: String { "Restore All \(group.app.name) Windows" }

    /// Whether its section is open under the row: the titles, or a single window's placements.
    static func isOpen(_ group: AppWindowGroup, in model: TuckModel) -> Bool {
        if group.isMultiWindow { return model.windowGroupExpansion.isExpanded(group) }
        return group.windows.first.map { model.chooser.isOpen(for: $0.id) } ?? false
    }

    var body: some View {
        let isOpen = Self.isOpen(group, in: model)
        WindowsFace(group: group, isResting: isResting, isHovering: isHovering || isOpen)
            .modifier(TileChrome(isHovering: isHovering, isActive: isOpen))
            .background(WindowRowFrame(windows: group.windows, isTile: true))
            .onHover { isHovering = $0 }
            .onTapGesture(perform: open)
            .contextMenu { menu }
            .modifier(Accessibility(model: model, group: group, single: single, isResting: isResting, isOpen: isOpen,
                                    restoreAllTitle: restoreAllTitle))
    }

    private func open() {
        if let single { model.activate(window: single) } else { model.toggleWindowGroup(group) }
    }

    @ViewBuilder private var menu: some View {
        if let single {
            WindowMenuItems(model: model, window: single)
            RestMenuItems(model: model, app: group.app)
            Divider()
            Button("Forget Window", systemImage: "minus.circle", role: .destructive) { model.forgetWindow(single.id) }
        } else {
            Button(restoreAllTitle, systemImage: "arrow.uturn.backward") { model.restoreAllWindows(of: group.app) }
                .disabled(model.isRestoringAll)
            Divider()
            RestMenuItems(model: model, app: group.app)
        }
    }

    /// A single window reads and acts as its row does; several as the app's row does, with restoring all
    /// of them offered by name.
    private struct Accessibility: ViewModifier {
        let model: TuckModel
        let group: AppWindowGroup
        let single: ParkedWindow?
        let isResting: Bool
        let isOpen: Bool
        let restoreAllTitle: String

        func body(content: Content) -> some View {
            if let single {
                content
                    .help(WindowRowHelp.text(for: single, model: model))
                    .modifier(WindowRowAccessibility(model: model, window: single, isResting: isResting, includesApp: true))
            } else {
                content
                    .help(isOpen ? "Hide \(group.app.name)'s windows" : "Show \(group.app.name)'s \(group.windows.count) windows")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(group.app.name), \(group.windows.count) windows\(isResting ? ", rested" : "")")
                    .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
                    .accessibilityHint(isOpen ? "Hides the windows" : "Shows each window")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.toggleWindowGroup(group) }
                    .accessibilityActions {
                        if !model.isRestoringAll {
                            Button(restoreAllTitle) { model.restoreAllWindows(of: group.app) }
                        }
                    }
            }
        }
    }
}

/// An app's windows, opened full width under the row that holds its tile: each title restores just
/// that window, and Command-click places it.
struct WindowGroupContents: View {
    @ObservedObject var model: TuckModel
    let group: AppWindowGroup

    var body: some View {
        let isResting = model.library.restState(for: group.app.bundleID).isResting
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "macwindow")
                    .accessibilityHidden(true)
                Text("\(group.app.name)'s windows")
                Spacer(minLength: 0)
                Button("Restore All") { model.restoreAllWindows(of: group.app) }
                    .buttonStyle(PanelButtonStyle())
                    .disabled(model.isRestoringAll)
                Button("Hide") { model.toggleWindowGroup(group) }
                    .buttonStyle(PanelButtonStyle())
            }
            .font(.panelSubtitle)
            .foregroundStyle(Theme.secondaryText)
            .padding(.leading, 4)
            .padding(.bottom, 2)
            ForEach(group.windows) { window in
                ParkedWindowChildRow(model: model, window: window, isResting: isResting)
                    .opacity(model.arrivingWindowIDs.contains(window.id) ? 0 : 1)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A window row's tooltip: when it was tucked, the display when there is more than one, and what a click
/// does. Never its size: the list names windows, it doesn't measure them.
enum WindowRowHelp {
    static func text(for window: ParkedWindow, model: TuckModel) -> String {
        var parts = ["Tucked \(Theme.spokenRelative(window.tuckedAt))"]
        if model.hasMultipleDisplays, let display = window.displayName { parts.append("from \(display)") }
        return parts.joined(separator: " ") + " · click to restore · ⌘-click to place"
    }
}

/// Tells the panel where a row or tile is, for each window it stands for, so a tucked window's card can
/// land in it. An app row or tile stands for all its windows until it opens; then each title's row is
/// reported after it, and wins.
struct WindowRowFrame: View {
    let windows: [ParkedWindow]
    var isTile = false

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(Theme.panelSpace))
            let landing = isTile ? WindowLanding.tile(frame) : WindowLanding.row(frame)
            Color.clear.preference(key: WindowRowFramesKey.self,
                                   value: Dictionary(uniqueKeysWithValues: windows.map { ($0.id, landing) }))
        }
    }
}

/// The app icon, greyed while the app rests; the Rested tag beside the name carries the crescent.
struct RestAwareIcon: View {
    static let size: CGFloat = StreamIcon.size
    let bundleID: String
    let isResting: Bool

    var body: some View {
        AppIconView(bundleID: bundleID)
            .frame(width: Self.size, height: Self.size)
            .saturation(isResting ? 0 : 1)
            .opacity(isResting ? 0.55 : 1)
    }
}

/// Restore, and a way to the placement chooser that doesn't depend on Command-click (for the keyboard
/// and VoiceOver as much as anyone).
struct WindowMenuItems: View {
    let model: TuckModel
    let window: ParkedWindow

    var body: some View {
        Button("Restore", systemImage: "arrow.uturn.backward") { model.restore(windowID: window.id, placement: .original) }
        Button("Restore To…", systemImage: "rectangle.split.2x1") { model.showPlacements(for: window.id) }
    }
}

/// One VoiceOver element per window row: what it is, when it was tucked, and that it restores.
struct WindowRowAccessibility: ViewModifier {
    let model: TuckModel
    let window: ParkedWindow
    let isResting: Bool
    let includesApp: Bool

    func body(content: Content) -> some View {
        var label = includesApp ? "\(window.app.name), \(window.displayTitle)" : window.displayTitle
        if isResting && includesApp { label += ", rested" }
        return content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue("Tucked \(Theme.spokenRelative(window.tuckedAt))")
            .accessibilityHint("Restores the window")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.restore(windowID: window.id, placement: .original) }
    }
}

/// Context-menu detail for the app-level Rest command.
struct RestMenuItems: View {
    @ObservedObject var model: TuckModel
    let app: AppIdentity

    private var isResting: Bool { model.library.restState(for: app.bundleID).isResting }

    var body: some View {
        if isResting {
            Button("Wake \(app.name)", systemImage: "sun.max") { model.wake(app) }
        } else {
            Button("Rest \(app.name)…", systemImage: "moon.zzz") { model.requestRest(app) }
                .disabled(!canRest)
            Text(explanation)
        }
    }

    private var canRest: Bool {
        if case .unavailable = model.restEligibility(for: app) { return false }
        return true
    }

    private var explanation: String {
        switch model.restEligibility(for: app) {
        case .eligible, .needsStrongConfirmation:
            return model.restIsEnabled
                ? "Pauses the whole app to reduce CPU work; it stays in memory."
                : "Rest is off · choosing it asks to turn it on."
        case .unavailable(let reason): return reason
        }
    }
}

/// The chooser attached to a row, laid out like the window-tiling menu on a window's green button:
/// "Move & Resize" (halves and quarters) and "Fill & Arrange" (full, thirds, two thirds, centre) as
/// glyphs, then Original and Next Display by name. A highlighted glyph is named in its section's header,
/// in room that is always kept, so the chooser never changes height. Choosing applies immediately.
struct PlacementChooserView: View {
    @ObservedObject var model: TuckModel

    private static let moveAndResize: [Placement] = [.leftHalf, .rightHalf, .topLeft, .topRight, .bottomLeft, .bottomRight]
    private static let fillAndArrange: [Placement] = [.fullScreen, .leftThird, .centerThird, .rightThird,
                                                      .leftTwoThirds, .rightTwoThirds, .center]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            section("Move & Resize", Self.moveAndResize)
            section("Fill & Arrange", Self.fillAndArrange)
            HStack(spacing: 6) {
                named(.original, systemImage: "macwindow")
                named(.nextDisplay, systemImage: "rectangle.on.rectangle")
                    .disabled(!model.hasMultipleDisplays)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .transition(Theme.reveal(edge: .top))
    }

    private func section(_ title: String, _ placements: [Placement]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                // Names the highlighted glyph; the line is always there, so nothing moves.
                Text(placements.contains(model.chooser.highlighted) ? model.chooser.highlighted.title : " ")
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityHidden(true)
            }
            .font(.panelCaption)
            .foregroundStyle(Theme.secondaryText)
            .lineLimit(1)
            HStack(spacing: 4) {
                ForEach(placements) { placement in
                    let highlighted = model.chooser.highlighted == placement
                    choice(placement) {
                        PlacementGlyph(placement: placement, highlighted: highlighted)
                            .frame(width: 24, height: 16)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(highlighted ? Theme.accentTint : Theme.stone,
                                        in: .rect(cornerRadius: 7, style: .continuous))
                    }
                }
            }
        }
    }

    private func named(_ placement: Placement, systemImage: String) -> some View {
        Button(placement.title, systemImage: systemImage) { model.applyPlacement(placement) }
            .buttonStyle(PanelButtonStyle(isSelected: model.chooser.highlighted == placement))
            .onHover { inside in
                if inside { model.chooser.highlight(placement) }
            }
            .help(placement.title)
    }

    private func choice<Label: View>(_ placement: Placement, @ViewBuilder label: () -> Label) -> some View {
        Button {
            model.applyPlacement(placement)
        } label: {
            label().contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { inside in
            if inside { model.chooser.highlight(placement) }
        }
        .help(placement.title)
        .accessibilityLabel(placement.title)
    }
}

/// A tiny screen outline showing where the window will land.
struct PlacementGlyph: View {
    let placement: Placement
    let highlighted: Bool

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let fill = fillRect(in: bounds.insetBy(dx: 2.5, dy: 2.5))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Theme.primaryText.opacity(0.5), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.primaryText.opacity(highlighted ? 0.95 : 0.6))
                    .frame(width: fill.width, height: fill.height)
                    .offset(x: fill.minX, y: fill.minY)
                if placement == .nextDisplay {
                    Image(systemName: "arrow.right")
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(Theme.primaryText.opacity(highlighted ? 0.95 : 0.6))
                        .frame(width: proxy.size.width * 0.55, height: proxy.size.height)
                }
            }
        }
    }

    /// Glyph coordinates are flipped (y down), so "top" quarters start at minY.
    private func fillRect(in area: CGRect) -> CGRect {
        let third = area.width / 3
        let halfWidth = area.width / 2
        let halfHeight = area.height / 2
        let gap: CGFloat = 0.75
        switch placement {
        case .original:
            return CGRect(x: area.minX + area.width * 0.18, y: area.minY + area.height * 0.18,
                          width: area.width * 0.56, height: area.height * 0.62)
        case .leftHalf: return CGRect(x: area.minX, y: area.minY, width: halfWidth - gap, height: area.height)
        case .rightHalf: return CGRect(x: area.midX + gap, y: area.minY, width: halfWidth - gap, height: area.height)
        case .fullScreen: return area
        case .leftThird: return CGRect(x: area.minX, y: area.minY, width: third - gap, height: area.height)
        case .centerThird: return CGRect(x: area.minX + third + gap, y: area.minY, width: third - gap * 2, height: area.height)
        case .rightThird: return CGRect(x: area.maxX - third + gap, y: area.minY, width: third - gap, height: area.height)
        case .leftTwoThirds: return CGRect(x: area.minX, y: area.minY, width: third * 2 - gap, height: area.height)
        case .rightTwoThirds: return CGRect(x: area.minX + third + gap, y: area.minY, width: third * 2 - gap, height: area.height)
        case .topLeft: return CGRect(x: area.minX, y: area.minY, width: halfWidth - gap, height: halfHeight - gap)
        case .topRight: return CGRect(x: area.midX + gap, y: area.minY, width: halfWidth - gap, height: halfHeight - gap)
        case .bottomLeft: return CGRect(x: area.minX, y: area.midY + gap, width: halfWidth - gap, height: halfHeight - gap)
        case .bottomRight: return CGRect(x: area.midX + gap, y: area.midY + gap, width: halfWidth - gap, height: halfHeight - gap)
        case .center:
            return CGRect(x: area.minX + area.width * 0.25, y: area.minY + area.height * 0.22,
                          width: area.width * 0.5, height: area.height * 0.56)
        case .nextDisplay:
            return CGRect(x: area.maxX - area.width * 0.38, y: area.minY + area.height * 0.2,
                          width: area.width * 0.38, height: area.height * 0.6)
        }
    }
}

/// The window in front, tucked with one click: its app's icon and the word, on the left of the band
/// in the shallow fold. Blank while no window is in front, including the moment after a tuck, keeping
/// its place so nothing beside it moves. A secondary click offers all of that app's windows, or a choice.
struct TuckFrontButton: View {
    @ObservedObject var model: TuckModel

    var body: some View {
        if let front = model.frontWindow, model.accessibilityTrusted {
            Button(action: model.tuckShownWindow) {
                HStack(spacing: 6) {
                    AppIconView(bundleID: front.app.bundleID)
                        .frame(width: 16, height: 16)
                    Text("Tuck")
                    // The card flies up into the notch, so the glyph points up.
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(PanelButtonStyle())
            .help(front.title.isEmpty ? "Tuck \(front.app.name)'s window" : "Tuck “\(front.title)” from \(front.app.name)")
            .accessibilityLabel(front.title.isEmpty ? "Tuck \(front.app.name) window" : "Tuck \(front.title), \(front.app.name)")
            .contextMenu {
                Button("Tuck All \(front.app.name) Windows", systemImage: "rectangle.stack") {
                    model.tuckAllWindows(of: front.app)
                }
                Button("Choose Windows to Tuck…", systemImage: "checklist", action: model.openWindowPicker)
            }
            .transition(.opacity)
        } else if !model.accessibilityTrusted {
            Button("Allow Tuck", systemImage: "lock.fill", action: AX.openAccessibilitySettings)
                .buttonStyle(PanelButtonStyle())
                .help("Tuck needs \(AX.paneName) to tuck windows · opens System Settings")
        }
    }
}

/// Arrange windows, at the left of the full fold's toolbar: places the window in front on screen without
/// tucking it, its app named beside it. Quiet until pointed at; lit while its placements are open under
/// the toolbar (`FoldToolbar`).
struct ArrangeWindowsButton: View {
    @ObservedObject var model: TuckModel

    static func isShown(for model: TuckModel) -> Bool {
        model.foldDepth == .full && model.windowPicker == nil && model.frontWindow != nil && model.accessibilityTrusted
    }

    static func isOpen(_ model: TuckModel) -> Bool { model.chooser.isOpen(for: TuckModel.frontWindowChooserID) }

    var body: some View {
        if let front = model.frontWindow {
            let isOpen = Self.isOpen(model)
            Button(action: model.toggleFrontWindowChooser) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .medium))
                        .accessibilityHidden(true)
                    Text("Arrange windows")
                    AppIconView(bundleID: front.app.bundleID)
                        .frame(width: 14, height: 14)
                        .padding(.leading, 2)
                    Text(front.app.name)
                        .font(.panelSubtitle)
                        .foregroundStyle(isOpen ? Theme.accent : Theme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PanelButtonStyle(role: .quiet, isSelected: isOpen))
            .help("Place \(front.app.name)'s window on screen without tucking it")
            .accessibilityLabel("Arrange windows: \(front.app.name)")
            .accessibilityAddTraits(isOpen ? .isSelected : [])
        }
    }
}

struct AppIconView: View {
    let bundleID: String

    var body: some View {
        Image(nsImage: AppIcons.icon(for: bundleID))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityHidden(true)
    }
}
