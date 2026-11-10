import CoreGraphics
import RookCore

public enum MouseButton: Sendable { case left, right }

public enum MouseEvent: Sendable {
    case down(MouseButton, CGPoint, KeyCombo.Modifiers)
    case dragged(MouseButton, CGPoint)
    case up(MouseButton, CGPoint)
}

/// A session-level CGEventTap for mouse buttons and drags.
///
/// The handler runs synchronously inside the tap and returns whether to
/// swallow the event, so it must be cheap: anything slow (AX calls) has to be
/// deferred unless the event is being consumed anyway. If the system disables
/// the tap (timeout, secure input), it's re-enabled immediately.
@MainActor
public final class MouseTap {
    public var handler: (MouseEvent) -> Bool = { _ in false }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public init() {}

    public var isRunning: Bool { tap != nil }

    /// Returns false if the tap couldn't be created (no Accessibility access).
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MouseTap>.fromOpaque(refcon).takeUnretainedValue()
                let location = event.location // CG global coordinates == AX coordinates
                let flags = event.flags
                // The source is added to the main run loop, so we're on the main thread.
                let consume = MainActor.assumeIsolated { me.handle(type, location, flags) }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    /// Returns whether to swallow the event.
    private func handle(_ type: CGEventType, _ location: CGPoint, _ flags: CGEventFlags) -> Bool {
        let mouseEvent: MouseEvent
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown: mouseEvent = .down(.left, location, Self.modifiers(flags))
        case .rightMouseDown: mouseEvent = .down(.right, location, Self.modifiers(flags))
        case .leftMouseDragged: mouseEvent = .dragged(.left, location)
        case .rightMouseDragged: mouseEvent = .dragged(.right, location)
        case .leftMouseUp: mouseEvent = .up(.left, location)
        case .rightMouseUp: mouseEvent = .up(.right, location)
        default: return false
        }
        return handler(mouseEvent)
    }

    /// Only the four user-facing modifiers; caps lock, fn and numpad flags are ignored.
    static func modifiers(_ flags: CGEventFlags) -> KeyCombo.Modifiers {
        var m: KeyCombo.Modifiers = []
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskCommand) { m.insert(.command) }
        return m
    }
}
