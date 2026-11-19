import AppKit
import SwiftUI
import TuckCore

/// The gestures step: the same pretend screen as the tour, with whatever was tucked there, to swipe on:
/// down to open, down again to unfold, up to fold back and close. Each swipe goes through the real
/// `SwipeGestureTracker`, and plays no haptic, as on the real notch. Clicks work as they do in the tour.
/// The closed notch only opens here: swiping it up does nothing, so nothing happens that the step
/// doesn't teach.
struct GesturesStep: View {
    @ObservedObject var setup: SetupModel
    @ObservedObject var settings: SettingsStore

    static let chips: [ExperiencedChips.Item] = [
        .init(id: TourDesk.Gesture.open.rawValue, title: "Open", symbol: "arrow.down"),
        .init(id: TourDesk.Gesture.unfold.rawValue, title: "Unfold", symbol: "arrow.down.to.line"),
        .init(id: TourDesk.Gesture.close.rawValue, title: "Close", symbol: "arrow.up")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(title: "Swipe on the notch", detail: instruction)
            PretendScreen(setup: setup, marksSwipeArea: true, closedNotchOnlyOpens: true,
                          dropInvitation: settings.dropInvitation, haptic: setup.app.performHaptic)
            ExperiencedChips(items: Self.chips, done: Set(setup.desk.tried.map(\.rawValue)), latest: meaning,
                             placeholder: "Only two-finger swipes on a trackpad tick these off. No trackpad? Click the notch to open and close it.")
                .padding(.top, 12)
        }
    }

    private var instruction: String {
        let desk = setup.desk
        let tried = desk.tried
        if tried.count == TourDesk.Gesture.allCases.count {
            return "That's all three. They work the same way on the real notch."
        }
        switch desk.stage {
        case .collapsed:
            if !tried.contains(.open) { return "Put the pointer on the notch, then swipe down with two fingers to open Tuck." }
            return "Swipe down on the notch to open Tuck again."
        case .expanded:
            if !tried.contains(.unfold) { return "Swipe down again to unfold it and see everything in Tuck." }
            return "Swipe up on the fold to close it."
        case .full:
            return "Swipe up to fold it back, then up again to close it."
        case .tucked:
            // Only if Tuck was swiped away on the tour's screen.
            return "Tuck is tucked away. Swipe down on the notch, or click it, to bring it back."
        }
    }

    private var meaning: String? {
        switch setup.desk.latestGesture {
        case .open?: "Open: swipe down on the notch. The fold shows the first few things in Tuck."
        case .unfold?: "Unfold: swipe down again for everything, with search and Arrange windows."
        case .close?: "Close: swipe up. From the full fold, the first swipe folds it back and the next closes it."
        case nil: nil
        }
    }
}

/// Hears two-finger trackpad swipes over its own part of the setup window and turns them into Tuck's
/// swipe actions with the real `SwipeGestureTracker`, read exactly as on the notch. It takes no clicks,
/// and mouse wheels never count. Its local monitor exists only while it's in a window, and sees only
/// that window's scrolls.
struct SwipeArea: NSViewRepresentable {
    var stage: () -> SwipeGestureTracker.Stage
    var onPull: (CGFloat) -> Void = { _ in }
    var onAction: (SwipeGestureTracker.Action) -> Void

    func makeNSView(context: Context) -> SwipeAreaView {
        let view = SwipeAreaView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: SwipeAreaView, context: Context) {
        view.stage = stage
        view.onPull = onPull
        view.onAction = onAction
    }

    static func dismantleNSView(_ view: SwipeAreaView, coordinator: ()) {
        view.stop()
    }

    final class SwipeAreaView: NSView {
        var stage: () -> SwipeGestureTracker.Stage = { .collapsed }
        var onPull: (CGFloat) -> Void = { _ in }
        var onAction: (SwipeGestureTracker.Action) -> Void = { _ in }
        private let tracker = SwipeGestureTracker()
        private var monitor: Any?
        /// Whether the gesture in progress began here; its glide afterwards belongs here too.
        private var owns = false

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.handle(event) else { return event }
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Whether the event was used.
        private func handle(_ event: NSEvent) -> Bool {
            guard let window, event.hasPreciseScrollingDeltas,
                  let point = location(of: event, in: window) else { return false }
            if !event.momentumPhase.isEmpty { return owns }
            guard !event.phase.isEmpty else { return false }
            let began = event.phase.contains(.began) || event.phase.contains(.mayBegin)
            if began { owns = bounds.contains(convert(point, from: nil)) }
            guard owns else { return false }
            let inverted = event.isDirectionInvertedFromDevice
            let down = inverted ? event.scrollingDeltaY : -event.scrollingDeltaY
            let right = inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
            let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
            let current = stage()
            if let action = tracker.process(down: down, right: right, began: began, ended: ended, stage: current) {
                onAction(action)
            } else {
                onPull(ended ? 0 : tracker.pull(stage: current))
            }
            return true
        }

        /// Where the event is in the window: its own location when it's aimed at this window, or, for an
        /// event that arrived without a window (one posted to the app), its screen location.
        private func location(of event: NSEvent, in window: NSWindow) -> NSPoint? {
            if event.window === window { return event.locationInWindow }
            guard event.window == nil, window.isVisible else { return nil }
            return window.convertPoint(fromScreen: event.locationInWindow)
        }
    }
}
