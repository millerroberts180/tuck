#if DEBUG
import AppKit
import SwiftUI
import TuckCore

/// `Tuck --snapshot-panel <folder>` (debug builds): renders the open fold in each of its states and the
/// closed surface, in Light, Dark and both Increase Contrast appearances, to PNGs off screen, from a
/// throwaway in-memory library and stand-in window service. The person's own library, windows and
/// settings are never read or touched. Reduce Motion changes only how things move, never a still frame.
@MainActor
enum PanelSnapshots {
    private static let notch = CGSize(width: 185, height: 32)
    /// A surface's pending deposit timers still read its model after the shot. The app's model
    /// lives as long as the app, so each surface shot's model is kept until the run ends.
    private static var surfaceModels: [TuckModel] = []

    static func render(to folder: String) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // The surface is black, closed or open, and the fold on it is drawn dark either way; the closed
        // surface's shots check that what is drawn on it stays legible over both menu bars.
        let appearances: [(NSAppearance.Name, String)] = [(.aqua, "light"), (.darkAqua, "dark"),
                                                          (.accessibilityHighContrastAqua, "contrast-light"),
                                                          (.accessibilityHighContrastDarkAqua, "contrast-dark")]
        for (appearance, suffix) in appearances {
            snapshotsIncreaseContrast = suffix.hasPrefix("contrast")
            for scene in Scene.allCases {
                let model = makeModel(for: scene.fixture, scene: scene)
                scene.prepare(model)
                save(model, appearance: appearance, to: output.appendingPathComponent("panel-\(scene.rawValue)-\(suffix).png"))
            }
            // Cards two, three or five to a row, small, medium or large, shallow and full; a strip that is
            // narrower than the notch's band needs, and five large cards on a display too narrow for them.
            for (columns, size) in [(2, CardSize.medium), (3, .medium), (5, .medium), (3, .small), (3, .large),
                                    (2, .small), (5, .large)] {
                for full in [false, true] {
                    let model = makeModel(for: .crowded)
                    model.cardLayout = CardLayout(columns: columns, size: size)
                    model.expand(on: 1, via: .click)
                    if full { model.unfold() }
                    let name = "panel-cards-\(columns)\(size.rawValue.prefix(1))-\(full ? "full" : "peek")-\(suffix).png"
                    save(model, appearance: appearance, to: output.appendingPathComponent(name))
                }
            }
            let narrow = makeModel(for: .crowded)
            narrow.cardLayout = CardLayout(columns: 5, size: .large)
            narrow.expand(on: 1, via: .click)
            save(narrow, appearance: appearance, screenWidth: 1024,
                 to: output.appendingPathComponent("panel-cards-5l-narrow-display-\(suffix).png"))
            // The strip scrolled: part way, with more either side, and to its end.
            for (offset, name) in [(400.0, "middle"), (.greatestFiniteMagnitude, "end")] {
                let model = makeModel(for: .crowded)
                model.expand(on: 1, via: .click)
                save(model, appearance: appearance, stripOffset: offset,
                     to: output.appendingPathComponent("panel-cards-strip-\(name)-\(suffix).png"))
            }
            // The full fold scrolled to its last row, at three widths: the last row whole above the toolbar.
            for (columns, size) in [(3, CardSize.medium), (2, .small), (5, .large)] {
                let model = makeModel(for: .crowded)
                model.cardLayout = CardLayout(columns: columns, size: size)
                model.expand(on: 1, via: .click)
                model.unfold()
                save(model, appearance: appearance, listOffset: .greatestFiniteMagnitude,
                     to: output.appendingPathComponent("panel-cards-\(columns)\(size.rawValue.prefix(1))-full-end-\(suffix).png"))
            }
            // The arrow keys: on the fifth tile of the full fold, on the last (the list scrolls to it), and
            // along the shallow fold's strip past its first row (the strip scrolls to it).
            for (name, full, step) in [("full-keyboard", true, 4), ("full-keyboard-last", true, Int.max),
                                       ("peek-keyboard", false, 4)] {
                let model = makeModel(for: .kinds)
                model.expand(on: 1, via: .click)
                if full { model.unfold() }
                save(model, appearance: appearance, then: { model in
                    let stream = model.stream
                    model.tileCursor = stream[min(step, stream.count - 1)].id
                }, to: output.appendingPathComponent("panel-kinds-\(name)-\(suffix).png"))
            }
            // Every kind, as its tile, and wearing the time each was copied or added; small and large too.
            saveTileGallery(appearance: appearance, to: output.appendingPathComponent("gallery-tiles-\(suffix).png"))
            saveTileGallery(appearance: appearance, showsTime: true,
                            to: output.appendingPathComponent("gallery-tiles-times-\(suffix).png"))
            for size in [CardSize.small, .large] {
                saveTileGallery(appearance: appearance, size: size,
                                to: output.appendingPathComponent("gallery-tiles-\(size.rawValue)-\(suffix).png"))
                saveTileGallery(appearance: appearance, showsTime: true, size: size,
                                to: output.appendingPathComponent("gallery-tiles-times-\(size.rawValue)-\(suffix).png"))
            }
            // Every kind's line of details in the fold on small cards two to a row and large ones five, with and
            // without times, shallow and full.
            for (columns, size) in [(2, CardSize.small), (5, .large)] {
                for times in [false, true] {
                    for full in [false, true] {
                        let model = makeModel(for: .kinds)
                        model.cardLayout = CardLayout(columns: columns, size: size)
                        model.showsCopyTimes = times
                        model.expand(on: 1, via: .click)
                        if full { model.unfold() }
                        let name = "panel-kinds-\(columns)\(size.rawValue.prefix(1))\(times ? "-times" : "")"
                            + "-\(full ? "full" : "peek")-\(suffix).png"
                        save(model, appearance: appearance, to: output.appendingPathComponent(name))
                    }
                }
            }
            func surface(_ name: String, _ fixture: Fixture, kind: ScreenAnchor.Kind = .notch, menuBarHeight: CGFloat? = nil,
                         dropLevel: Int? = nil, dropKind: DropKind = .file, hovered: Bool = false) {
                let model = makeModel(for: fixture)
                model.dragStarted(kind: dropKind)
                saveSurface(model, kind: kind, menuBarHeight: menuBarHeight, dropLevel: dropLevel, hovered: hovered,
                            appearance: appearance, to: output.appendingPathComponent("surface-\(name)-\(suffix).png"))
            }
            // State 0: an empty Tuck is the bare notch; holding something (a little, or a great deal), the
            // faint mark with its card, and the grey dot.
            surface("state0-empty", .empty)
            surface("state0", .mixed)
            surface("state0-99plus", .huge)
            // A deposit landing on the closed notch: the card waits for it, then drops into the mark.
            let depositing = makeModel(for: .mixed)
            depositing.tuckFrontWindow()
            saveSurface(depositing, kind: .notch, appearance: appearance,
                        to: output.appendingPathComponent("surface-state0-deposit-\(suffix).png"))
            // Pointed at, nothing opens: holding something, the mark greets the pointer and lights, and the
            // dot gives way to the Tuck button; empty, "Drop into Tuck".
            surface("hover", .mixed, hovered: true)
            surface("hover-empty", .empty, hovered: true)
            // Without a notch: the bubble's lone mark, faint when empty, then on an external display's 24 pt
            // menu bar. Pointed at, the Tuck button takes the mark's place; empty, "Drop into Tuck".
            surface("bubble-empty", .empty, kind: .bubble)
            surface("bubble", .mixed, kind: .bubble)
            surface("bubble-external", .mixed, kind: .bubble, menuBarHeight: 24)
            surface("bubble-hover", .mixed, kind: .bubble, hovered: true)
            surface("bubble-hover-empty", .empty, kind: .bubble, hovered: true)
            surface("bubble-external-hover", .mixed, kind: .bubble, menuBarHeight: 24, hovered: true)
            // The one drop target, as a drag nears and once it is over, naming what the drag carries.
            for (kind, name) in [(ScreenAnchor.Kind.notch, "notch"), (.bubble, "bubble")] {
                for (level, state) in [(0, "near"), (DropApproach.levels, "over")] {
                    for (dropKind, label) in [(DropKind.file, "file"), (.link, "link"), (.text, "text")] {
                        surface("drop-\(name)-\(state)-\(label)", .mixed, kind: kind, dropLevel: level, dropKind: dropKind)
                    }
                }
            }
        }
        snapshotsIncreaseContrast = false
    }

    /// The closed surface's own layers, drawn into an image over a menu-bar strip, with the camera
    /// housing on top as the hardware hides what is under it.
    private static func saveSurface(_ model: TuckModel, kind: ScreenAnchor.Kind, menuBarHeight: CGFloat? = nil,
                                    dropLevel: Int? = nil, hovered: Bool = false,
                                    appearance: NSAppearance.Name, to url: URL) {
        let anchor = ScreenAnchor(kind: kind, screenID: 1, screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                  notchSize: kind == .notch ? notch : .zero, menuBarHeight: menuBarHeight ?? notch.height,
                                  centerX: 756)
        let size = CGSize(width: 360, height: dropLevel == nil && !hovered ? 60 : 90)
        surfaceModels.append(model)
        let surface = SurfaceView(anchor: anchor, model: model)
        surface.appearance = NSAppearance(named: appearance)
        surface.frame = CGRect(origin: .zero, size: size)
        surface.refreshCollapsedContent()
        if hovered, let enter = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
                                                       timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                       trackingNumber: 0, userData: nil) {
            surface.mouseEntered(with: enter)
            surface.finishMorphs()
        }
        surface.layoutSubtreeIfNeeded()
        surface.layout()
        if let dropLevel {
            surface.setDropPrompt(dropLevel)
            surface.finishMorphs()
            surface.layoutSubtreeIfNeeded()
            surface.layout()
        }
        guard let layer = surface.layer,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return }
        context.scaleBy(x: 2, y: 2)
        // A plain menu-bar strip in the chosen appearance, then the surface, flipped like the view.
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        if kind == .notch {
            let housing = CGRect(x: (size.width - notch.width) / 2, y: 0, width: notch.width, height: notch.height)
            context.addPath(CGPath(roundedRect: housing, cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.addRect(CGRect(x: housing.minX, y: 0, width: housing.width, height: 10))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
        }
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// What Tuck holds before a scene is set up.
    enum Fixture {
        /// Nothing at all.
        case empty
        /// One link.
        case one
        /// A window, a note and a link: the shallow fold's one row, full.
        case three
        /// Four Safari windows and nothing else.
        case safari
        /// Windows from four apps (Safari's two grouped), held text, files, music and a link, and two copies.
        case mixed
        /// `mixed` and more: windows from five more apps, twenty notes and forty copies, past fifty rows.
        case crowded
        /// A hundred and twenty notes, for a count past 99.
        case huge
        /// `mixed`'s windows and held items, and a copy of every kind.
        case kinds
    }

    enum Scene: String, CaseIterable {
        /// State 1, the shallow fold: empty, with the drop cue; one item; three, its row full; several
        /// windows from one app, closed and opened; a bit of everything; and past fifty, with the "more" row.
        case empty, one, three, safari, safariOpen, mixed, crowded
        /// State 1 through each lens, and the Windows lens with nothing tucked.
        case lensWindows, lensFiles, lensCopied, lensWindowsEmpty
        /// State 2, the full fold: everything, scrolling past fifty rows, searching (with and without a
        /// match), and Arrange windows opened.
        case full, fullCrowded, search, searchNoMatch, arrange
        /// Every kind: the shallow fold's newest rows, and through the Copied lens; the full fold's tiles;
        /// with a text being edited, a stack's files and Safari's windows opened under their row.
        case kinds, kindsCopied, fullKinds, editing, stackOpen, windowsOpen
        /// Searching every kind: chips for what "images" finds; "windows" typed through the Copied lens,
        /// which steps aside; and "links yesterday", found only on another day. And ⌘F through the Windows
        /// lens with no windows tucked, which searches everything instead.
        case searchChips, searchLens, searchElsewhere, searchFromEmptyLens
        /// ⌘-click on a tucked window: its placements, under its row.
        case placements
        /// Choosing windows to tuck, with one ticked, and with Finder's two windows listed.
        case picker, pickerGroupOpen
        /// The questions asked inline.
        case clearPrompt, restoreAll, restPrompt
        /// Accessibility turned off with windows tucked.
        case accessibilityLost
        /// The status line after a tuck.
        case status
        /// A drag over the open fold: the one target, saying what the drag carries.
        case dropFile, dropLink, dropText
        /// Clearing one section: the full fold's foot row through each lens (Everything's Clear menu is in
        /// `full`), Clear Windows' question with one and three tucked, and Clear Copied's.
        case clearRowWindows, clearRowFiles, clearRowCopied, restoreAllOne, restoreAllThree, clearCopiedPrompt
        /// A kind's chip clicked before any search (`fullKinds` shows the chips alone): the search opens with
        /// Links filtered.
        case chipClicked
        /// Every kind's tiles wearing the time each came, shallow and full; badge words searched, a type
        /// and a size; and an app's name searched, read as where things came from.
        case kindsTimes, fullKindsTimes, searchBadges, searchApp

        var fixture: Fixture {
            switch self {
            case .empty, .lensWindowsEmpty: return .empty
            case .one, .searchFromEmptyLens: return .one
            case .three: return .three
            case .safari, .safariOpen: return .safari
            case .crowded, .fullCrowded: return .crowded
            case .kinds, .kindsCopied, .fullKinds, .editing, .stackOpen, .windowsOpen, .searchChips, .searchLens,
                 .searchElsewhere, .chipClicked, .kindsTimes, .fullKindsTimes, .searchBadges, .searchApp:
                return .kinds
            default: return .mixed
            }
        }

        private func groups(_ model: TuckModel) -> [AppWindowGroup] { WindowGrouping.groups(for: model.library.windows) }

        func prepare(_ model: TuckModel) {
            model.expand(on: 1, via: .click)
            switch self {
            case .empty, .one, .three, .safari, .mixed, .crowded, .kinds: break
            case .kindsCopied: model.toggleLens(.copied)
            case .fullKinds: model.unfold()
            case .kindsTimes: model.showsCopyTimes = true
            case .fullKindsTimes:
                model.showsCopyTimes = true
                model.unfold()
            case .searchBadges:
                model.beginSearch()
                model.searchText = "md over 50 kb"
            case .searchApp:
                model.beginSearch()
                model.searchText = "safari links"
            case .editing:
                model.unfold()
                if let text = model.library.items.first(where: { $0.kind == .text }) { model.beginEditing(text) }
            case .stackOpen:
                model.unfold()
                if let stack = model.library.items.first(where: { $0.kind == .stack }) { model.toggleStack(stack) }
            case .windowsOpen:
                model.unfold()
                if let group = groups(model).first(where: \.isMultiWindow) { model.toggleWindowGroup(group) }
            case .searchChips:
                model.beginSearch()
                model.searchText = "images"
            case .searchLens:
                model.toggleLens(.copied)
                model.beginSearch()
                model.searchText = "windows"
            case .searchElsewhere:
                model.beginSearch()
                model.searchText = "links yesterday"
            case .searchFromEmptyLens:
                model.toggleLens(.windows)
                model.beginSearch()
            case .safariOpen:
                if let group = groups(model).first(where: \.isMultiWindow) { model.toggleWindowGroup(group) }
            case .lensWindows, .lensWindowsEmpty: model.toggleLens(.windows)
            case .lensFiles: model.toggleLens(.files)
            case .lensCopied: model.toggleLens(.copied)
            case .full, .fullCrowded: model.unfold()
            case .search:
                model.beginSearch()
                model.searchText = "safari"
            case .searchNoMatch:
                model.beginSearch()
                model.searchText = "invoices 2019"
            case .arrange:
                model.unfold()
                model.toggleFrontWindowChooser()
            case .placements:
                if let group = groups(model).first(where: \.isMultiWindow) {
                    model.toggleWindowGroup(group)
                    if let window = group.windows.first { model.showPlacements(for: window.id) }
                }
            // After opening, which reads the permission afresh.
            case .accessibilityLost: model.accessibilityChanged(trusted: false)
            case .picker:
                model.openWindowPicker()
                if let first = model.windowPicker?.candidates.first { model.toggleCandidate(first.id) }
            case .pickerGroupOpen:
                model.openWindowPicker()
                if let group = model.windowPicker?.groups.first(where: { $0.windows.count > 1 }) {
                    model.toggleCandidateGroup(group)
                    if let first = group.windows.first { model.toggleCandidate(first.id) }
                }
            case .clearPrompt: model.requestClear()
            case .restoreAll: model.requestRestoreAll()
            case .restPrompt:
                if let app = model.library.windows.last?.app { model.requestRest(app) }
            case .status: model.tuckFrontWindow()
            case .dropFile, .dropLink, .dropText:
                model.dragEntered(on: 1, kind: dropKind)
                model.updateDropTarget(isOver: true)
            case .clearRowWindows, .clearRowFiles, .clearRowCopied:
                // A lens comes along into the full fold with a search, and stays once the search is put away.
                model.toggleLens(self == .clearRowWindows ? .windows : self == .clearRowFiles ? .files : .copied)
                model.beginSearch()
                model.endSearch()
            case .restoreAllOne, .restoreAllThree: model.requestRestoreAll()
            case .clearCopiedPrompt: model.requestClearCopied()
            case .chipClicked:
                model.unfold()
                model.beginSearch(filtering: "links")
            }
        }

        private var dropKind: DropKind {
            switch self {
            case .dropLink: return .link
            case .dropText: return .text
            default: return .file
            }
        }
    }

    private static func makeModel(for fixture: Fixture, scene: Scene? = nil) -> TuckModel {
        let now = Date()
        var library = TuckLibrary()
        fill(&library, fixture: fixture, now: now)
        // Clear Windows asked with one window tucked, and with three.
        if let kept = scene == .restoreAllOne ? 1 : scene == .restoreAllThree ? 3 : nil {
            for window in library.windows.dropFirst(kept) { _ = library.removeWindow(id: window.id) }
        }
        let parking = MockWindowParkingService(front: FrontWindowInfo(
            app: AppIdentity(bundleID: "com.apple.Safari", name: "Safari"), title: "Apple – Start Page"))
        parking.candidates = candidates()
        var clipboard = ClipboardHistory(isEnabled: fixture == .mixed || fixture == .crowded)
        if fixture == .mixed || fixture == .crowded {
            clipboard.record(text: "Meeting notes for Thursday", sourceAppName: "Notes", now: now.addingTimeInterval(-1_200))
            clipboard.record(text: "https://example.com/report", sourceAppName: "Safari", now: now.addingTimeInterval(-30))
        }
        if fixture == .crowded {
            for index in 1...40 {
                clipboard.record(text: "Copied snippet \(index)", now: now.addingTimeInterval(-Double(index) * 90))
            }
        }
        if fixture == .kinds {
            clipboard = ClipboardHistory(isEnabled: true)
            TileSamples.record(into: &clipboard, assets: TileSamples.assets, now: now)
        }
        let model = TuckModel(parking: parking, rest: DisabledRestService(), opener: SimulatedItemOpener(),
                              pasteboard: SystemPasteboard(), haptics: RecordingHaptics(),
                              persistence: InMemoryLibraryPersistence(initial: library),
                              clipboard: clipboard, receivedFiles: nil)
        model.clipboardAssets = TileSamples.assets
        model.accessibilityChanged(trusted: true)
        return model
    }

    private static func fill(_ library: inout TuckLibrary, fixture: Fixture, now: Date) {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        func window(_ bundleID: String, _ name: String, _ title: String, minutes: Double) -> ParkedWindow {
            ParkedWindow(app: AppIdentity(bundleID: bundleID, name: name), title: title,
                         originalFrame: WindowFrame(x: 80, y: 80, width: 1280, height: 820),
                         displayName: "Built-in Display", tuckedAt: now.addingTimeInterval(-minutes * 60))
        }
        switch fixture {
        case .empty: return
        case .one:
            library.add(.link(URL(string: "https://developer.apple.com/design/human-interface-guidelines")!,
                              title: "Human Interface Guidelines", addedAt: now.addingTimeInterval(-300)))
            return
        case .three:
            library.park(window("com.apple.Notes", "Notes", "Trip planning", minutes: 40))
            library.add(.text("Pick up the prints before 6, and ask about the frame.", addedAt: now.addingTimeInterval(-900)))
            library.add(.link(URL(string: "https://developer.apple.com/design/human-interface-guidelines")!,
                              title: "Human Interface Guidelines", addedAt: now.addingTimeInterval(-300)))
            return
        case .safari:
            for (title, minutes) in [("Swift Testing – Apple Developer", 40.0), ("Human Interface Guidelines", 22),
                                     ("Apple – Start Page", 6), ("Release Notes – macOS 27", 2)] {
                library.park(window("com.apple.Safari", "Safari", title, minutes: minutes))
            }
            return
        case .huge:
            for index in 1...120 {
                library.add(.text("Note \(index)", addedAt: now.addingTimeInterval(-Double(index) * 20)))
            }
            return
        case .mixed, .crowded, .kinds: break
        }
        for window in [window("com.apple.Preview", "Preview", "Invoice-0423.pdf", minutes: 95),
                       window("com.apple.Notes", "Notes", "Trip planning", minutes: 40),
                       window("com.apple.Safari", "Safari", "Swift Testing – Apple Developer", minutes: 22),
                       window("com.apple.Safari", "Safari", "Human Interface Guidelines", minutes: 6),
                       window("com.apple.TextEdit", "TextEdit", "Draft reply.rtf", minutes: 2)] {
            library.park(window)
        }
        library.setRestState(.resting(since: now, process: ProcessIdentity(
            pid: 1, startTime: 0, executablePath: "/System/Applications/Preview.app", bundleID: "com.apple.Preview")),
                             for: "com.apple.Preview")
        let files = ["README.md", "Package.swift", "docs/architecture.md", "docs/decision-log.md"].map {
            repo.appendingPathComponent($0)
        }
        library.add(.text("Pick up the prints before 6, and ask about the frame.", addedAt: now.addingTimeInterval(-3_000)))
        library.add(.stack(files.suffix(3).map { HeldItem.file($0) }, addedAt: now.addingTimeInterval(-1_800)))
        library.add(.music(URL(string: "https://music.apple.com/album/1440818584")!, title: "Random Access Memories",
                           addedAt: now.addingTimeInterval(-900)))
        library.add(.link(URL(string: "https://developer.apple.com/design/human-interface-guidelines")!,
                          title: "Human Interface Guidelines", addedAt: now.addingTimeInterval(-300)))
        library.add(.file(files[0], addedAt: now.addingTimeInterval(-60)))
        guard fixture == .crowded else { return }
        let apps = [("com.apple.mail", "Mail"), ("com.apple.finder", "Finder"), ("com.apple.iCal", "Calendar"),
                    ("com.apple.Maps", "Maps"), ("com.apple.Music", "Music")]
        for (index, app) in apps.enumerated() {
            for copy in 1...2 {
                library.park(ParkedWindow(app: AppIdentity(bundleID: app.0, name: app.1), title: "\(app.1) window \(copy)",
                                          originalFrame: WindowFrame(x: 80, y: 80, width: 1280, height: 820),
                                          displayName: "Built-in Display",
                                          tuckedAt: now.addingTimeInterval(-Double(index * 2 + copy) * 400)))
            }
        }
        for index in 1...20 {
            library.add(.text("Note \(index)", addedAt: now.addingTimeInterval(-Double(index) * 200)))
        }
    }

    private static func candidates() -> [WindowCandidate] {
        // One process per app, as on a real Mac, so an app's windows group into one row.
        func candidate(_ id: String, _ bundleID: String, _ name: String, _ title: String, _ order: Int,
                       pid: Int32) -> WindowCandidate {
            WindowCandidate(id: id, app: AppIdentity(bundleID: bundleID, name: name), pid: pid, title: title,
                            frame: CGRect(x: 0, y: 0, width: 1200, height: 800), displayName: "Built-in Display",
                            subrole: "AXStandardWindow", stackOrder: order)
        }
        return [candidate("1", "com.apple.Safari", "Safari", "Apple – Start Page", 0, pid: 101),
                candidate("2", "com.apple.finder", "Finder", "Downloads", 1, pid: 102),
                candidate("3", "com.apple.finder", "Finder", "Documents", 2, pid: 102),
                candidate("4", "com.apple.Notes", "Notes", "Groceries", 3, pid: 103)]
    }

    /// Every tile face, three medium tiles to a row as the fold lays them out by default (or of another
    /// size), each named by its kind, with the first just clicked and the second under the pointer.
    private static func saveTileGallery(appearance: NSAppearance.Name, showsTime: Bool = false,
                                        size cardSize: CardSize = .medium, to url: URL) {
        let model = makeModel(for: .kinds)
        var tiles: [GalleryItem] = groups(model).map { GalleryItem(id: $0.id, name: "window", face: .windows($0)) }
        tiles += model.library.items.map { item in
            let content = TileContent(item: item)
            return GalleryItem(id: content.id.uuidString, name: content.category.title, face: .content(content))
        }
        tiles += model.clipboard.entries.map { entry in
            let content = TileContent(entry: entry, assets: TileSamples.assets)
            return GalleryItem(id: content.id.uuidString, name: content.category.title, face: .content(content))
        }
        // A click's feedback shows on a copy's tile, as the fold shows it.
        let used = tiles.first { if case .content = $0.face { true } else { false } }?.id
        let hovered = tiles.dropFirst().first?.id
        // The third wears the keyboard's ring, so the focus state is seen beside the pointer's.
        let focused = tiles.dropFirst(2).first?.id
        let gallery = TileGrid(items: tiles, cursor: focused) { tile in
            VStack(alignment: .leading, spacing: 3) {
                switch tile.face {
                case .windows(let group):
                    WindowsFace(group: group, isResting: model.library.restState(for: group.app.bundleID).isResting,
                                isHovering: hovered == tile.id)
                        .modifier(TileChrome(isHovering: hovered == tile.id))
                case .content(let content):
                    ContentTileView(content: content,
                                    feedback: used == tile.id ? TuckModel.RowFeedback(id: UUID(), message: "Copied",
                                                                                      symbol: "checkmark") : nil,
                                    isHovering: hovered == tile.id, showsTime: showsTime)
                }
                Text(tile.name)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
            }
        } detail: { _ in EmptyView() }
        let fold = FoldLayout(cards: CardLayout(size: cardSize), minimumWidth: 0, maximumWidth: .greatestFiniteMagnitude)
        let metrics = TileMetrics(fold)
        let rows = CGFloat((tiles.count + metrics.columns - 1) / metrics.columns)
        let size = CGSize(width: fold.width, height: rows * (metrics.height + 16 + Theme.tileSpacing) + 16)
        saveView(gallery.environment(\.tileMetrics, metrics).padding(8)
                    .frame(width: size.width, height: size.height, alignment: .top).background(Theme.paper),
                 size: size, appearance: appearance, to: url)
    }

    private static func groups(_ model: TuckModel) -> [AppWindowGroup] { WindowGrouping.groups(for: model.library.windows) }

    private struct GalleryItem: Identifiable {
        enum Face {
            case windows(AppWindowGroup)
            case content(TileContent)
        }

        let id: String
        let name: String
        let face: Face
    }

    private static func saveView(_ view: some View, size: CGSize, appearance: NSAppearance.Name, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered,
                              defer: false)
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top))
        window.contentView = host
        window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    /// The fold as it sits under a hardware notch: its black fill behind it (the surface draws it in the
    /// app, and draws the fold dark whatever the setting) and the camera housing drawn on top, over a
    /// plain desktop. `stripOffset` scrolls the shallow fold's strip that far before the shot, `listOffset`
    /// the full fold's list down, and `change` is done to the model once the fold is drawn.
    private static func save(_ model: TuckModel, appearance: NSAppearance.Name, screenWidth: CGFloat = 1512,
                             stripOffset: CGFloat? = nil, listOffset: CGFloat? = nil,
                             then change: ((TuckModel) -> Void)? = nil, to url: URL) {
        let anchor = ScreenAnchor(kind: .notch, screenID: 1, screenFrame: CGRect(x: 0, y: 0, width: screenWidth, height: 982),
                                  notchSize: notch, menuBarHeight: notch.height, centerX: screenWidth / 2)
        let width = SurfaceMetrics(anchor: anchor, cards: model.cardLayout).panelWidth
        var height: CGFloat = 640
        let root = SnapshotFrame(model: model, anchor: anchor, notch: notch, width: width) { height = $0 }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width + 40, height: 720),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let contrast = appearance == .accessibilityHighContrastAqua || appearance == .accessibilityHighContrastDarkAqua
        window.appearance = NSAppearance(named: contrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
        let host = NSHostingView(rootView: root)
        window.contentView = host
        window.setFrameOrigin(CGPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        if let stripOffset, let strip = scrollView(in: host, sideways: true), let document = strip.documentView {
            let end = document.frame.width - strip.contentView.bounds.width
            strip.contentView.scroll(to: CGPoint(x: min(stripOffset, end), y: strip.contentView.bounds.minY))
            strip.reflectScrolledClipView(strip.contentView)
        }
        if let listOffset, let list = scrollView(in: host, sideways: false), let document = list.documentView {
            let end = document.frame.height - list.contentView.bounds.height
            list.contentView.scroll(to: CGPoint(x: list.contentView.bounds.minX, y: min(listOffset, end)))
            list.reflectScrolledClipView(list.contentView)
        }
        // Something done once the fold is drawn, as a key pressed in it would be.
        change?(model)
        if stripOffset != nil || listOffset != nil || change != nil {
            for _ in 0..<10 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }
        let crop = CGRect(x: 0, y: 0, width: host.bounds.width, height: min(host.bounds.height, ceil(height) + 20))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsHigh) / host.bounds.height
        guard let cg = bitmap.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: crop.width * scale, height: crop.height * scale))
        else { return }
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }

    /// The strip's scroll view, the one whose content is wider than it, or the list's, taller than it.
    private static func scrollView(in view: NSView, sideways: Bool) -> NSScrollView? {
        if let scroll = view as? NSScrollView, let document = scroll.documentView,
           sideways ? document.frame.width > scroll.contentView.bounds.width + 1
                    : document.frame.height > scroll.contentView.bounds.height + 1 {
            return scroll
        }
        return view.subviews.lazy.compactMap { scrollView(in: $0, sideways: sideways) }.first
    }

    fileprivate struct SnapshotFrame: View {
        let model: TuckModel
        let anchor: ScreenAnchor
        let notch: CGSize
        let width: CGFloat
        let onHeight: (CGFloat) -> Void
        @SwiftUI.State private var height: CGFloat = 400

        private var fold: UnevenRoundedRectangle {
            UnevenRoundedRectangle(bottomLeadingRadius: Theme.foldRadius, bottomTrailingRadius: Theme.foldRadius,
                                   style: .continuous)
        }

        var body: some View {
            ZStack(alignment: .top) {
                Color(nsColor: .underPageBackgroundColor)
                fold
                    .fill(.black)
                    .frame(width: width, height: height)
                ExpandedPanelView(model: model, anchor: anchor) { value in
                    height = value
                    onHeight(value)
                }
                .frame(width: width, height: 700, alignment: .top)
                // To the fold's own height, as the surface's outline clips the panel in the app.
                .mask(alignment: .top) { fold.frame(width: width, height: height) }
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                    .fill(.black)
                    .frame(width: notch.width, height: notch.height)
            }
            .frame(width: width + 40, height: 720, alignment: .top)
        }
    }
}
#endif
