import AppKit
import ApplicationServices
import RookCore

/// Private but long-stable SPI (used by Rectangle, AeroSpace, yabai) that maps
/// an AX window element to its CGWindowID. It's the only reliable window identity.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

public enum AX {
    /// Caps how long any single AX call may block on an unresponsive app.
    /// Setting it on the system-wide element sets the global default.
    @MainActor public static func configureTimeout(seconds: Float = 0.25) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }
}

/// A window of another app, in AX coordinates (top-left origin of primary display).
@MainActor
public final class AXWindow {
    public let element: AXUIElement
    public let app: AXUIElement
    public let pid: pid_t

    public init(element: AXUIElement, app: AXUIElement, pid: pid_t) {
        self.element = element
        self.app = app
        self.pid = pid
    }

    /// The key window of the frontmost app, falling back to its main window.
    public static func focused() -> AXWindow? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = front.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let value = AX.copy(app, attr), CFGetTypeID(value) == AXUIElementGetTypeID() {
                return AXWindow(element: value as! AXUIElement, app: app, pid: pid)
            }
        }
        return nil
    }

    /// The standard window under a screen point (AX coordinates), ignoring
    /// rook's own windows, the desktop, and sheets/popovers' parents' chrome.
    public static func at(_ point: CGPoint) -> AXWindow? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit
        else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier else { return nil }

        let window: AXUIElement
        if (AX.copy(hit, kAXRoleAttribute) as? String) == kAXWindowRole {
            window = hit
        } else if let value = AX.copy(hit, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
            window = value as! AXUIElement
        } else {
            return nil
        }
        let result = AXWindow(element: window, app: AXUIElementCreateApplication(pid), pid: pid)
        guard result.subrole == kAXStandardWindowSubrole else { return nil }
        return result
    }

    /// Brings the window to the front and activates its app.
    public func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }

    /// For continuous updates (modifier-drag), toggle enhanced UI once around
    /// the whole gesture instead of per frame. Returns whether it was on.
    public func suspendEnhancedUI() -> Bool {
        let enhanced = (AX.copy(app, "AXEnhancedUserInterface") as? Bool) ?? false
        if enhanced { AX.set(app, "AXEnhancedUserInterface", kCFBooleanFalse) }
        return enhanced
    }

    public func resumeEnhancedUI(_ wasOn: Bool) {
        if wasOn { AX.set(app, "AXEnhancedUserInterface", kCFBooleanTrue) }
    }

    public var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    public var subrole: String? { AX.copy(element, kAXSubroleAttribute) as? String }

    public var isFullscreen: Bool {
        (AX.copy(element, "AXFullScreen") as? Bool) ?? false
    }

    public var isMinimized: Bool {
        (AX.copy(element, kAXMinimizedAttribute) as? Bool) ?? false
    }

    public var isResizable: Bool { AX.isSettable(element, kAXSizeAttribute) }

    public var frame: CGRect? {
        guard let posRef = AX.copy(element, kAXPositionAttribute),
              let sizeRef = AX.copy(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    public func setPosition(_ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) { AX.set(element, kAXPositionAttribute, value) }
    }

    public func setSize(_ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) { AX.set(element, kAXSizeAttribute, value) }
    }

    /// Sets the frame and returns what the app actually accepted.
    ///
    /// Size → position → size: the first resize lets a big window fit on a
    /// smaller target display before moving; the second fixes any clamp the
    /// app applied while it was still on the old display.
    ///
    /// `AXEnhancedUserInterface` (turned on by VoiceOver-adjacent tooling and
    /// some utilities) makes Chrome/Electron/Office animate and fight AX
    /// resizes, so it's turned off for the duration and restored after.
    @discardableResult
    public func setFrame(_ target: CGRect) -> CGRect? {
        let enhanced = (AX.copy(app, "AXEnhancedUserInterface") as? Bool) ?? false
        if enhanced { AX.set(app, "AXEnhancedUserInterface", kCFBooleanFalse) }
        defer { if enhanced { AX.set(app, "AXEnhancedUserInterface", kCFBooleanTrue) } }

        let resizable = isResizable
        if resizable { setSize(target.size) }
        setPosition(target.origin)
        if resizable { setSize(target.size) }
        return frame
    }
}
