import Carbon.HIToolbox
import RookCore

/// Global shortcuts via Carbon's `RegisterEventHotKey`. Still the most reliable
/// API for this: no Input Monitoring permission, no event tap, and the system
/// swallows the keystroke so the frontmost app never sees it.
@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private let signature: OSType = 0x524F_4F4B // 'ROOK'

    private init() {}

    public enum RegistrationError: Error, CustomStringConvertible {
        case alreadyTaken(KeyCombo)

        public var description: String {
            switch self {
            case .alreadyTaken(let combo): return "'\(combo)' is already used by another app or the system"
            }
        }
    }

    public func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws(RegistrationError) {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            Self.carbonModifiers(combo.modifiers),
            EventHotKeyID(signature: signature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { throw .alreadyTaken(combo) }
        refs[id] = ref
        handlers[id] = handler
    }

    public func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            // Carbon delivers application-target events on the main thread.
            MainActor.assumeIsolated { HotkeyManager.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private static func carbonModifiers(_ m: KeyCombo.Modifiers) -> UInt32 {
        var flags = 0
        if m.contains(.command) { flags |= cmdKey }
        if m.contains(.option) { flags |= optionKey }
        if m.contains(.control) { flags |= controlKey }
        if m.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}
