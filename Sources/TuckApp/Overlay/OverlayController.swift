import AppKit
import TuckCore

/// One surface window per display. The window is kept as small as the current state allows so it never
/// blocks clicks on the menu bar or desktop around it.
final class OverlayController {
    let anchor: ScreenAnchor
    let panel = OverlayPanel()
    private let surface: SurfaceView
    private unowned let model: TuckModel

    init(anchor: ScreenAnchor, model: TuckModel) {
        self.anchor = anchor
        self.model = model
        surface = SurfaceView(anchor: anchor, model: model)
        panel.contentView = surface
        // Escape backs out one step at a time: a prompt, the picker, an edit, the tile the arrows are on,
        // a search, the full fold, then the panel itself.
        panel.onCancel = { [weak model] in
            guard let model else { return }
            if model.clearPlan != nil {
                model.cancelClear()
            } else if model.clearCopiedPrompt {
                model.cancelClearCopied()
            } else if model.restoreAllPrompt {
                model.cancelRestoreAll()
            } else if model.restPrompt != nil {
                model.cancelRest()
            } else if model.windowPicker != nil {
                model.closeWindowPicker()
            } else if model.editingItemID != nil {
                model.cancelEdit()
            } else if model.tileCursor != nil {
                model.tileCursor = nil
            } else if model.isSearching {
                model.endSearch()
            } else if model.foldDepth == .full {
                model.fold()
            } else {
                model.collapse(via: .keyboard)
            }
        }
        // The arrows move through this display's tiles in rows as wide as its fold's.
        panel.onTileKey = { [weak self] key in
            guard let self, self.isExpanded else { return false }
            let columns = SurfaceMetrics(anchor: self.anchor, cards: self.model.cardLayout).fold.columns
            return self.model.handleTileKey(key, columns: columns)
        }
        surface.onNeedsWindowFrame = { [weak self] in self?.applyFrame() }
        surface.onPromptRoom = { [weak self] needed in
            guard let self else { return }
            self.applyFrame(expanded: self.surface.isShowingExpanded, prompt: needed)
        }
        surface.refreshCollapsedContent()
        applyFrame()
        panel.orderFrontRegardless()
    }

    var isExpanded: Bool { model.isExpanded(on: anchor.screenID) }

    /// Zones the drag watcher measures against, in AppKit global coordinates.
    var approachZone: DropApproach.Zone {
        let metrics = surface.metrics
        let size = metrics.restingSize
        let surfaceRect = CGRect(x: anchor.centerX - size.width / 2,
                                 y: anchor.screenFrame.maxY - metrics.topInset - size.height,
                                 width: size.width, height: size.height)
        return DropApproach.Zone(surface: surfaceRect, approach: anchor.dragApproachZone, display: anchor.screenFrame)
    }

    /// Shows, updates or hides the drop invitation. The surface asks for window room as it needs it.
    func setDropPrompt(_ level: Int?) {
        surface.setDropPrompt(level)
    }

    /// Where a tucked window's card lands on this display, in global coordinates.
    func depositLanding(window: UUID) -> DepositLanding? {
        surface.depositLanding(window: window)
    }

    /// Two-finger swipes on this display's surface; returns whether the event was used.
    func handleScroll(_ event: NSEvent) -> Bool {
        surface.handleScroll(event)
    }

    /// Called whenever the shared model changes.
    func refresh() {
        surface.setTuckedAway(model.isTuckedAway(on: anchor.screenID))
        let expanded = isExpanded
        if expanded && !surface.isShowingExpanded {
            guard !surface.isPreparingToExpand else { return }
            // The panel is built and measured first; then the window grows (with room for the spring's
            // overshoot) and the surface opens in one motion.
            surface.prepareToExpand { [weak self] in
                guard let self else { return }
                // Closed again while the panel was being built: the built panel isn't left in the surface.
                guard self.isExpanded, !self.surface.isShowingExpanded else { return self.settleClosed() }
                self.surface.finishMorphs()
                self.applyFrame(expanded: true)
                self.surface.layoutSubtreeIfNeeded()
                self.surface.setExpanded(true)
            }
        } else if !expanded && surface.isShowingExpanded {
            panel.resignKey()
            surface.setExpanded(false) { [weak self] in
                guard let self, !self.isExpanded else { return }
                self.applyFrame(expanded: false)
            }
        } else if !expanded {
            surface.cancelExpand()
            surface.refreshCollapsedContent()
            settleClosed()
        } else {
            // The cards changed in Settings while the fold is open: it takes its new width at once, and its
            // rows are laid out again inside it.
            if panel.frame.width != expandedWindowWidth { applyFrame(expanded: true) }
            surface.refreshCollapsedContent()
        }
    }

    /// The window's width while the fold is open, which follows the cards' layout.
    private var expandedWindowWidth: CGFloat { windowWidth(surface.metrics.expandedWidth + 48) }

    /// Whole points, with the width's parity chosen so the window stays centred exactly on the notch
    /// (whose centre can fall on a half point); the surface is then centred inside it.
    private func windowWidth(_ width: CGFloat) -> CGFloat {
        var width = ceil(width)
        if (anchor.centerX - width / 2).rounded() != anchor.centerX - width / 2 { width += 1 }
        return width
    }

    /// Mid-morph (a close still settling, say) the window keeps its size until the outline is at rest;
    /// then it shrinks, and any panel still in the surface is let go.
    private func settleClosed() {
        surface.whenSettled { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.applyFrame(expanded: false)
            self.surface.dropIdlePanel()
        }
    }

    func applyFrame() {
        applyFrame(expanded: surface.isShowingExpanded)
    }

    private func applyFrame(expanded: Bool, prompt: Bool? = nil) {
        let metrics = surface.metrics
        let size: CGSize
        let invites = prompt ?? (surface.promptLevel != nil)
        if expanded {
            // Room below the panel for the opening spring to overshoot without being clipped.
            let overshoot = ceil((surface.panelHeight - metrics.restingSize.height) * SurfaceMotion.open.overshoot) + 4
            size = CGSize(width: metrics.expandedWidth + 48,
                          height: metrics.topInset + surface.panelHeight + 28 + overshoot)
        } else {
            let slack = invites ? SurfaceView.promptSlack : .zero
            size = CGSize(width: metrics.collapsedWindowSize.width + slack.width,
                          height: metrics.collapsedWindowSize.height + slack.height)
        }
        let width = windowWidth(size.width)
        let height = ceil(size.height)
        let frame = CGRect(x: anchor.centerX - width / 2, y: anchor.screenFrame.maxY - height, width: width, height: height)
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        // The window closed (or otherwise changed size) under the pointer, which may now be in or out
        // of it; while a drag is inviting a drop, the drag decides instead.
        if !expanded && !invites { surface.pointerMayHaveMoved() }
    }

    func makeKey() {
        panel.makeKey()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}
