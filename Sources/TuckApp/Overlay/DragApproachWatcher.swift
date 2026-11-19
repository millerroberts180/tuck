import AppKit
import TuckCore

/// Watches content drags so Tuck can invite a drop before the pointer reaches it, saying what the drag
/// carries, and knows when the drag settles near the top centre of a display.
///
/// Event-driven only: global presses and releases are observed, and drag events only from a press until
/// the drag ends or is known not to carry content; nothing runs between drags. A drag is classified from
/// the drag pasteboard's change count and advertised types (`DragClassification`); contents are never
/// read, and unsupported drags are ignored for the rest of the gesture. Per event the work is a few
/// rectangle tests on the display under the pointer; the surface is told only when the invitation
/// level changes.
final class DragApproachWatcher {
    private let zones: () -> [(CGDirectDisplayID, DropApproach.Zone)]
    private let onPrompt: (CGDirectDisplayID?, Int) -> Void
    /// Once a drag is known to carry content: file, link or text, from its type list.
    private let onContent: (DropKind) -> Void
    private let onApproach: (CGDirectDisplayID) -> Void
    private let onLeave: (CGDirectDisplayID) -> Void
    private var monitors: [Any] = []
    /// Exists only from a press until the drag ends or turns out not to carry content: a pointer moved
    /// with the button down sends a stream of events, and outside a droppable drag none are needed.
    private var dragMonitor: Any?
    /// Exists only while an invitation may be showing: the first plain mouse move means the drag ended,
    /// even if its mouse-up went somewhere Tuck could not see.
    private var endMonitors: [Any] = []
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var changeCountAtMouseDown = 0
    private var mouseDownTime: TimeInterval = 0
    private var dragStartTime: TimeInterval?
    private var lastPasteboardCheck: TimeInterval = 0
    private var dragKind: DragClassification.Kind = .other
    private var prompt: (screen: CGDirectDisplayID, level: Int)?
    private var armedScreen: CGDirectDisplayID?
    private var openedScreen: CGDirectDisplayID?
    private var dwellWork: DispatchWorkItem?

    /// How often a pending drag re-checks whether its source has written the drag pasteboard.
    private static let pasteboardCheckInterval: TimeInterval = 0.03

    init(
        zones: @escaping () -> [(CGDirectDisplayID, DropApproach.Zone)],
        onPrompt: @escaping (CGDirectDisplayID?, Int) -> Void,
        onContent: @escaping (DropKind) -> Void,
        onApproach: @escaping (CGDirectDisplayID) -> Void,
        onLeave: @escaping (CGDirectDisplayID) -> Void
    ) {
        self.zones = zones
        self.onPrompt = onPrompt
        self.onContent = onContent
        self.onApproach = onApproach
        self.onLeave = onLeave
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handlers: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = [
            (.leftMouseDown, { [weak self] _ in self?.mouseDown() }),
            (.leftMouseUp, { [weak self] _ in self?.dragEnded() })
        ]
        for (mask, handler) in handlers {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
                monitors.append(monitor)
            }
        }
    }

    func stop() {
        dragEnded()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func mouseDown() {
        if dragKind != .other || prompt != nil || armedScreen != nil { dragEnded() } // never leave a stale invitation
        changeCountAtMouseDown = dragPasteboard.changeCount
        mouseDownTime = ProcessInfo.processInfo.systemUptime
        lastPasteboardCheck = mouseDownTime
        dragStartTime = nil
        dragKind = .pending
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.mouseDragged()
        }
    }

    private func mouseDragged() {
        if dragKind == .pending { classify() }
        guard dragKind == .content else { return }

        let pointer = NSEvent.mouseLocation
        // NSMouseInRect counts the top row of pixels as inside, where `contains` would not: a drag pushed
        // right up into the notch keeps its invitation.
        let hit = zones().first { NSMouseInRect(pointer, $0.1.display, false) }
        let level = hit.flatMap { screen, zone in
            DropApproach.invitation(pointer: pointer, zone: zone, wasInviting: prompt?.screen == screen)
        }
        if let hit, let level {
            if prompt?.screen != hit.0 || prompt?.level != level {
                prompt = (hit.0, level)
                onPrompt(hit.0, level)
            }
        } else if prompt != nil {
            prompt = nil
            onPrompt(nil, 0)
        }

        let armed = hit.flatMap { screen, zone in
            DropApproach.isArmed(pointer: pointer, zone: zone, wasArmed: armedScreen == screen) ? screen : nil
        }
        guard armed != armedScreen else { return }
        dwellWork?.cancel()
        if let opened = openedScreen {
            onLeave(opened)
            openedScreen = nil
        }
        armedScreen = armed
        guard let armed else { return }
        // Only if the pointer is still there after the dwell; a drag passing through does nothing.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.armedScreen == armed else { return }
            self.openedScreen = armed
            self.onApproach(armed)
        }
        dwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DropApproach.dwell, execute: work)
    }

    /// Checks the drag pasteboard's change count (and, once it changes, its type list) at a gentle rate
    /// until the drag is known to carry content or not.
    private func classify() {
        let now = ProcessInfo.processInfo.systemUptime
        // The decision window starts when the pointer first moves, not at the press: a file held still
        // for a moment before it is dragged hasn't written the drag pasteboard yet.
        if dragStartTime == nil { dragStartTime = now }
        let elapsed = now - (dragStartTime ?? now)
        guard now - lastPasteboardCheck >= Self.pasteboardCheckInterval || elapsed >= DragClassification.decisionWindow
        else { return }
        lastPasteboardCheck = now
        let changeCount = dragPasteboard.changeCount
        let types = changeCount != changeCountAtMouseDown ? dragPasteboard.types : nil
        let supported = DropReader.isDroppable(types: types)
        dragKind = DragClassification.classify(changeCountAtMouseDown: changeCountAtMouseDown, changeCount: changeCount,
                                               advertisesSupportedType: supported, elapsed: elapsed)
        switch dragKind {
        case .content:
            onContent(DropReader.kind(types: types))
            watchForDragEnd()
        case .other: stopWatchingDrags()
        case .pending: break
        }
    }

    private func stopWatchingDrags() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
    }

    private func watchForDragEnd() {
        guard endMonitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            self?.dragEnded()
        }) {
            endMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            self?.dragEnded()
            return event
        }) {
            endMonitors.append(local)
        }
    }

    private func dragEnded() {
        dwellWork?.cancel()
        dwellWork = nil
        if let opened = openedScreen { onLeave(opened) }
        if prompt != nil { onPrompt(nil, 0) }
        prompt = nil
        armedScreen = nil
        openedScreen = nil
        dragKind = .other
        stopWatchingDrags()
        endMonitors.forEach(NSEvent.removeMonitor)
        endMonitors.removeAll()
    }
}
