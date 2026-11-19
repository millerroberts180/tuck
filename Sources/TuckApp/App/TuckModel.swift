import AppKit
import SwiftUI
import TuckCore

/// Shared state for every display's surface. The AppKit overlay listens through `addObserver`; the
/// SwiftUI panel (alive only while expanded) observes the published properties.
final class TuckModel: ObservableObject {
    enum Trigger: Equatable {
        case click, gesture, drag, keyboard, menu, outside, deposit
    }

    struct RowFeedback: Equatable {
        let id: UUID
        let message: String
        let symbol: String
    }

    struct StatusLine: Equatable {
        let text: String
        let symbol: String
    }

    struct PlusOne: Equatable {
        let count: Int
        let token = UUID()
    }

    @Published private(set) var library: TuckLibrary {
        didSet {
            persistence.save(library)
            holdTerminationWhileResting()
            holdTerminationWhileOffScreen()
            windowGroupExpansion.prune(to: WindowGrouping.groups(for: library.windows))
            notifyObservers()
        }
    }
    /// Which multi-window app rows are open; all start closed and open only on a click.
    @Published private(set) var windowGroupExpansion = WindowGroupExpansion()
    /// Plays the upward deposit for windows just tucked; set by the overlay. `covered` is called with the
    /// windows whose cards are now on screen over them, so they can go; `arrived` as a card fills its
    /// window's row; and `landed` once every card is in, with whether any landed in the mark.
    var onWindowsTucked: ((_ windows: [ParkedWindow],
                           _ covered: @escaping (Set<UUID>) -> Void, _ arrived: @escaping (UUID) -> Void,
                           _ landed: @escaping (_ inMark: Bool) -> Void) -> Void)?
    /// Plays the way back for a window parked off screen; set by the overlay. Its card leaves its row or
    /// the mark and lands where the window will be (`frame`, AppKit coordinates), and `landed` is called
    /// as it lands, for the window to be put back under it.
    var onWindowRestoring: ((_ window: ParkedWindow, _ frame: CGRect, _ landed: @escaping () -> Void) -> Void)?
    @Published private(set) var expandedScreenID: CGDirectDisplayID? {
        didSet {
            guard oldValue != expandedScreenID else { return }
            // A question asked in the fold closes with it.
            if expandedScreenID == nil { clearCopiedPrompt = false }
            notifyObservers()
        }
    }
    /// Displays whose collapsed surface has been swiped up into the notch. Opening still works from
    /// there; closing returns to the tucked notch until a swipe down brings the surface back.
    @Published private(set) var tuckedAwayScreenIDs: Set<CGDirectDisplayID> = [] {
        didSet { if oldValue != tuckedAwayScreenIDs { notifyObservers() } }
    }
    @Published var chooser = PlacementChooserState()
    @Published private(set) var editingItemID: UUID?
    @Published var editingText = ""
    @Published private(set) var feedback: RowFeedback?
    @Published private(set) var status: StatusLine?
    /// Windows just tucked into the open panel whose card is still on its way to their row: a row of only
    /// these stays empty until its card arrives and opens out into it.
    @Published private(set) var arrivingWindowIDs: Set<UUID> = []
    @Published private(set) var plusOne: PlusOne? {
        didSet { notifyObservers() }
    }
    /// Counts refused actions, so the collapsed surface can give a small shake when the status line
    /// that explains it isn't showing.
    @Published private(set) var refusals = 0 {
        didSet { notifyObservers() }
    }
    /// A drag is over Tuck's one drop target: the surface lights its rim and the label says what will
    /// happen.
    @Published private(set) var isOverDropTarget = false {
        didSet { if oldValue != isOverDropTarget { notifyObservers() } }
    }
    @Published private(set) var isDragActive = false {
        didSet { if oldValue != isDragActive { notifyObservers() } }
    }
    /// What the drag in progress carries, for the drop target's words: file, link or text.
    @Published private(set) var dragKind: DropKind = .file {
        didSet { if oldValue != dragKind { notifyObservers() } }
    }
    @Published private(set) var clipboard: ClipboardHistory
    var onClipboardHistoryChanged: ((ClipboardHistory) -> Void)?
    /// Told when the person clears clipboard history, so copies set aside on disk go too.
    var onClipboardCleared: (() -> Void)?
    /// Learns more about each new copy (the words in an image, a song's tags), once.
    var clipboardEnricher: ClipboardEnricher?
    /// Where copied images, styling, page icons and maps are kept, for tiles to draw them.
    var clipboardAssets: ClipboardAssetStore?
    /// macOS is holding back what other apps copy until Tuck is allowed to paste from them.
    @Published var clipboardAccessHeldBack = false
    /// Tiles wear the time each was copied or added, from Settings.
    @Published var showsCopyTimes = false
    /// What the Tuck button names, read when the fold opens and kept current while it is open, and
    /// whether it is held blank after a tuck.
    @Published private(set) var frontWindowBar = FrontWindowBarState() {
        didSet {
            // Arrange's chooser belongs to the window it opened under: once another is named, or none, it closes.
            if frontWindowBar.shown?.isSameWindow(as: oldValue.shown) != true,
               chooser.isOpen(for: Self.frontWindowChooserID) { chooser.dismiss() }
        }
    }
    /// The window "Tuck" and "Arrange" act on. Nothing once it is tucked.
    var frontWindow: FrontWindowInfo? { frontWindowBar.shown }
    @Published private(set) var accessibilityTrusted = AX.isTrusted
    /// Accessibility is off while windows are tucked, so none of them can be brought back until it is
    /// allowed again. The panel says so for as long as it lasts.
    var accessibilityLostWithWindows: Bool { !accessibilityTrusted && !library.windows.isEmpty }
    @Published var revealedStackID: UUID?
    /// The tile the arrow keys are on in the open fold, by its entry's id: it wears the focus ring, and
    /// Return opens it. Nil while they are on none; it goes when the fold folds, closes or is narrowed.
    @Published var tileCursor: String?
    /// How deep the open fold is: the shallow fold it opens on, or the full one a further swipe (or More)
    /// unfolds. The surface sizes and routes swipes by it.
    @Published private(set) var foldDepth: FoldDepth = .peek {
        didSet { if oldValue != foldDepth { notifyObservers() } }
    }
    /// How many cards the fold shows in a row and how big, from Settings › Notch. The surface sizes the
    /// fold by it.
    @Published var cardLayout = CardLayout.standard {
        didSet { if oldValue != cardLayout { notifyObservers() } }
    }
    /// The lens the stream is narrowed to, if any. Tuck always opens on Everything (no lens).
    @Published private(set) var lens: StreamLens?
    /// What the full fold's search field holds, read into `searchQuery` as it is typed: kind and day words
    /// become chips, and the words left must all appear.
    @Published var searchText = "" {
        didSet { if searchText != oldValue { searchChanged() } }
    }
    @Published private(set) var searchQuery = SearchQuery()
    /// The full fold's search field is showing.
    @Published private(set) var isSearching = false {
        didSet { if !isSearching { searchApps = nil } }
    }
    /// The apps the history and the held items came from, gathered once when a search starts, so their
    /// names read as app filters.
    private(set) var searchApps: [SourceApp]?

    /// A Clear of everything held, waiting for the person's choice, shown inline in the fold.
    @Published private(set) var clearPlan: ClearPlan?

    /// The Suggested picker while it is open: the windows offered and which are ticked.
    struct WindowPicker: Equatable {
        var candidates: [WindowCandidate]
        var groups: [CandidateGroup]
        var selection = WindowSelection()
        /// Apps whose several windows are listed; all start closed and open only on a click.
        var openGroups: Set<Int32> = []

        func isOpen(_ group: CandidateGroup) -> Bool { openGroups.contains(group.id) }
    }
    @Published private(set) var windowPicker: WindowPicker? {
        // While it is open, a listed window closing or its app quitting drops that window at once.
        didSet {
            guard (windowPicker == nil) != (oldValue == nil) else { return }
            if let windowPicker {
                parking.watchListedWindows(windowPicker.candidates) { [weak self] in self?.pruneWindowPicker() }
            } else {
                parking.watchListedWindows([], onChange: nil)
            }
        }
    }
    /// "Restore all windows" (Clear Windows) is waiting to be confirmed.
    @Published private(set) var restoreAllPrompt = false
    /// Clear Copied is waiting to be confirmed.
    @Published private(set) var clearCopiedPrompt = false

    /// A Rest waiting for the person: the first-use explanation, or a stronger confirmation.
    struct RestPrompt: Equatable {
        enum Step: Equatable { case turnOn, explain, confirmBusy(String) }
        let app: AppIdentity
        let step: Step
    }
    @Published private(set) var restPrompt: RestPrompt?
    @Published private(set) var isReceiving = false

    /// Chooser key for the front window, which has no parked-window row of its own.
    static let frontWindowChooserID = UUID()

    /// Each tucked window's row or tile in the stream, for its card to land in, in panel coordinates (down).
    var windowLandings: [UUID: WindowLanding] = [:]
    /// Where the stream's list sits in the panel, in panel coordinates.
    var listFrame: CGRect = .zero
    /// The panel list's frame in panel coordinates while its content is long enough to scroll; swipes
    /// that start over it scroll the list instead of moving the panel.
    var scrollableListFrame: CGRect?
    /// The shallow fold's strip in panel coordinates while it holds more than it shows; sideways swipes
    /// that start over it scroll it.
    var stripFrame: CGRect?
    var requestKeyFocus: ((CGDirectDisplayID) -> Void)?
    var openSettingsHandler: (() -> Void)?
    var visibleFrameProvider: ((CGDirectDisplayID) -> CGRect?)?
    var displayExists: ((String) -> Bool)?

