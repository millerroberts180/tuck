import AppKit
import ApplicationServices
import TuckCore

/// Thin wrappers over the Accessibility API. Frames read and written here are in Quartz global
/// coordinates (origin top-left of the primary display, y down); `Displays` converts to AppKit.
enum AX {
    /// Every call into another app waits at most this long, so an unresponsive app can never stall Tuck
    /// (or the mouse, when called from the window-drag event tap).
    static let messagingTimeout: Float = 0.25

    static var isTrusted: Bool { AXIsProcessTrusted() }

    private(set) static var hasPrompted = false

    /// Shows the system prompt that leads to Accessibility settings, at most once per launch and only
    /// from a deliberate action (setup's permission step is one); after that the fold's Allow Tuck
    /// button and status line explain it.
    static func promptForTrust() {
        guard !hasPrompted else { return }
        hasPrompted = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// What System Settings calls the list Tuck must be on: macOS 27 renamed Privacy & Security's
    /// Accessibility to Device Control and Data Access. The permission and its link are unchanged.
    static let paneName: String = {
        if #available(macOS 27, *) { return "Device Control and Data Access" }
        return "Accessibility"
    }()

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    struct Window {
        let element: AXUIElement
        let app: AXUIElement
        let pid: pid_t

        /// Stable for the lifetime of the window; used to remember its frame before Tuck placed it.
        var key: String { "\(pid):\(CFHash(element))" }
    }

    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

    /// The focused window of the frontmost app, ignoring Tuck itself.
    static func focusedWindow() -> Window? {
        guard let running = NSWorkspace.shared.frontmostApplication,
              running.processIdentifier != getpid() else { return nil }
        return focusedWindow(of: running.processIdentifier)
    }

    /// The focused window of this app. A caller that has already read the app in front passes its pid, so
    /// the window can only be that app's, even if another comes forward in between.
    static func focusedWindow(of pid: pid_t) -> Window? {
        let app = application(pid)
        // Never a minimised window, nor one parked off screen, when falling back: one just tucked must not
        // be named, tucked or arranged again. (A focused one parked off screen is the caller's to pass over.)
        let window = element(app, kAXFocusedWindowAttribute)
            ?? element(app, kAXMainWindowAttribute)
            ?? elements(app, kAXWindowsAttribute).first { bool($0, kAXMinimizedAttribute) != true && !isOutOfSight($0) }
        return window.map { Window(element: $0, app: app, pid: pid) }
    }

    /// The window under a point, ignoring Tuck's own windows.
    static func window(atQuartzPoint point: CGPoint) -> Window? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid != getpid() else { return nil }
        let window = string(hit, kAXRoleAttribute) == (kAXWindowRole as String) ? hit : element(hit, kAXWindowAttribute)
        guard let window, string(window, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String) else { return nil }
        return Window(element: window, app: application(pid), pid: pid)
    }

