import AppKit
import TuckCore

/// Optional modifier-drag: hold the chosen keys and drag anywhere in a window to move it, or right-drag
/// (or add Shift) to resize it from the nearest corner.
///
/// Off by default. The event tap exists only while the setting is on and Accessibility is allowed; with
/// it off, Tuck sees no mouse events at all. While on, an ordinary click costs one flag comparison and is
/// passed straight through; only a modifier-click on a window is consumed.
final class WindowDragController {
    private struct Drag {
        let gesture: WindowDragGesture
        let window: AX.Window
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var modifiers: WindowDragModifiers = .controlOption
    private var drag: Drag?
    private var pendingFrame: CGRect?
    private var throttle = FrameThrottle(framesPerSecond: 60)

    var isActive: Bool { tap != nil }

    /// Installs or removes the tap to match the setting. Returns false when the setting is on but
    /// Accessibility has not been allowed yet.
    @discardableResult
    func update(enabled: Bool, modifiers: WindowDragModifiers) -> Bool {
        self.modifiers = modifiers
        guard enabled else {
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

    private func install() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<WindowDragController>.fromOpaque(info).takeUnretainedValue()
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
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        drag = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .leftMouseDown, .rightMouseDown:
            guard let kind = modifiers.gesture(for: event.flags, rightButton: type == .rightMouseDown),
                  let window = AX.window(atQuartzPoint: event.location),
                  let frame = AX.frame(of: window.element) else { return pass }
            drag = Drag(gesture: WindowDragGesture(kind: kind, pointer: event.location, windowFrame: frame), window: window)
            pendingFrame = nil
            throttle.reset()
            AX.raise(window)
            return nil

        case .leftMouseDragged, .rightMouseDragged:
            guard let drag else { return pass }
            let frame = drag.gesture.frame(for: event.location)
            pendingFrame = frame
            if throttle.shouldSend(at: ProcessInfo.processInfo.systemUptime) { send(frame, for: drag) }
            return nil

        case .leftMouseUp, .rightMouseUp:
            guard let drag else { return pass }
            if let pendingFrame { send(pendingFrame, for: drag) }
            self.drag = nil
            pendingFrame = nil
            return nil

        default:
            return pass
        }
    }

    private func send(_ frame: CGRect, for drag: Drag) {
        switch drag.gesture.kind {
        case .move:
            AX.setPosition(frame.origin, of: drag.window.element)
        case .resize:
            AX.setFrame(frame, of: drag.window)
        }
        pendingFrame = nil
    }
}