    private(set) var lastTrigger: Trigger?
    private let parking: WindowParkingService
    private let rest: RestService
    private let opener: HeldItemOpening
    private let pasteboard: PasteboardWriting
    private let haptics: HapticFeedbackProviding
    private let persistence: LibraryPersistence
    private let receivedFiles: ReceivedFileStore?
    private let paster: KeystrokePasting
    private var observers: [() -> Void] = []
    private var feedbackWork: DispatchWorkItem?
    private var statusWork: DispatchWorkItem?
    private var dragEndWork: DispatchWorkItem?
    /// A copy waiting to move to the top of the history, once a second click can no longer land on it.
    private var pendingTouch: (id: UUID, work: DispatchWorkItem)?

    init(
        parking: WindowParkingService,
        rest: RestService,
        opener: HeldItemOpening,
        pasteboard: PasteboardWriting,
        haptics: HapticFeedbackProviding,
        persistence: LibraryPersistence,
        clipboard: ClipboardHistory,
        receivedFiles: ReceivedFileStore?,
        paster: KeystrokePasting = NoPaster()
    ) {
        self.parking = parking
        self.rest = rest
        self.opener = opener
        self.pasteboard = pasteboard
        self.haptics = haptics
        self.persistence = persistence
        self.clipboard = clipboard
        self.receivedFiles = receivedFiles
        self.paster = paster
        self.library = persistence.load() ?? TuckLibrary()
        // Rows still parked off screen (Tuck stopped without minimising them) hold termination at once.
        holdTerminationWhileOffScreen()
    }

    // MARK: Observation for AppKit

