import SwiftUI
import TuckCore

/// Settings' panes, grouped in the sidebar: General and the notch, then what works in every app, then
/// what the panel offers, then Tuck itself.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, notch, windows, keyboard, mouse, rest, held, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .notch: "Notch"
        case .windows: "Windows"
        case .keyboard: "Keyboard"
        case .mouse: "Mouse"
        case .rest: "Rest"
        case .held: "Held"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .notch: "rectangle.topthird.inset.filled"
        case .windows: "macwindow"
        case .keyboard: "keyboard.fill"
        case .mouse: "computermouse.fill"
        case .rest: "moon.zzz.fill"
        case .held: "tray.full.fill"
        case .about: "info.circle.fill"
        }
    }

    /// One distinct tint per pane, like System Settings; grey for General, notch black for the notch, and
    /// Tuck Blue for About, whose tile is the app icon.
    var tint: Color {
        switch self {
        case .general: .gray
        case .about: Color(nsColor: TuckLogo.blue)
        case .notch: Color(white: 0.22)
        case .windows: .blue
        case .keyboard: .orange
        case .mouse: .teal
        case .rest: .indigo
        case .held: .pink
        }
    }

    /// A word beside the pane's name in its header.
    var badge: String? { self == .rest ? "Experimental" : nil }
}

/// Which pane Settings shows. The window controller holds it, so Tuck can turn Settings to a pane while
/// the window is already open.
final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane?

    init(pane: SettingsPane = .general) {
        self.pane = pane
    }
}

/// The Settings window's content: a sidebar of panes, like System Settings, and the chosen pane under a
/// header naming it. Created when the window opens and released with it.
struct SettingsView: View {
    /// Fixed and fairly narrow: settings read down, not across. The window adds its title bar.
    static let size = CGSize(width: 620, height: 540)

    // Not observed here: each pane observes what it shows, so a change redraws only that pane.
    let settings: SettingsStore
    let model: TuckModel
    let supportFolder: URL
    let onClearClipboard: () -> Void
    let onOpenTutorial: () -> Void
    let onUninstall: () -> Void
    @ObservedObject var navigation: SettingsNavigation

    init(settings: SettingsStore, model: TuckModel, supportFolder: URL, onClearClipboard: @escaping () -> Void,
         onOpenTutorial: @escaping () -> Void, onUninstall: @escaping () -> Void,
         navigation: SettingsNavigation = SettingsNavigation()) {
        self.settings = settings
        self.model = model
        self.supportFolder = supportFolder
        self.onClearClipboard = onClearClipboard
        self.onOpenTutorial = onOpenTutorial
        self.onUninstall = onUninstall
        self.navigation = navigation
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                Section {
                    SidebarRow(pane: .general)
                    SidebarRow(pane: .notch)
                }
                Section("Across apps") {
                    SidebarRow(pane: .windows)
                    SidebarRow(pane: .keyboard)
                    SidebarRow(pane: .mouse)
                }
                Section("In the panel") {
                    SidebarRow(pane: .rest)
                    SidebarRow(pane: .held)
                }
                Section("Tuck") {
                    SidebarRow(pane: .about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(150)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let shown = navigation.pane ?? .general
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    // In the title bar, level with the window buttons.
                    PaneHeader(pane: shown)
                        .frame(height: max(proxy.safeAreaInsets.top, PaneHeader.minimumHeight))
                    Divider().opacity(0.6)
                    detail(shown)
                }
                .ignoresSafeArea(.container, edges: .top)
            }
            // Read by VoiceOver and the Window menu; the title bar hides it.
            .navigationTitle(shown.title)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // Clicking empty sidebar space would leave nothing chosen.
        .onChange(of: navigation.pane) { old, new in
            if new == nil { navigation.pane = old }
        }
    }

    @ViewBuilder private func detail(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane(settings: settings, model: model, onOpenTutorial: onOpenTutorial)
        case .notch: NotchPane(settings: settings)
        case .windows: WindowsPane(settings: settings, model: model)
        case .keyboard: KeyboardPane(settings: settings)
        case .mouse: MousePane(settings: settings, model: model)
        case .rest: RestPane(settings: settings, model: model)
        case .held: HeldPane(settings: settings, model: model, onClear: onClearClipboard)
        case .about: AboutPane(supportFolder: supportFolder, onUninstall: onUninstall)
        }
    }
}

/// What you're looking at, in the title bar above the pane: its tile and its name.
struct PaneHeader: View {
    static let minimumHeight: CGFloat = 46

    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 9) {
            PaneTile(pane: pane, size: 24)
            Text(pane.title)
                .font(.system(size: 15, weight: .semibold))
            if let badge = pane.badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A pane's tinted symbol tile, for the sidebar and the header. About's is Tuck's own icon, the logo's line
/// in white, placed as on `TuckMark`, on a tile shaped like the others.
struct PaneTile: View {
    let pane: SettingsPane
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        glyph
            .frame(width: size, height: size)
            .background(shape.fill(pane.tint.gradient))
            .overlay(shape.strokeBorder(.white.opacity(0.15)))
            .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        if pane == .about {
            Image(nsImage: TuckLogo.markImage(side: size * 0.77, color: .white))
                .offset(y: -size * 0.013)
        } else {
            Image(systemName: pane.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// One pane in the sidebar: a small tinted tile, then its name.
struct SidebarRow: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title).font(.system(size: 12))
        } icon: {
            PaneTile(pane: pane, size: 19)
        }
        .padding(.vertical, 1)
        .tag(pane)
    }
}