    /// Every window of a running app; used to find windows parked before a relaunch, when Tuck no longer
    /// holds their element.
    static func windows(bundleID: String) -> [Window] {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return [] }
        let app = application(running.processIdentifier)
        return elements(app, kAXWindowsAttribute).map { Window(element: $0, app: app, pid: running.processIdentifier) }
    }

    // MARK: Frames

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute), let size = size(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Size, then position, then size again: the first resize can be clamped by the old position near a
    /// screen edge, and the second applies it once the window has moved. Apps with assistive "enhanced
    /// UI" enabled animate and fight frame changes, so that is switched off for the duration.
    @discardableResult
    static func setFrame(_ frame: CGRect, of window: Window) -> Bool {
        withoutEnhancedUserInterface(window.app) {
            let sized = setSize(frame.size, of: window.element)
            let moved = setPosition(frame.origin, of: window.element)
            setSize(frame.size, of: window.element)
            return sized || moved
        }
    }

    /// Moves a window without resizing it, with "enhanced UI" off as for `setFrame`.
    @discardableResult
    static func move(_ window: Window, to origin: CGPoint) -> Bool {
        withoutEnhancedUserInterface(window.app) { setPosition(origin, of: window.element) }
    }

    private static func withoutEnhancedUserInterface<T>(_ app: AXUIElement, _ body: () -> T) -> T {
        let enhanced = bool(app, "AXEnhancedUserInterface") == true
        if enhanced { set(app, "AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { set(app, "AXEnhancedUserInterface", kCFBooleanTrue) } }
        return body()
    }

    @discardableResult
    static func setPosition(_ origin: CGPoint, of window: AXUIElement) -> Bool {
        var value = origin
        guard let axValue = AXValueCreate(.cgPoint, &value) else { return false }
        return set(window, kAXPositionAttribute, axValue)
    }

    @discardableResult
    static func setSize(_ size: CGSize, of window: AXUIElement) -> Bool {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { return false }
        return set(window, kAXSizeAttribute, axValue)
    }

    // MARK: State

    static func title(of window: AXUIElement) -> String { string(window, kAXTitleAttribute) ?? "" }

    /// Whether no more than a sliver of a window shows on any display: parked off screen by Tuck, now or
    /// before a relaunch. False when its frame can't be read.
    static func isOutOfSight(_ window: AXUIElement) -> Bool {
        frame(of: window).map(Displays.isOutOfSight) ?? false
    }

    /// Whether the app lets this attribute be changed (a window's position, say).
    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    /// Whether a window element still exists. Only an explicit "invalid element" answer counts as gone;
    /// a timeout or any other error means the app could not be asked, not that the window closed.
    static func state(of window: AXUIElement) -> WindowElementState {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &value) {
        case .success: return .alive
        case .invalidUIElement: return .destroyed
        default: return .unresponsive
        }
    }

    /// Hides an app (all its windows vanish in place, with no Dock animation). The app's own hidden
    /// state decides success: the workspace's request can report failure and still hide it.
    @discardableResult
    static func hide(_ window: Window) -> Bool {
        let requested = NSRunningApplication(processIdentifier: window.pid)?.hide() ?? false
        if bool(window.app, kAXHiddenAttribute) == true { return true }
        if set(window.app, kAXHiddenAttribute, kCFBooleanTrue) { return true }
        return requested && bool(window.app, kAXHiddenAttribute) != false
    }

    static func setMinimised(_ minimised: Bool, _ window: AXUIElement) -> Bool {
        set(window, kAXMinimizedAttribute, minimised ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// An app reports itself hidden a few milliseconds before its windows actually leave the screen, and
    /// a window minimised before then is minimised in view. Waits, at most `timeout`, until none of the
    /// app's ordinary windows is on screen. (Its menu bar extras, on other layers, stay.)
    static func waitUntilOffScreen(_ pid: pid_t, timeout: TimeInterval = 0.3) -> Bool {
        waitUntil(timeout) { !hasWindowOnScreen(pid) }
    }

    /// An app shown again is only brought forward once its windows are back: asked any sooner, it
    /// accepts and stays behind. Waits, at most `timeout`, until one of its ordinary windows is on screen.
    static func waitUntilOnScreen(_ pid: pid_t, timeout: TimeInterval = 0.3) -> Bool {
        waitUntil(timeout) { hasWindowOnScreen(pid) }
    }

    private static func hasWindowOnScreen(_ pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // Quartz returns these bridged CFNumbers. Reading them as NSNumber avoids a fragile
        // architecture-dependent cast to `pid_t` when this runs against another process.
        return list.contains { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = info[kCGWindowLayer as String] as? NSNumber else { return false }
            return owner.int32Value == pid && layer.intValue == 0
        }
    }

    /// Whether the person has clicked or typed since this moment (system uptime), and so may have
    /// chosen another app themselves.
    static func personClickedOrTyped(since uptime: TimeInterval) -> Bool {
        let elapsed = ProcessInfo.processInfo.systemUptime - uptime
        let events: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        return events.contains { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < elapsed }
    }

    /// A minimise request is answered before the app has acted on it. Waits, at most `timeout`, until
    /// every one of these windows reports itself minimised.
    static func waitUntilMinimised(_ windows: [AXUIElement], timeout: TimeInterval = 0.3) -> Bool {
        waitUntil(timeout) { windows.allSatisfy { bool($0, kAXMinimizedAttribute) == true } }
    }

    /// Checks every 2 ms. Only used for the few milliseconds an app takes to act on a request.
    private static func waitUntil(_ timeout: TimeInterval, _ done: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !done() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            usleep(2_000)
        }
        return true
    }

    /// Makes an app frontmost again, as it was before it was hidden for a moment. Setting AXFrontmost
    /// can report success without actually activating the app, so always follow it with Launch Services.
    static func makeFrontmost(_ app: AXUIElement, pid: pid_t) {
        _ = set(app, kAXFrontmostAttribute, kCFBooleanTrue)
        _ = NSRunningApplication(processIdentifier: pid)?.activate()
    }

    static func raise(_ window: Window) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    /// Gives a window the keyboard: raised, made its app's main window, and its app brought forward the
    /// way `makeFrontmost` does it, since a plain activation can be dropped. Being raised and made main
    /// doesn't always move an app's focus: one already in front can keep it in the window that had it,
    /// even one that has just gone off screen. Such an app is also told which window to focus.
    static func focus(_ window: Window) {
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        set(window.element, kAXMainAttribute, kCFBooleanTrue)
        if let focused = element(window.app, kAXFocusedWindowAttribute), !CFEqual(focused, window.element) {
            set(window.app, kAXFocusedWindowAttribute, window.element)
        }
        makeFrontmost(window.app, pid: window.pid)
    }

    // MARK: Attribute access

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement) // type checked above
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let value = copy(element, attribute), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as? [AnyObject] ?? []).compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    @discardableResult
    private static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }
}

/// Display lookups in AppKit coordinates, plus conversion to and from the Quartz space AX uses.
enum Displays {
    /// Height of the primary display (the one whose origin is the global origin).
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func appKit(_ quartz: CGRect) -> CGRect { PlacementGeometry.flipped(quartz, primaryDisplayHeight: primaryHeight) }
    static func quartz(_ appKit: CGRect) -> CGRect { PlacementGeometry.flipped(appKit, primaryDisplayHeight: primaryHeight) }

    /// Every display's frame, in Quartz coordinates.
    static var quartzFrames: [CGRect] { NSScreen.screens.map { quartz($0.frame) } }

    /// The frame (Quartz) of the display with this identifier, while it is connected.
    static func quartzFrame(ofDisplay identifier: String?) -> CGRect? {
        guard let identifier else { return nil }
        return NSScreen.screens.first { String($0.displayID) == identifier }.map { quartz($0.frame) }
    }

    /// Whether no more than a sliver of a frame (Quartz) shows on any display (see `OffScreenParking`).
    static func isOutOfSight(_ quartzFrame: CGRect) -> Bool {
        OffScreenParking.isOutOfSight(quartzFrame, displays: quartzFrames)
    }

    /// The display holding most of a frame.
    static func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.max { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }
            .flatMap { area($0.frame.intersection(frame)) > 0 ? $0 : NSScreen.main }
    }

    /// The display after this one, ordered left to right, wrapping round.
    static func next(after screen: NSScreen) -> NSScreen? {
        let ordered = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard let id = PlacementGeometry.nextDisplay(after: screen.displayID, in: ordered.map(\.displayID)) else { return nil }
        return ordered.first { $0.displayID == id }
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
}