    func addObserver(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    private func notifyObservers() {
        observers.forEach { $0() }
    }

    // MARK: Settings

    func apply(settings: SettingsStore) {
        haptics.isEnabled = settings.hapticsEnabled
        // Turning Rest off wakes anything it paused; waking needs no permission from the setting.
        if !settings.restEnabled { wakeAllRestedApps() }
        clipboard.isEnabled = settings.clipboardHistoryEnabled
        // Turning clipboard history off takes the Copied lens away with it.
        if !clipboard.isEnabled && lens == .copied { lens = nil }
        clipboard.retention = settings.clipboardRetention
        clipboard.prune()
        clipboardEnricher?.readsTextInImages = settings.clipboardReadsImageText
        showsCopyTimes = settings.showsCopyTimes
        onClipboardHistoryChanged?(clipboard)
        cardLayout = settings.cardLayout
    }

    func openSettings() {
        collapse(via: .menu)
        openSettingsHandler?()
    }

    // MARK: Expansion

    func isExpanded(on screenID: CGDirectDisplayID) -> Bool { expandedScreenID == screenID }

    func toggle(on screenID: CGDirectDisplayID, via trigger: Trigger) {
        if isExpanded(on: screenID) {
            collapse(via: trigger)
        } else {
            expand(on: screenID, via: trigger)
        }
    }

    /// Opens the shallow fold on Everything: no lens, no search.
    func expand(on screenID: CGDirectDisplayID, via trigger: Trigger) {
        guard expandedScreenID != screenID else { return }
        lastTrigger = trigger
        refreshOnOpen()
        followFrontWindow()
        foldDepth = .peek
        lens = nil
        searchText = ""
        isSearching = false
        expandedScreenID = screenID
        // Opened from the keyboard or the menu bar, the panel takes key focus so Escape closes it; the
        // app in front stays active and gets its focus back when the panel closes.
        if trigger == .keyboard || trigger == .menu { requestKeyFocus?(screenID) }
    }

    func collapse(via trigger: Trigger) {
        guard expandedScreenID != nil else { return }
        if editingItemID != nil { commitEdit() }
        lastTrigger = trigger
        chooser.dismiss()
        revealedStackID = nil
        isOverDropTarget = false
        clearPlan = nil
        windowPicker = nil
        restoreAllPrompt = false
        restPrompt = nil
        isSearching = false
        tileCursor = nil
        expandedScreenID = nil
        // Closed, nothing reads the window in front until the panel opens again.
        parking.watchFrontWindow(nil)
    }

    // MARK: Fold

    /// Opens the full fold: the whole stream, search and Arrange windows. The lens beside the notch
    /// recedes, so the full fold shows everything, unless a search was asked for from inside a lens.
    /// However it was opened (a swipe, "N more", the picker, search), the panel takes key focus, as the
    /// keyboard's fold does: its list scrolls straight away, without a click in it first, and Escape
    /// folds it. The app in front stays active and gets its focus back when the panel closes.
    func unfold(keepingLens: Bool = false) {
        guard let screen = expandedScreenID, foldDepth != .full else { return }
        chooser.dismiss()
        tileCursor = nil
        withAnimation(Theme.fold) {
            foldDepth = .full
            if !keepingLens { lens = nil }
        }
        requestKeyFocus?(screen)
    }

    /// Back to the shallow fold; a search in progress is dropped with the search field.
    func fold() {
        guard foldDepth == .full else { return }
        chooser.dismiss()
        windowPicker = nil
        tileCursor = nil
        withAnimation(Theme.fold) {
            foldDepth = .peek
            isSearching = false
            searchText = ""
        }
    }

    /// A lens narrows the stream; choosing it again goes back to Everything.
    func toggleLens(_ choice: StreamLens) {
        chooser.dismiss()
        tileCursor = nil
        withAnimation(Theme.quick) { lens = lens == choice ? nil : choice }
    }

    /// The lenses offered beside the notch: Copied only while clipboard history is on.
    var lenses: [StreamLens] { StreamLens.available(includingCopied: clipboard.isEnabled) }

    /// Clipboard history as the stream shows it: nothing while it is off.
    private var copiedEntries: [ClipboardEntry] { clipboard.isEnabled ? clipboard.entries : [] }

    /// The stream as the fold shows it now: Everything, or the lens, narrowed by the search.
    var stream: [StreamEntry] {
        TuckStream.entries(windows: library.windows, items: library.items, copied: copiedEntries, lens: lens,
                           query: foldDepth == .full ? searchQuery : SearchQuery(), category: ContentKinds.category(of:),
                           size: FileSizes.byteCount(of:))
    }

    /// How many rows each lens holds, for the counts beside the notch.
    var lensCounts: [StreamLens: Int] {
        TuckStream.counts(windows: library.windows, items: library.items, copied: copiedEntries)
    }

    /// Nothing in Tuck: no windows, no held items, no copied text to show.
    var isStreamEmpty: Bool { library.isEmpty && copiedEntries.isEmpty }

    /// Cheap checks done once per open rather than continuously: which window is in front (followed from
    /// then on by `followFrontWindow`), whether Accessibility is allowed, and whether any held file has
    /// been moved or deleted since it was dropped.
    private func refreshOnOpen() {
        updateFrontWindowBar(animated: false) { $0.show(parking.frontWindow()) }
        accessibilityTrusted = AX.isTrusted
        var updated = library
        if FileReferences.reconcile(&updated) > 0 || updated != library { library = updated }
    }

    func accessibilityChanged(trusted: Bool) {
        let wasTrusted = accessibilityTrusted
        accessibilityTrusted = trusted
        if wasTrusted, !trusted, !library.windows.isEmpty {
            // Turned off with windows tucked: they are out of reach until it is allowed again. The notch
            // shakes and the status line says so now; the panel keeps saying it until then.
            refuse(Self.accessibilityLost, symbol: "lock")
        }
        guard expandedScreenID != nil else { return }
        // Allowed while the panel is open: the watcher starts again so it can see windows, not just apps.
        parking.watchFrontWindow(nil)
        followFrontWindow()
        refreshFrontWindowBar()
    }

    // MARK: Following the window in front

    /// While the panel is open what the fold names follows the window in front: switches, closes and renames, and
    /// tucks and restores by any path, each told by the parking service's watcher rather than asked for.
    private func followFrontWindow() {
        parking.watchFrontWindow { [weak self] front, byPerson in self?.frontWindowChanged(to: front, byPerson: byPerson) }
    }

    private func frontWindowChanged(to front: FrontWindowInfo?, byPerson: Bool) {
        guard expandedScreenID != nil else { return }
        updateFrontWindowBar { $0.frontChanged(to: front, byPerson: byPerson) }
        pruneWindowPicker()
    }

    /// Reads the window in front again and names it, letting go of a blank held since a tuck.
    private func refreshFrontWindowBar() {
        guard expandedScreenID != nil else { return }
        let front = parking.frontWindow()
        updateFrontWindowBar { $0.show(front) }
    }

    /// Publishes a change to what the fold names only when there is one, so a rename or a burst that changed nothing
    /// redraws nothing.
    private func updateFrontWindowBar(animated: Bool = true, _ change: (inout FrontWindowBarState) -> Void) {
        var bar = frontWindowBar
        change(&bar)
        guard bar != frontWindowBar else { return }
        if animated {
            withAnimation(Theme.quick) { frontWindowBar = bar }
        } else {
            frontWindowBar = bar
        }
    }

    /// Drops from the open picker any window that has closed, lost its app or been tucked since it was
    /// listed, with its tick, so the picker offers only what it would tuck. Asked when a listed window
    /// closes or its app quits, when the window in front changes, and after a tuck.
    private func pruneWindowPicker() {
        guard var picker = windowPicker else { return }
        let listed = parking.stillListed(picker.candidates)
        guard listed.count < picker.candidates.count else { return }
        picker.candidates = listed
        picker.groups = CandidatePolicy.groupedByApp(listed)
        picker.selection.keepOnly(listed)
        picker.openGroups.formIntersection(picker.groups.map(\.id))
        withAnimation(Theme.quick) { windowPicker = picker }
    }

    /// A tactile tick with the person's setting and Tuck's pacing: a drag crossing into the drop target,
    /// a deposit, a placement snapping. Setup's practice notch plays the same.
    func performHaptic(_ event: HapticEvent) {
        haptics.perform(event)
    }

    func isTuckedAway(on screenID: CGDirectDisplayID) -> Bool { tuckedAwayScreenIDs.contains(screenID) }

    func setTuckedAway(_ tucked: Bool, on screenID: CGDirectDisplayID) {
        guard tucked != isTuckedAway(on: screenID) else { return }
        if tucked { tuckedAwayScreenIDs.insert(screenID) } else { tuckedAwayScreenIDs.remove(screenID) }
    }

    /// Brings every tucked surface back, from the menu-bar item.
    func revealEverywhere() {
        tuckedAwayScreenIDs.removeAll()
    }

    /// Tucks every surface away, from the menu-bar item: the same as swiping up on each collapsed surface.
    func tuckAwayEverywhere(_ screenIDs: [CGDirectDisplayID]) {
        if expandedScreenID != nil { collapse(via: .menu) }
        tuckedAwayScreenIDs.formUnion(screenIDs)
    }

    func toggleWindowGroup(_ group: AppWindowGroup) {
        withAnimation(Theme.quick) { windowGroupExpansion.toggle(group) }
    }

    func handleSwipe(_ action: SwipeGestureTracker.Action, on screenID: CGDirectDisplayID) {
        switch action {
        case .tuckAway: setTuckedAway(true, on: screenID)
        case .reveal: setTuckedAway(false, on: screenID)
        case .expand: expand(on: screenID, via: .gesture)
        case .collapse: collapse(via: .gesture)
        case .unfold: unfold()
        case .fold: fold()
        }
    }

    // MARK: Clear

    /// Starts clearing everything held. Tucked windows are never cleared: they stay until restored.
    /// Nothing held means nothing to ask; anything else waits for an answer to the question its plan
    /// raises.
    func requestClear() {
        let plan = currentClearPlan
        guard plan.question != .none else { return }
        chooser.dismiss()
        withAnimation(Theme.quick) {
            restoreAllPrompt = false
            clearCopiedPrompt = false
            clearPlan = plan
        }
    }

    func cancelClear() {
        withAnimation(Theme.quick) { clearPlan = nil }
    }

    /// What clearing every held item would involve right now. Windows are not part of it.
    private var currentClearPlan: ClearPlan {
        ClearPlan(items: library.items, isSavedByTuck: isSavedByTuck)
    }

    /// Clears after the person confirmed. Asks again instead if what clearing would do has changed since
    /// the question was asked (a saved file would now be deleted, say).
    func confirmClear() {
        guard let asked = clearPlan?.question else { return }
        let plan = currentClearPlan
        guard plan.question == asked || plan.question == .none else {
            withAnimation(Theme.quick) { clearPlan = plan }
            return
        }
        var updated = library
        let removed = updated.removeAllItems()
        // Only files Tuck itself saved are deleted; references to the person's files are just dropped.
        let saved = removed.flatMap(\.fileURLs).filter(isSavedByTuck)
        withAnimation(Theme.settle) {
            library = updated
            clearPlan = nil
        }
        if let receivedFiles { saved.forEach { receivedFiles.discard($0) } }
        let deleted = saved.isEmpty ? "" : saved.count == 1 ? " · 1 saved copy deleted" : " · \(saved.count) saved copies deleted"
        showStatus("Cleared · your files untouched\(deleted)", symbol: "checkmark.circle")
    }

    /// Clear Copied, asked first as the other sections' Clear is. Settings clears the history its own way.
    func requestClearCopied() {
        guard canClear(.copied) else { return }
        chooser.dismiss()
        withAnimation(Theme.quick) {
            clearPlan = nil
            restoreAllPrompt = false
            clearCopiedPrompt = true
        }
    }

    func cancelClearCopied() {
        withAnimation(Theme.quick) { clearCopiedPrompt = false }
    }

    func confirmClearCopied() {
        guard clearCopiedPrompt else { return }
        withAnimation(Theme.quick) { clearCopiedPrompt = false }
        clearClipboard()
    }

    /// Whether a section has anything to clear: a window to put back, a held item, a copy.
    func canClear(_ section: StreamLens) -> Bool {
        switch section {
        case .windows: canRestoreAll && !isRestoringAll
        case .files: !library.items.isEmpty
        case .copied: clipboard.isEnabled && !clipboard.entries.isEmpty
        }
    }

    /// A section's Clear. Windows are put back where they were, never closed; held items and copies leave
    /// Tuck. Each asks first, at the foot of the fold, in place of any other section's question.
    func requestClear(_ section: StreamLens) {
        switch section {
        case .windows: requestRestoreAll()
        case .files: requestClear()
        case .copied: requestClearCopied()
        }
    }

    private func isSavedByTuck(_ url: URL) -> Bool {
        receivedFiles?.owns(url) ?? false
    }

    /// Whether removing this item deletes its file: a copy Tuck saved itself, not one of the person's.
    func isSavedCopy(_ item: HeldItem) -> Bool {
        let urls = item.fileURLs
        return !urls.isEmpty && urls.contains(where: isSavedByTuck)
    }

    // MARK: Choosing windows to tuck

    /// Opens the Suggested picker with a fresh, conservative list of open windows. Nothing is ticked. It
    /// opens in the full fold, which has key focus so its list scrolls at once (`unfold`).
    func openWindowPicker() {
        chooser.dismiss()
        clearPlan = nil
        if foldDepth != .full {
            unfold()
        } else if let screen = expandedScreenID {
            requestKeyFocus?(screen)
        }
        let candidates = CandidatePolicy.suggestions(from: parking.windowCandidates())
        withAnimation(Theme.fold) {
            windowPicker = WindowPicker(candidates: candidates, groups: CandidatePolicy.groupedByApp(candidates))
        }
    }

    func closeWindowPicker() {
        withAnimation(Theme.fold) { windowPicker = nil }
    }

    func toggleCandidate(_ id: String) {
        windowPicker?.selection.toggle(id)
    }

    func toggleCandidates(in group: CandidateGroup) {
        windowPicker?.selection.toggleAll(in: group)
    }

    /// Opens or closes the list of an app's windows in the picker, as an app row in the stream does.
    func toggleCandidateGroup(_ group: CandidateGroup) {
        guard var picker = windowPicker else { return }
        if picker.isOpen(group) { picker.openGroups.remove(group.id) } else { picker.openGroups.insert(group.id) }
        withAnimation(Theme.quick) { windowPicker = picker }
    }

    /// Tucks exactly the ticked windows, each as its own row.
    func tuckSelectedWindows() {
        guard let picker = windowPicker else { return }
        let chosen = picker.selection.chosen(from: picker.candidates)
        guard !chosen.isEmpty else { return }
        withAnimation(Theme.fold) { windowPicker = nil }
        tuck(chosen)
    }

    /// Tucks every listed window of one app (the app in front, from the Tuck button's menu); they share
    /// its app row.
    func tuckAllWindows(of app: AppIdentity) {
        let windows = parking.windowCandidates().filter { candidate in
            CandidatePolicy.exclusion(for: candidate) == nil
                && (app.bundleID.isEmpty ? candidate.app.name == app.name : candidate.app.bundleID == app.bundleID)
        }
        guard !windows.isEmpty else {
            showStatus(accessibilityTrusted ? "No \(app.name) windows to tuck" : Self.accessibilityNeeded,
                       symbol: accessibilityTrusted ? "macwindow" : "lock")
            return
        }
        tuck(windows.sorted { $0.stackOrder < $1.stackOrder })
    }

    private func tuck(_ candidates: [WindowCandidate]) {
        let results = parking.park(candidates)
        if results.contains(.needsPermission) {
            showStatus(Self.accessibilityNeeded, symbol: "lock")
            return
        }
        let parked = results.compactMap { result -> ParkedWindow? in
            if case .parked(let window) = result { return window }
            return nil
        }
        let missed = candidates.count - parked.count - results.filter { $0 == .alreadyTucked }.count
        if parked.isEmpty && missed == 0 { return }
        guard !parked.isEmpty else {
            showStatus(missed == 1 ? "That window couldn't be tucked" : "Those windows couldn't be tucked",
                       symbol: "exclamationmark.circle")
            return
        }
        withAnimation(Theme.settle) { library.parkAll(parked) }
        updateFrontWindowBar { $0.tucked(parked) }
        depositWindows(parked)
        showArrivals()
        var text = parked.count == 1 ? "1 window tucked" : "\(parked.count) windows tucked"
        if missed > 0 { text += missed == 1 ? " · 1 couldn't be" : " · \(missed) couldn't be" }
        showStatus(text, symbol: "arrow.down.to.line")
    }

    // MARK: Restore all

    /// While a Restore All is bringing windows back. A second one waits for it to finish rather than
    /// starting another run over the same windows, which would restore each twice and miscount them.
    @Published private(set) var isRestoringAll = false

    /// Whether any window is tucked, so Restore All (Clear Windows) has something to do.
    var canRestoreAll: Bool { !library.windows.isEmpty }

    /// Restores every tucked window for one app, in turn. It is chosen by name from that app's own row,
    /// so it doesn't ask first.
    func restoreAllWindows(of app: AppIdentity) {
        let windows = library.windows.filter { $0.app.isSameApp(as: app) }
        guard windows.count > 1 else { return }
        chooser.dismiss()
        restoreAll(windows)
    }

    /// Asks before restoring every tucked window; nothing is restored in bulk by accident.
    func requestRestoreAll() {
        guard canRestoreAll, !isRestoringAll else { return }
        chooser.dismiss()
        withAnimation(Theme.quick) {
            clearPlan = nil
            clearCopiedPrompt = false
            restoreAllPrompt = true
        }
    }

    func cancelRestoreAll() {
        withAnimation(Theme.quick) { restoreAllPrompt = false }
    }

    /// Restores every tucked window one after another; any that can't come back stay listed.
    func confirmRestoreAll() {
        guard restoreAllPrompt else { return }
        withAnimation(Theme.quick) { restoreAllPrompt = false }
        restoreAll(library.windows)
    }

    /// Windows come back in the order they are kept, newest first, each raised as it returns: the one
    /// tucked first comes back last and so ends up in front, as it was before the others were tucked.
    private func restoreAll(_ windows: [ParkedWindow]) {
        guard !windows.isEmpty, !isRestoringAll else { return }
        guard AX.isTrusted else { return refuse(Self.accessibilityNeeded, symbol: "lock") }
        isRestoringAll = true
        restoreInTurn(windows.map(\.id), summary: RestoreSummary()) { [weak self] summary in
            guard let self else { return }
            self.isRestoringAll = false
            var text = summary.restored == 1 ? "1 window restored" : "\(summary.restored) windows restored"
            if summary.gone > 0 { text += " · \(summary.gone) had closed" }
            if summary.kept > 0 { text += " · \(summary.kept) still here" }
            self.showStatus(text, symbol: summary.kept > 0 ? "exclamationmark.circle" : "checkmark.circle")
        }
    }

    /// Restores windows one after another, then reports how it went.
    private func restoreInTurn(_ ids: [UUID], summary: RestoreSummary, done: @escaping (RestoreSummary) -> Void) {
        guard let next = ids.first else { return done(summary) }
        restore(windowID: next, placement: .original) { [weak self] result in
            var updated = summary
            updated.add(result)
            self?.restoreInTurn(Array(ids.dropFirst()), summary: updated, done: done)
        }
    }

    /// Kept short enough for the status line under either name of the settings list.
    private static let accessibilityNeeded: String = {
        if #available(macOS 27, *) { return "Allow Tuck in \(AX.paneName)" }
        return "Allow Tuck in \(AX.paneName) settings, then try again"
    }()

    private static let restoreNeedsAccessibility: String = {
        if #available(macOS 27, *) { return accessibilityNeeded }
        return "Allow Tuck in \(AX.paneName) settings to restore windows"
    }()

    private static let accessibilityLost = "Allow Tuck in \(AX.paneName) again to bring windows back"

    /// Brings back every tucked window, one after another, then says how it went through `done`. Without
    /// Accessibility none can come back: nothing is tried, and all of them count as kept.
    func restoreEveryWindow(done: @escaping (RestoreSummary) -> Void) {
        let windows = library.windows
        guard AX.isTrusted else { return done(RestoreSummary(results: windows.map { _ in .needsPermission })) }
        isRestoringAll = true
        restoreInTurn(windows.map(\.id), summary: RestoreSummary()) { [weak self] summary in
            self?.isRestoringAll = false
            done(summary)
        }
    }

    /// What the closed notch holds, for VoiceOver: what is in Tuck.
    var spaceSummary: String {
        var parts: [String] = []
        let windows = library.windows.count, items = library.items.count
        if windows > 0 { parts.append(windows == 1 ? "1 window" : "\(windows) windows") }
        if items > 0 { parts.append(items == 1 ? "1 item" : "\(items) items") }
        // VoiceOver reads it after the surface's label, "Tuck", and announcements put "Tuck, " first.
        return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
    }

    // MARK: Rest

    private var restHoldsTermination = false
    /// Told when the first app starts resting and when the last one wakes.
    var onRestingChanged: ((Bool) -> Void)?

    /// While any app is resting, macOS may not end Tuck suddenly: a normal quit must reach
    /// `applicationWillTerminate`, which wakes every rested app.
    private func holdTerminationWhileResting() {
        let resting = library.restStates.values.contains(where: \.isResting)
        guard resting != restHoldsTermination else { return }
        restHoldsTermination = resting
        onRestingChanged?(resting)
        if resting {
            ProcessInfo.processInfo.disableSuddenTermination()
        } else {
            ProcessInfo.processInfo.enableSuddenTermination()
        }
    }

    /// Bundle identifiers of apps Tuck is resting; their windows are never listed or touched.
    var restingBundleIDs: Set<String> {
        Set(library.restStates.filter { $0.value.isResting }.keys)
    }

    /// Whether the experimental Rest setting is on.
    var restIsEnabled: Bool { rest.isEnabled }
    /// Turns the experimental Rest setting on, through the settings store so its window stays in step.
    var enableRestHandler: (() -> Void)?

    private static let restExplainedKey = "RestExplained"
    private var restExplained: Bool {
        get { UserDefaults.standard.bool(forKey: Self.restExplainedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.restExplainedKey) }
    }

    /// Starts resting an app at the person's request: explained the first time, confirmed more strongly
    /// when the app is busy, refused with a reason when it isn't safe. Never automatic.
    func requestRest(_ app: AppIdentity) {
        if case .unavailable(let reason) = rest.currentEligibility(for: app) {
            showStatus(reason, symbol: "moon.zzz")
            return
        }
        // The setting is the only thing in the way: offer to turn it on right here.
        guard rest.isEnabled else {
            withAnimation(Theme.quick) { restPrompt = RestPrompt(app: app, step: .turnOn) }
            return
        }
        if !restExplained {
            withAnimation(Theme.quick) { restPrompt = RestPrompt(app: app, step: .explain) }
            return
        }
        performRest(app, confirmedStrongly: false)
    }

    func confirmRest() {
        guard let prompt = restPrompt else { return }
        withAnimation(Theme.quick) { restPrompt = nil }
        switch prompt.step {
        case .turnOn:
            // One question covers both: turning Rest on shows the same explanation as a first rest.
            enableRestHandler?()
            guard rest.isEnabled else { return }
            restExplained = true
            performRest(prompt.app, confirmedStrongly: false)
        case .explain:
            restExplained = true
            performRest(prompt.app, confirmedStrongly: false)
        case .confirmBusy:
            performRest(prompt.app, confirmedStrongly: true)
        }
    }

    func cancelRest() {
        withAnimation(Theme.quick) { restPrompt = nil }
    }

    private func performRest(_ app: AppIdentity, confirmedStrongly: Bool) {
        rest.rest(app, confirmedStrongly: confirmedStrongly, acknowledged: restExplained) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let state):
                self.library.setRestState(state, for: app.bundleID)
                // On disk straight away, so a crash right after still leaves a record to wake it from.
                self.persistence.flush()
                self.showStatus("\(app.name) is resting · restore a window to wake it", symbol: "moon.zzz")
            case .failure(.needsStrongConfirmation(let reason)):
                withAnimation(Theme.quick) { self.restPrompt = RestPrompt(app: app, step: .confirmBusy(reason)) }
            case .failure(let failure):
                self.showStatus(Self.describe(failure, app: app), symbol: "moon.zzz")
            }
        }
    }

    /// Wakes a rested app on a deliberate action. Returns false (and says so) only when it is still paused.
    @discardableResult
    func wake(_ app: AppIdentity) -> Bool {
        let state = library.restState(for: app.bundleID)
        guard state.isResting else { return true }
        switch rest.wake(state) {
        case .woke, .wasAwake, .stale:
            library.setRestState(.awake, for: app.bundleID)
            return true
        case .failed:
            showStatus("Couldn't wake \(app.name) · it's still resting", symbol: "exclamationmark.circle")
            return false
        }
    }

    /// The person switched to a rested app themselves (Dock, Command-Tab): a deliberate wake.
    func wakeIfResting(bundleID: String) {
        guard library.restState(for: bundleID).isResting else { return }
        wake(AppIdentity(bundleID: bundleID, name: Self.appName(for: bundleID)))
    }

    /// A rested app is woken once none of its windows is listed any more (the row was forgotten):
    /// nothing on screen would offer to wake it.
    private func wakeUnlistedRestedApps() {
        let listed = Set(library.windows.map(\.app.bundleID))
        for bundleID in restingBundleIDs where !listed.contains(bundleID) {
            wake(AppIdentity(bundleID: bundleID, name: Self.appName(for: bundleID)))
        }
    }

    static func appName(for bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.deletingPathExtension().lastPathComponent
            ?? bundleID
    }

    /// Before quitting or sleeping, and at launch: wakes everything recorded as resting.
    func wakeAllRestedApps() {
        let resting = library.restStates.filter { $0.value.isResting }
        guard !resting.isEmpty else { return }
        let left = rest.wakeAll(resting)
        for bundleID in resting.keys where left[bundleID] == nil {
            library.setRestState(.awake, for: bundleID)
        }
    }

    func recoverRestedApps() {
        wakeAllRestedApps()
    }

    /// Wakes apps recorded as resting in a library file that couldn't otherwise be read.
    func wakeRecorded(_ states: [String: RestState]) {
        let resting = states.filter { $0.value.isResting }
        if !resting.isEmpty { _ = rest.wakeAll(resting) }
    }

    private static func describe(_ failure: RestFailure, app: AppIdentity) -> String {
        switch failure {
        case .disabled: return "Rest is experimental: turn it on in Tuck's settings"
        case .notAcknowledged: return "Rest needs its explanation accepted first"
        case .notEligible(let reason), .needsStrongConfirmation(let reason): return reason
        case .processGone: return "\(app.name) isn't running"
        case .processChanged: return "\(app.name) restarted · nothing was paused"
        case .signalFailed, .didNotTakeEffect: return "Couldn't rest \(app.name) · it's still running"
        }
    }

    // MARK: Parked windows

    /// Normal click restores; Command-click opens the inline placement chooser.
    func activate(window: ParkedWindow) {
        if NSEvent.modifierFlags.contains(.command) {
            withAnimation(Theme.quick) { chooser.toggle(for: window.id) }
        } else {
            restore(windowID: window.id, placement: .original)
        }
    }

    func applyPlacement(_ placement: Placement) {
        guard let request = chooser.commit(placement) else { return }
        if request.windowID == Self.frontWindowChooserID {
            placeShownWindow(request.placement)
        } else {
            restore(windowID: request.windowID, placement: request.placement)
        }
    }

    var hasMultipleDisplays: Bool { NSScreen.screens.count > 1 }

    /// Restores under way, by window, with whoever is waiting to hear how each went: a second click
    /// while a card flies out joins the first rather than starting another.
    private var restoresUnderWay: [UUID: [(WindowActionResult) -> Void]] = [:]

    /// Brings a tucked window back. One parked off screen comes back under its card, which flies out of
    /// Tuck to where the window will be (unless `flies` is false: the person has gone to the window
    /// already); a minimised one comes back with the Dock's own animation.
    func restore(windowID: UUID, placement: Placement, flies: Bool = true,
                 completion: ((WindowActionResult) -> Void)? = nil) {
        guard let window = library.window(id: windowID) else {
            completion?(.windowGone)
            return
        }
        if restoresUnderWay[windowID] != nil {
            if let completion { restoresUnderWay[windowID]?.append(completion) }
            return
        }
        let screen = expandedScreenID.flatMap { id in NSScreen.screens.first { $0.displayID == id } } ?? NSScreen.main
        let context = PlacementContext(
            visibleFrame: screen?.visibleFrame ?? .zero,
            originalDisplayAvailable: window.displayID.map { displayExists?($0) ?? false } ?? true,
            nextVisibleFrame: screen.flatMap(Displays.next(after:))?.visibleFrame
        )
        withAnimation(Theme.quick) { chooser.dismiss() }
        // A rested app is woken first: restoring its window is the deliberate wake. If it can't be woken,
        // nothing else is tried and the row stays.
        guard wake(window.app) else {
            completion?(.failed)
            return
        }
        // Showing a hidden app shows every window it hid: the others tucked with it are minimised first,
        // while still hidden, so only this one comes back.
        let siblings = ParkingPolicy.siblingsToKeepTucked(restoring: window, among: library.windows)
        if !siblings.isEmpty {
            let kept = parking.keepTucked(siblings)
            if !kept.isEmpty { library.setParkingMethod(.minimised, forWindows: kept) }
        }
        restoresUnderWay[windowID] = completion.map { [$0] } ?? []
        let bringBack: () -> Void = { [weak self] in
            self?.parking.restore(window, placement: placement, context: context) { outcome in
                self?.restored(window, placement: placement, outcome: outcome)
            }
        }
        guard flies, window.isOffScreen, let fly = onWindowRestoring else { return bringBack() }
        let target = PlacementGeometry.frame(
            for: placement,
            originalFrame: window.originalFrame.cgRect,
            visibleFrame: context.visibleFrame,
            originalDisplayAvailable: context.originalDisplayAvailable,
            destinationVisibleFrame: context.nextVisibleFrame
        )
        fly(window, target, bringBack)
    }

    private func restored(_ window: ParkedWindow, placement: Placement, outcome: WindowActionOutcome) {
        let waiting = restoresUnderWay.removeValue(forKey: window.id) ?? []
        // The row goes only once the window is confirmed back or confirmed gone; anything else keeps it.
        if outcome.result.removesParkedRow {
            withAnimation(Theme.settle) { _ = library.removeWindow(id: window.id) }
        }
        let name = window.app.name
        switch outcome.result {
        case .moved, .constrained, .simulated:
            // A placement chosen with Command-click snaps the window into place; a plain restore is quiet.
            if placement != .original { haptics.perform(.placementSnapped) }
            var text = "\(name) restored to \(placement.restoreDescription)"
            if outcome.result == .constrained { text += " · kept its size" }
            showStatus(text, symbol: Theme.symbol(for: placement))
        case .windowGone:
            showStatus("That \(name) window has closed", symbol: "xmark.circle")
        case .needsPermission:
            showStatus(Self.restoreNeedsAccessibility, symbol: "lock")
        case .failed, .unchanged:
            showStatus("Couldn't bring back \(name) · try again", symbol: "exclamationmark.circle")
        }
        // The person brought it back, so what comes forward with it is named, even if Tuck's own
        // moves are still settling when the watcher reports it.
        if [.moved, .constrained, .simulated].contains(outcome.result) { updateFrontWindowBar { $0.windowRestored() } }
        waiting.forEach { $0(outcome.result) }
    }

    /// The person went to a window parked off screen (its app's Dock icon, the app switcher): it comes
    /// back where it was, at once, since they are already looking for it.
    func parkedWindowFocused(_ windowID: UUID) {
        restore(windowID: windowID, placement: .original, flies: false)
    }

    /// Windows that didn't stay off screen as planned: minimised instead, still in view because they
    /// couldn't be put away at all, or brought back by the person some other way. The last two are no
    /// longer tucked, so their rows go.
    func windowsParkedDifferently(minimised: Set<UUID>, refused: Set<UUID>, broughtBack: Set<UUID>) {
        var updated = library
        if !minimised.isEmpty { updated.setParkingMethod(.minimised, forWindows: minimised) }
        for id in refused.union(broughtBack) { _ = updated.removeWindow(id: id) }
        withAnimation(Theme.settle) { library = updated }
        arrivingWindowIDs.subtract(refused.union(broughtBack))
        // Back in view, so the fold may name them again.
        if !refused.isEmpty || !broughtBack.isEmpty { refreshFrontWindowBar() }
        if !refused.isEmpty {
            showStatus(refused.count == 1 ? "That window couldn't be tucked" : "Those windows couldn't be tucked",
                       symbol: "exclamationmark.circle")
        }
    }

    /// Before Tuck quits, windows parked off screen are minimised, so none is left out of reach while
    /// Tuck isn't running to bring it back; their rows then restore from the Dock.
    func minimiseOffScreenWindows() {
        let rows = library.windows.filter(\.isOffScreen)
        guard !rows.isEmpty else { return }
        let minimised = parking.keepTucked(rows)
        if !minimised.isEmpty { library.setParkingMethod(.minimised, forWindows: minimised) }
    }

    private var offScreenHoldsTermination = false

    /// While any window is parked off screen, macOS may not end Tuck suddenly: a normal quit must reach
    /// `applicationWillTerminate`, which minimises those windows.
    private func holdTerminationWhileOffScreen() {
        let offScreen = library.windows.contains(where: \.isOffScreen)
        guard offScreen != offScreenHoldsTermination else { return }
        offScreenHoldsTermination = offScreen
        if offScreen {
            ProcessInfo.processInfo.disableSuddenTermination()
        } else {
            ProcessInfo.processInfo.enableSuddenTermination()
        }
    }

    /// Removes a parked-window row on request, for a window that can no longer be found. A window that
    /// still exists is left as it is, minimised or hidden with its app; one parked off screen would be
    /// out of reach once forgotten, so it is minimised first.
    func forgetWindow(_ windowID: UUID) {
        guard let window = library.window(id: windowID) else { return }
        let minimised = window.isOffScreen && !parking.keepTucked([window]).isEmpty
        withAnimation(Theme.settle) {
            _ = library.removeWindow(id: windowID)
            chooser.dismiss()
        }
        wakeUnlistedRestedApps()
        showStatus(minimised ? "Forgot the \(window.app.name) window · it's in the Dock"
                             : "Forgot the \(window.app.name) window · it's untouched", symbol: "minus.circle")
    }

    /// Opens the placement chooser under a parked window's row, as Command-click does.
    func showPlacements(for windowID: UUID) {
        guard !chooser.isOpen(for: windowID) else { return }
        withAnimation(Theme.quick) { chooser.toggle(for: windowID) }
    }

    // MARK: Front window

    func toggleFrontWindowChooser() {
        withAnimation(Theme.quick) { chooser.toggle(for: Self.frontWindowChooserID) }
    }

    /// Hides the window in front at this moment into Tuck: the shortcut, the menu and the notch's Tuck,
    /// which name no window.
    func tuckFrontWindow() {
        frontWindowTucked(parking.parkFrontWindow())
    }

    /// The Tuck button: hides the window the fold names, and no other. One closed, put away or no longer
    /// the one held since it was read is left alone; the window in front is read again and the fold says
    /// why.
    func tuckShownWindow() {
        guard let front = frontWindow else { return }
        let check = parking.check(front.window)
        guard check == .ready, let window = front.window else { return shownWindowUnavailable(front, check) }
        let result = parking.park(window)
        // Ready a moment ago, then closed or put away before it could go: said as for a failed check, not
        // as the shortcut's "No window to tuck", and the window in front is read again.
        guard result != .noWindow, result != .alreadyTucked else {
            return shownWindowUnavailable(front, .missed(rechecked: parking.check(window)))
        }
        frontWindowTucked(result)
    }

    private func frontWindowTucked(_ result: ParkResult) {
        switch result {
        case .parked(let window):
            withAnimation(Theme.settle) { library.park(window) }
            // The window in front has just been put away: nothing is offered until another is chosen.
            updateFrontWindowBar { $0.tuckedFrontWindow() }
            pruneWindowPicker()
            depositWindows([window])
            showArrivals()
            showStatus("\(window.app.name) tucked", symbol: "arrow.down.to.line")
        case .alreadyTucked:
            break
        case .needsPermission:
            refuse(Self.accessibilityNeeded, symbol: "lock")
        case .noWindow:
            refuse("No window to tuck", symbol: "macwindow")
        case .failed:
            refuse("That window couldn't be tucked", symbol: "exclamationmark.circle")
        }
    }

    /// Whether there is a tucked window for "Restore Last Tucked Window".
    var canRestoreLastTucked: Bool { !library.windows.isEmpty }

    /// The window tucked most recently comes back where it was: one window, never more.
    func restoreLastTuckedWindow() {
        guard let newest = WindowOrdering.newestFirst(library.windows).first else {
            refuse("No windows in Tuck", symbol: "macwindow")
            return
        }
        restore(windowID: newest.id, placement: .original) { [weak self] result in
            if !result.removesParkedRow { self?.refusals += 1 }
        }
    }

    /// Arrange: places the window the fold names, and no other, checked as Tuck checks it.
    func placeShownWindow(_ placement: Placement) {
        guard let front = frontWindow else { return }
        let check = parking.check(front.window)
        guard check == .ready, let window = front.window else { return shownWindowUnavailable(front, check) }
        let name = front.app.name
        let outcome = parking.place(window, placement: placement)
        switch outcome.result {
        case .moved, .constrained, .simulated:
            // Going back to its earlier frame is quiet, as a plain restore is.
            if placement != .original { haptics.perform(.placementSnapped) }
            let suffix = outcome.result == .constrained ? " · kept its own size" : ""
            let verb = placement == .original ? "returned to" : "placed on"
            let where_ = placement == .original ? "its earlier frame" : placement.restoreDescription
            showStatus("\(name) \(verb) \(where_)\(suffix)", symbol: Theme.symbol(for: placement))
        case .unchanged:
            showStatus(placement == .nextDisplay ? "Only one display connected" : "\(name) is already where it was",
                       symbol: "equal.circle")
        case .needsPermission:
            showStatus(Self.accessibilityNeeded, symbol: "lock")
        case .windowGone:
            // Ready a moment ago, then closed, put away or too slow to answer: as for a failed check.
            shownWindowUnavailable(front, .missed(rechecked: parking.check(window)))
        case .failed:
            showStatus("\(name) didn't accept the new frame", symbol: "exclamationmark.circle")
        }
    }

    /// The named window can't be acted on any more, so nothing is done to any window: the window in front
    /// is read again, to name what is in front now, and a status line says why.
    private func shownWindowUnavailable(_ front: FrontWindowInfo, _ check: ShownWindowCheck) {
        let name = front.app.name
        switch check {
        case .ready:
            return
        case .needsPermission:
            refuse(Self.accessibilityNeeded, symbol: "lock")
        case .closed:
            refuse("That \(name) window has closed", symbol: "xmark.circle")
        case .putAway:
            refuse("That \(name) window is already put away", symbol: "macwindow")
        case .busy:
            refuse("\(name) isn't answering · try again", symbol: "exclamationmark.circle")
        case .stale:
            refuse("The window in front has changed", symbol: "macwindow")
        }
        refreshFrontWindowBar()
    }

    func restEligibility(for app: AppIdentity) -> RestEligibility { rest.eligibility(for: app) }

    // MARK: Held items

    func activate(item: HeldItem) {
        switch item.kind {
        case .text:
            copy(text: item.text ?? "", feedbackID: item.id)
        case .file, .link, .music, .stack:
            switch opener.open(item) {
            case .opened(let appName):
                showFeedback(for: item.id, message: "Opened in \(appName)", symbol: "arrow.up.forward.app")
            case .simulatedOpen(let appName):
                showFeedback(for: item.id, message: "Opening in \(appName) · simulated", symbol: "arrow.up.forward.app")
            case .failed(let reason):
                showFeedback(for: item.id, message: reason, symbol: "exclamationmark.circle")
            }
        }
    }

    func copy(text: String, feedbackID: UUID, label: String? = nil) {
        guard !text.isEmpty else { return }
        pasteboard.copy(text)
        clipboard.record(text: text, sourceBundleID: Bundle.main.bundleIdentifier, sourceAppName: "Tuck")
        onClipboardHistoryChanged?(clipboard)
        showFeedback(for: feedbackID, message: label.map { "Copied \($0)" } ?? "Copied", symbol: "checkmark")
    }

    func beginEditing(_ item: HeldItem) {
        guard item.kind == .text else { return }
        editingText = item.text ?? ""
        withAnimation(Theme.quick) { editingItemID = item.id }
        if let screen = expandedScreenID { requestKeyFocus?(screen) }
    }

    func commitEdit() {
        guard let id = editingItemID else { return }
        let text = editingText
        let saves = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        withAnimation(Theme.quick) {
            if saves { library.updateText(itemID: id, to: text) }
            editingItemID = nil
        }
        if saves { showFeedback(for: id, message: "Saved", symbol: "checkmark") }
    }

    func cancelEdit() {
        withAnimation(Theme.quick) { editingItemID = nil }
    }

    /// Removes the row (a file inside a stack included). Files Tuck received itself (promised files,
    /// dropped images) are deleted with it unless another row still refers to them; references to the
    /// person's own files never touch the file.
    func remove(item: HeldItem) {
        var removed: HeldItem?
        withAnimation(Theme.settle) { removed = library.removeHeldItem(id: item.id) }
        guard let removed, let receivedFiles else { return }
        let stillHeld = library.referencedFileURLs
        removed.fileURLs.filter { !stillHeld.contains($0.standardizedFileURL) }.forEach { receivedFiles.discard($0) }
    }

    func toggleStack(_ item: HeldItem) {
        withAnimation(Theme.quick) { revealedStackID = revealedStackID == item.id ? nil : item.id }
    }

    func unstack(_ item: HeldItem) {
        withAnimation(Theme.settle) { _ = library.unstack(itemID: item.id) }
    }

    func revealInFinder(_ item: HeldItem) {
        let urls = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Zips the item's files next to the originals (Downloads when that folder is read-only) and holds
    /// the archive at the top of the stream.
    func compress(_ item: HeldItem) {
        let sources = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !sources.isEmpty else {
            showFeedback(for: item.id, message: "Files missing", symbol: "exclamationmark.circle")
            return
        }
        showFeedback(for: item.id, message: "Zipping…", symbol: "doc.zipper")
        ZipArchiver.zip(sources) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                let archive = FileReferences.withBookmarks(.file(url, sourceAppName: "Tuck"))
                withAnimation(Theme.settle) { self.library.add(archive) }
                self.showFeedback(for: archive.id, message: "Zipped", symbol: "checkmark")
            case .failure:
                self.showFeedback(for: item.id, message: "Couldn't zip", symbol: "exclamationmark.circle")
            }
        }
    }

    /// Representations supplied when a held item is dragged out: the original file, the link, or the text.
    func dragProvider(for item: HeldItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            if let url = item.url {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider()
        case .link, .music:
            let provider = item.url.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
            provider.suggestedName = item.title
            return provider
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .stack:
            // Single-provider fallback; stack rows drag all their files through `MultiFileDragSource`.
            return item.fileURLs.first.map { NSItemProvider(contentsOf: $0) ?? NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        }
    }

    func feedback(for id: UUID) -> RowFeedback? {
        feedback?.id == id ? feedback : nil
    }

    // MARK: Clipboard history

    func recordClipboardCapture(_ capture: ClipboardCapture) {
        guard clipboard.isEnabled else { return }
        let decision = withAnimation(Theme.quick) { clipboard.record(capture) }
        guard decision == .recorded || decision == .movedToTop else { return }
        onClipboardHistoryChanged?(clipboard)
        guard let entry = clipboard.entries.first else { return }
        // A link copied again without its page's picture (copied before Tuck looked links up, or while its
        // page couldn't be reached) is looked up once more, so a link already in the history can gain one.
        let lacksPicture = [.link, .music].contains(entry.category) && entry.preview?.pageImageFile == nil
        if decision == .recorded || lacksPicture {
            clipboardEnricher?.enrich(entry) { [weak self] preview in self?.updateClipboardPreview(id: entry.id, preview) }
        }
    }

    func updateClipboardPreview(id: UUID, _ preview: ClipPreview) {
        clipboard.update(id: id, preview: preview)
        onClipboardHistoryChanged?(clipboard)
    }

    /// Links the panel has asked about this launch, so each is looked up at most once while Tuck runs.
    private var linksLookedUp: Set<UUID> = []

    /// A link already in the history with neither its page's icon nor its picture (copied before Tuck looked
    /// links up, or while its page couldn't be reached) is looked up once, when its tile first comes into view.
    func lookUpPreviewIfNeeded(_ entry: ClipboardEntry) {
        guard [.link, .music].contains(entry.category),
              entry.preview?.iconFile == nil, entry.preview?.pageImageFile == nil,
              clipboardEnricher?.wants(entry) == true,
              linksLookedUp.insert(entry.id).inserted else { return }
        clipboardEnricher?.enrich(entry) { [weak self] preview in self?.updateClipboardPreview(id: entry.id, preview) }
    }

    /// Puts the entry back on the clipboard as it was copied (its files, image or styling too), and moves it
    /// to the top. Returns whether it copied: files that have all gone are not.
    @discardableResult
    func copy(entry: ClipboardEntry) -> Bool {
        if let urls = entry.payload?.fileURLs, !urls.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            showFeedback(for: entry.id, message: urls.count == 1 ? "File no longer there" : "Files no longer there",
                         symbol: "exclamationmark.circle")
            return false
        }
        pasteboard.copy(entry)
        moveToTop(entry.id)
        showFeedback(for: entry.id, message: "Copied", symbol: "checkmark")
        return true
    }

    /// A copy goes to the top of the history once a double-click could no longer finish on it: moved at
    /// once, its tile would slide out from under the second click. Another copy in the meantime moves the
    /// waiting one first.
    private func moveToTop(_ id: UUID) {
        if let pending = pendingTouch {
            pending.work.cancel()
            if pending.id != id { touch(pending.id) }
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pendingTouch = nil
            self?.touch(id)
        }
        pendingTouch = (id, work)
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    private func touch(_ id: UUID) {
        withAnimation(Theme.quick) { clipboard.touch(id: id) }
        onClipboardHistoryChanged?(clipboard)
    }

    /// Copies one part of an entry as text (a colour's hex, a contact's number).
    func copy(part text: String, of entry: ClipboardEntry, label: String) {
        pasteboard.copy(text)
        showFeedback(for: entry.id, message: "Copied \(label)", symbol: "checkmark")
    }

    /// Keeps a copy in Tuck as a held item: its files as references to the originals, an image as a file
    /// Tuck saves, a link or text as itself. The copy stays where it is; its row says it's kept.
    func keep(entry: ClipboardEntry) {
        var items: [HeldItem] = []
        if let urls = entry.payload?.fileURLs, !urls.isEmpty {
            items = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                .map { HeldItem.file($0, sourceAppName: entry.sourceAppName) }
        } else if let name = entry.payload?.imageFile {
            if let store = receivedFiles, let data = clipboardAssets.flatMap({ try? Data(contentsOf: $0.url(for: name)) }),
               let url = ReceivedIntake.receive(image: data, into: store) {
                items = [.file(url, sourceAppName: entry.sourceAppName)]
            }
        } else if let item = HeldItemClassifier.item(forText: entry.text, sourceAppName: entry.sourceAppName) {
            items = [item]
        }
        let rows = DropIntake.rows(for: items).map(FileReferences.withBookmarks)
        guard !rows.isEmpty else {
            return showFeedback(for: entry.id, message: "Nothing to keep", symbol: "exclamationmark.circle")
        }
        guard library.remainingCapacity >= rows.count else {
            return showFeedback(for: entry.id, message: "Tuck is full", symbol: "tray.full")
        }
        var updated = library
        for item in rows.reversed() { updated.add(item) }
        withAnimation(Theme.settle) { library = updated }
        confirmDeposit(count: rows.count)
        showFeedback(for: entry.id, message: "Kept in Tuck", symbol: "tray.and.arrow.down")
    }

    func removeClipboardEntry(_ entry: ClipboardEntry) {
        withAnimation(Theme.quick) { clipboard.remove(id: entry.id) }
        onClipboardHistoryChanged?(clipboard)
    }

    func clearClipboard() {
        withAnimation(Theme.quick) { clipboard.clear() }
        onClipboardHistoryChanged?(clipboard)
        onClipboardCleared?()
        showStatus("Clipboard history cleared", symbol: "trash")
    }

    // MARK: Pasting

    /// The app a double-click pastes into, for tooltips and VoiceOver: the one in front, unless that is
    /// Tuck itself or Tuck isn't allowed to type into it.
    var pasteTargetName: String? {
        guard accessibilityTrusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app.localizedName
    }

    /// Double-click on a copy: back on the clipboard, then pasted into the app in front, as ⌘V there
    /// would. Files that have gone aren't pasted.
    func paste(entry: ClipboardEntry) {
        let target = NSWorkspace.shared.frontmostApplication
        guard copy(entry: entry) else { return }
        paste(into: target, feedbackID: entry.id)
    }

    /// Double-click on held text, a link or music: the text, or the link's address as text, pasted the same
    /// way. Files and stacks open as a click does.
    func paste(item: HeldItem) {
        let target = NSWorkspace.shared.frontmostApplication
        let text: String?
        switch item.kind {
        case .text: text = item.text
        case .link, .music: text = item.url?.absoluteString
        case .file, .stack: return activate(item: item)
        }
        guard let text, !text.isEmpty else { return }
        copy(text: text, feedbackID: item.id)
        paste(into: target, feedbackID: item.id)
    }

    /// What was just copied goes into `target`, the app in front when the double-click landed. The fold
    /// closes and hands the keyboard back; a moment later one ⌘V is typed, if that app is still in front.
    /// With Tuck itself in front, or without Accessibility, it stays copied and the fold says how to paste.
    private func paste(into target: NSRunningApplication?, feedbackID: UUID) {
        guard let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return showStatus("Copied · paste with ⌘V", symbol: "doc.on.clipboard")
        }
        guard AX.isTrusted else {
            return showStatus("Copied · allow Tuck in \(AX.paneName) to paste here", symbol: "lock")
        }
        let name = target.localizedName ?? "the app in front"
        collapse(via: .click)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier, paster.paste() {
                showFeedback(for: feedbackID, message: "Pasted into \(name)", symbol: "checkmark")
            } else {
                showStatus("Copied · paste with ⌘V", symbol: "doc.on.clipboard")
            }
        }
    }

    // MARK: Search

    func toggleSearch() {
        isSearching ? endSearch() : beginSearch()
    }

    /// Opens the search field in the full fold and makes the panel take typing. From the shallow fold a
    /// lens that is on comes along, so the search looks within it, unless it holds nothing, when the search
    /// looks at everything. With nothing in Tuck there is nothing to search, so the fold says so rather
    /// than unfolding onto nothing.
    func beginSearch() {
        guard let screen = expandedScreenID else { return }
        if editingItemID != nil { commitEdit() }
        if isStreamEmpty, !isSearching {
            return showStatus("Nothing in Tuck to search yet", symbol: "magnifyingglass")
        }
        let lensSearched = TuckStream.lens(lens, keptFor: lensCounts)
        if foldDepth != .full {
            unfold(keepingLens: lensSearched != nil)
        } else if lensSearched != lens {
            withAnimation(Theme.quick) { lens = lensSearched }
        }
        withAnimation(Theme.quick) { isSearching = true }
        requestKeyFocus?(screen)
    }

    /// A chip over the stream before any search: opens the search with that kind already filtered, and a
    /// space after its word, so what is typed next narrows it further.
    func beginSearch(filtering word: String) {
        beginSearch()
        guard isSearching, searchText.isEmpty else { return }
        searchText = word + " "
    }

    func endSearch() {
        withAnimation(Theme.quick) {
            isSearching = false
            searchText = ""
        }
    }

    /// A chip under the field: adds its word to the search, or, when its filter is already on (however it
    /// was typed), takes it out again.
    func toggleSearchFilter(word: String, label: String) {
        if searchQuery.filterLabels.contains(label) {
            searchText = SearchQuery.removing(label, from: searchText, apps: searchApps ?? [])
        } else {
            searchText = searchText.isEmpty ? word : word + " " + searchText
        }
    }

    /// Return in the field: the tile the arrows are on, else the first match, does what a click on it does.
    func openFirstMatch() {
        let stream = stream
        guard let entry = stream.first(where: { $0.id == tileCursor }) ?? stream.first else { return }
        open(entry)
    }

    /// What a click on an entry's tile does: a window comes back, several open their titles, a stack its
    /// files, an item opens and a copy goes back on the clipboard.
    func open(_ entry: StreamEntry) {
        switch entry {
        case .windows(let group):
            if group.windows.count == 1 { activate(window: group.windows[0]) } else { toggleWindowGroup(group) }
        case .item(let item):
            item.kind == .stack ? toggleStack(item) : activate(item: item)
        case .copied(let entry): copy(entry: entry)
        }
    }

    /// An arrow, Return or Space in the open fold, before anything in it sees the key; returns whether
    /// it was used. The arrows move the focus ring through the tiles in rows of `columns` (the shallow
    /// fold's strip is one row); Return opens the tile they are on, and Space does too outside a search.
    /// While the arrows are on no tile, left and right stay the search field's, and so does up. Nothing
    /// is taken while an edit, the picker or a question is open.
    func handleTileKey(_ key: TileKey, columns: Int) -> Bool {
        guard expandedScreenID != nil, editingItemID == nil, windowPicker == nil, clearPlan == nil,
              !clearCopiedPrompt, !restoreAllPrompt, restPrompt == nil else { return false }
        let stream = stream
        let index = tileCursor.flatMap { id in stream.firstIndex { $0.id == id } }
        switch key {
        case .move(let move):
            if index == nil, move != .down, !(move == .right && !isSearching) { return false }
            let next = TileNavigation.step(from: index, move, count: stream.count, columns: columns,
                                           isStrip: foldDepth == .peek)
            tileCursor = next.map { stream[$0].id }
            return next != nil || index != nil
        case .open(let isSpace):
            guard let index, !(isSpace && isSearching) else { return false }
            open(stream[index])
            return true
        }
    }

    /// The lens the search is narrowed to steps aside when nothing in it matches but something elsewhere
    /// does ("windows" typed in Copied), rather than show an empty fold.
    private func searchChanged() {
        // New words, new matches: Return opens the first again.
        tileCursor = nil
        if searchApps == nil, !searchText.isEmpty {
            searchApps = ItemDetails.sourceApps(copied: copiedEntries, items: library.items)
        }
        let query = SearchQuery.parse(searchText, apps: searchApps ?? [])
        withAnimation(Theme.quick) { searchQuery = query }
        guard let lens, !query.isEmpty else { return }
        let kept = TuckStream.lens(lens, keptFor: searchCounts)
        if kept != lens { withAnimation(Theme.quick) { self.lens = kept } }
    }

    /// Where the search finds something, lens by lens, for stepping out of a lens and for saying where
    /// else something was found.
    var searchCounts: [StreamLens: Int] {
        TuckStream.counts(windows: library.windows, items: library.items, copied: copiedEntries, query: searchQuery,
                          category: ContentKinds.category(of:), size: FileSizes.byteCount(of:))
    }

    /// The kind of every row the search would show with its kind words left out (each window on its own),
    /// for the chips under the field to count.
    var searchKinds: [ContentCategory] {
        var unfiltered = searchQuery
        unfiltered.categories = []
        return kinds(of: unfiltered)
    }

    private func kinds(of query: SearchQuery) -> [ContentCategory] {
        TuckStream.entries(windows: library.windows, items: library.items, copied: copiedEntries, lens: lens,
                           query: query, category: ContentKinds.category(of:),
                           size: FileSizes.byteCount(of:)).flatMap { entry -> [ContentCategory] in
            switch entry {
            case .windows(let group): Array(repeating: .window, count: group.windows.count)
            case .item(let item): [ContentKinds.category(of: item)]
            case .copied(let copied): [copied.category]
            }
        }
    }

    struct NoMatchHint {
        struct Action {
            let title: String
            let perform: () -> Void
        }
        let text: String
        var action: Action?
    }

    /// What "No matches" says under it: where the words are found once the kinds typed are left out, or on
    /// other days, with a click that leaves those out; otherwise to try fewer words.
    var noMatchHint: NoMatchHint {
        let apps = searchApps ?? []
        if !searchQuery.categories.isEmpty {
            let found = searchKinds
            if !found.isEmpty {
                let kindLabels = searchQuery.filterLabels.filter { !SearchQuery.parse($0, apps: apps).categories.isEmpty }
                return NoMatchHint(text: "Found as \(Self.describe(found))", action: .init(title: "Show Every Kind") { [weak self] in
                    guard let self else { return }
                    searchText = kindLabels.reduce(searchText) { SearchQuery.removing($1, from: $0, apps: apps) }
                })
            }
        }
        if searchQuery.dateRange != nil {
            var anyDay = searchQuery
            anyDay.dateRange = nil
            let found = kinds(of: anyDay)
            if !found.isEmpty {
                let dayLabels = searchQuery.filterLabels.filter { SearchQuery.parse($0, apps: apps).dateRange != nil }
                return NoMatchHint(text: "Found on other days: \(Self.describe(found))", action: .init(title: "Search Any Day") { [weak self] in
                    guard let self else { return }
                    searchText = dayLabels.reduce(searchText) { SearchQuery.removing($1, from: $0, apps: apps) }
                })
            }
        }
        return NoMatchHint(text: "Try fewer words, or another kind or day.")
    }

    /// "2 links and 1 window": the kinds found, most first, at most three.
    static func describe(_ kinds: [ContentCategory]) -> String {
        let counted = Dictionary(grouping: kinds, by: { $0 }).map { (kind: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.kind.title < $1.kind.title }
        let parts = counted.prefix(3).map { "\($0.count) \(($0.count == 1 ? $0.kind.title : $0.kind.pluralTitle).lowercased())" }
        return ListFormatter.localizedString(byJoining: parts)
    }

    // MARK: Dropping

    /// A drag carrying something Tuck can hold has begun, anywhere: the invitation will name it.
    func dragStarted(kind: DropKind) {
        dragKind = kind
    }

    /// A drag has come to Tuck, near the notch or over the surface. The surface invites the drop in place
    /// and says what the drag carries; nothing opens, so the one target stays where the drag is going.
    func dragEntered(on screenID: CGDirectDisplayID, kind: DropKind) {
        dragEndWork?.cancel()
        dragKind = kind
        isDragActive = true
    }

    /// Whether a drag is over the drop target. Crossing into it plays one tick.
    func updateDropTarget(isOver: Bool) {
        guard isOverDropTarget != isOver else { return }
        isOverDropTarget = isOver
        if isOver { haptics.perform(.dropTargetEntered) }
    }

    func dragExited(from screenID: CGDirectDisplayID) {
        isOverDropTarget = false
        scheduleDragEnd(screenID: screenID, delay: 0.45)
    }

    /// Called by the global drag watcher when the pointer leaves the approach zone or the drag ends.
    func dragApproachEnded(on screenID: CGDirectDisplayID) {
        scheduleDragEnd(screenID: screenID, delay: 0.3)
    }

    private func scheduleDragEnd(screenID: CGDirectDisplayID, delay: TimeInterval) {
        dragEndWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isDragActive = false
            self?.isOverDropTarget = false
        }
        dragEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Adds dropped items with no destination dialog and plays the deposit into the mark.
    func deposit(_ dropped: [HeldItem], at point: CGPoint) {
        guard !dropped.isEmpty else { return }
        dragEndWork?.cancel()
        let rows = DropIntake.rows(for: dropped).map(FileReferences.withBookmarks)
        let items = Array(rows.prefix(library.remainingCapacity))
        if items.count < rows.count {
            showStatus("Tuck is full · \(TuckLibrary.heldItemLimit) items at most", symbol: "tray.full")
        }
        guard !items.isEmpty else {
            isDragActive = false
            isOverDropTarget = false
            return
        }
        var updated = library
        // Added oldest-first so the list reads in drop order, newest on top.
        for item in items.reversed() { updated.add(item) }
        withAnimation(Theme.deposit) { library = updated }

        confirmDeposit(count: items.count)
        showArrivals()

        isDragActive = false
        isOverDropTarget = false
        lastTrigger = .deposit
    }

    /// Whatever just arrived shows at the top of the stream: a lens that would hide it, and a search,
    /// are let go.
    private func showArrivals() {
        guard expandedScreenID != nil, lens != nil || !searchText.isEmpty else { return }
        withAnimation(Theme.quick) {
            lens = nil
            searchText = ""
        }
    }

    /// Tucked windows fly up into Tuck (drawn by the overlay). With the panel open, each lands in its own
    /// row in the stream, which waits empty until it does; otherwise in the mark, which swells and counts
    /// up. A surface that was swiped away comes back first so there is a mark to land in. A window parked
    /// off screen stays in place until its card is drawn over it, then goes at once, so no frame shows the
    /// spot empty.
    private func depositWindows(_ windows: [ParkedWindow]) {
        if !tuckedAwayScreenIDs.isEmpty { tuckedAwayScreenIDs.removeAll() }
        let ids = Set(windows.map(\.id))
        guard let fly = onWindowsTucked else {
            parking.moveOutOfSight(ids)
            return confirmDeposit(count: windows.count)
        }
        if expandedScreenID != nil { arrivingWindowIDs.formUnion(ids) }
        var waiting = ids
        fly(windows, { [weak self] covered in
            waiting.subtract(covered)
            self?.parking.moveOutOfSight(covered)
        }, { [weak self] id in
            self?.arrivingWindowIDs.remove(id)
        }, { [weak self] inMark in
            // Any window whose card never showed goes now.
            if !waiting.isEmpty { self?.parking.moveOutOfSight(waiting) }
            self?.arrivingWindowIDs.subtract(ids)
            // Landing in its row with the fold open, the deposit still gets its one tick.
            if inMark { self?.confirmDeposit(count: windows.count) } else { self?.haptics.perform(.deposited) }
        })
    }

    /// The visible half of every deposit: the mark swells and the count updates, with one tick. A surface
    /// that was swiped away comes back first, so the confirmation is never drawn on a hidden mark.
    private func confirmDeposit(count: Int) {
        if !tuckedAwayScreenIDs.isEmpty { tuckedAwayScreenIDs.removeAll() }
        haptics.perform(.deposited)
        let marker = PlusOne(count: count)
        withAnimation(Theme.deposit) { plusOne = marker }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard self?.plusOne?.token == marker.token else { return }
            withAnimation(Theme.quick) { self?.plusOne = nil }
        }
    }

    /// Handles drops whose files arrive later (promises) or must be written first (raw images).
    func deposit(_ payload: DropPayload, at point: CGPoint) {
        switch payload {
        case .items(let items):
            deposit(items, at: point)
        case .image(let data):
            guard let store = receivedFiles, let url = ReceivedIntake.receive(image: data, into: store) else { return }
            deposit([.file(url)], at: point)
        case .promises(let receivers):
            guard let store = receivedFiles else { return }
            isReceiving = true
            showStatus(receivers.count == 1 ? "Receiving file…" : "Receiving \(receivers.count) files…", symbol: "arrow.down.circle")
            dragEndWork?.cancel()
            ReceivedIntake.receive(receivers, into: store) { [weak self] urls in
                guard let self else { return }
                self.isReceiving = false
                if urls.isEmpty {
                    self.showStatus("Nothing arrived from that app", symbol: "exclamationmark.circle")
                } else {
                    self.deposit(urls.map { HeldItem.file($0) }, at: point)
                }
            }
        }
    }

    // MARK: Transient feedback

    /// Spoken by VoiceOver: what a status line or row feedback shows is otherwise only seen.
    private func announce(_ text: String) {
        guard let app = NSApp else { return }
        NSAccessibility.post(element: app, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func showFeedback(for id: UUID, message: String, symbol: String) {
        announce(message)
        feedbackWork?.cancel()
        withAnimation(Theme.quick) { feedback = RowFeedback(id: id, message: message, symbol: symbol) }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Theme.quick) { self?.feedback = nil }
        }
        feedbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    /// A status line plus the collapsed surface's shake, for actions that did nothing.
    private func refuse(_ text: String, symbol: String) {
        showStatus(text, symbol: symbol)
        refusals += 1
    }

    private func showStatus(_ text: String, symbol: String) {
        announce(text)
        statusWork?.cancel()
        withAnimation(Theme.quick) { status = StatusLine(text: text, symbol: symbol) }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Theme.quick) { self?.status = nil }
        }
        statusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }
}
