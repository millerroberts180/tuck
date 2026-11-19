import AppKit
import QuartzCore
import TuckCore

/// Optional mouse-wheel improvements: smooth scrolling for notched wheels and a wheel direction that is
/// independent of the trackpad's.
///
/// Both are off by default. The event tap listens to scroll-wheel events only and exists only while one
/// of them is on. Trackpad and Magic Mouse gestures pass through untouched, as does anything scrolled
/// with a modifier held (zooming and sideways scrolling belong to the app). The display link that drives
/// a glide runs only while that glide is moving and is released as soon as it settles.
final class ScrollController: NSObject {
    /// Written into the source user-data field of every event Tuck posts, so the tap lets them through.
    private static let marker: Int64 = 0x7475_636B // "tuck"
    private static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var smoothness: ScrollSmoothness?
    private var reverseWheel = false
    private var smoother = ScrollSmoother()
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval?
    /// Where the glide started; every frame is posted there so it keeps scrolling the same view even if
    /// the pointer moves on.
    private var anchor: CGPoint = .zero

    var isActive: Bool { tap != nil }

    /// Installs or removes the tap to match the settings. Returns false when a setting is on but
    /// Accessibility has not been allowed yet.
    @discardableResult
    func update(smoothness: ScrollSmoothness?, reverseWheel: Bool) -> Bool {
        self.smoothness = smoothness
        self.reverseWheel = reverseWheel
        if let smoothness { smoother.timeConstant = smoothness.timeConstant } else { finishGlide() }
        guard smoothness != nil || reverseWheel else {
            uninstall()
            return true
        }
        guard AX.isTrusted else {
            uninstall()
            return false
        }
        install()
        return tap != nil
    }

    // MARK: Tap

    private func install() {
        guard tap == nil else { return }
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<ScrollController>.fromOpaque(info).takeUnretainedValue()
            return controller.handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
    }

    private func uninstall() {
        finishGlide()
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard type == .scrollWheel,
              event.getIntegerValueField(.eventSourceUserData) != Self.marker,
              event.flags.intersection(Self.modifierMask).isEmpty else { return pass }

        let input = ScrollInput.classify(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        )
        guard input != .gesture else { return pass }
        if reverseWheel { Self.reverse(event) }

        guard input == .wheel, smoothness != nil else { return pass }
        let vertical = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let horizontal = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        if smoother.isIdle { anchor = event.location }
        smoother.add(vertical: ScrollSmoother.distance(forPointDelta: vertical),
                     horizontal: ScrollSmoother.distance(forPointDelta: horizontal))
        startGlide()
        return nil
    }

    /// Flips every delta representation the event carries, so apps reading lines, fixed-point or pixel
    /// values all see the same direction.
    private static func reverse(_ event: CGEvent) {
        let integerFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
                                             .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
        for field in integerFields {
            event.setIntegerValueField(field, value: -event.getIntegerValueField(field))
        }
        for field in [CGEventField.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2] {
            event.setDoubleValueField(field, value: -event.getDoubleValueField(field))
        }
    }

    // MARK: Glide

    private func startGlide() {
        guard displayLink == nil else { return }
        let point = PlacementGeometry.flipped(anchor, primaryDisplayHeight: Displays.primaryHeight)
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) } ?? NSScreen.main
        guard let link = screen?.displayLink(target: self, selector: #selector(frame(_:))) else {
            smoother.reset()
            return
        }
        lastFrame = nil
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frame(_ link: CADisplayLink) {
        // The first frame after a tick has no previous timestamp; assume one display frame.
        let elapsed = lastFrame.map { link.timestamp - $0 } ?? (link.targetTimestamp - link.timestamp)
        lastFrame = link.timestamp
        let frame = smoother.advance(elapsed: elapsed)
        if frame.vertical != 0 || frame.horizontal != 0 { post(frame) }
        if frame.finished { finishGlide() }
    }

    private func post(_ frame: ScrollFrame) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: frame.vertical, wheel2: frame.horizontal, wheel3: 0) else { return }
        event.location = anchor
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cgSessionEventTap)
    }

    private func finishGlide() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrame = nil
        smoother.reset()
    }
}
