import AppKit
import RookAX
import RookCore

/// Executes a `SnapAction` against a window. Every trigger (hotkey, drag,
/// menu, later the CLI) funnels through here, and it owns the per-window
/// memory that makes restore, cycling and unsnap work across all of them.
@MainActor
final class WindowController {
    var engine = SnapEngine()
    private var memory = WindowMemory()

    /// Keyboard entry point: acts on the focused window.
    func perform(_ action: SnapAction) {
        guard let window = AXWindow.focused() else {
            NSSound.beep()
            return
        }
        perform(action, on: window, cycle: true)
    }

    /// - Parameters:
    ///   - display: target display; defaults to the one holding most of the window.
    ///   - before: frame to remember as the restore point; defaults to the current frame.
    ///   - cycle: whether repeated presses walk the action's size cycle.
    func perform(_ action: SnapAction, on window: AXWindow, display: Display? = nil, before: CGRect? = nil, cycle: Bool = false) {
        guard !window.isFullscreen,
              !window.isMinimized,
              let current = window.frame,
              let display = display ?? DisplayManager.display(for: current)
        else {
            NSSound.beep()
            return
        }
        let id = window.windowID
        let before = before ?? current

        switch action {
        case .restore:
            guard let id, let original = memory.takeRestoreFrame(window: id) else {
                NSSound.beep()
                return
            }
            window.setFrame(original)

        case .nextDisplay, .previousDisplay:
            guard let target = DisplayManager.neighbor(of: display, offset: action == .nextDisplay ? 1 : -1) else {
                NSSound.beep()
                return
            }
            let from = engine.usableArea(display.visibleFrame)
            let to = engine.usableArea(target.visibleFrame)
            let frame = SnapEngine.translate(current, from: from, to: to)
            apply(frame, to: window, area: to, action: action, id: id, before: before)

        default:
            let resolved = cycle ? id.map { memory.resolve(action, window: $0, current: current) } ?? action : action
            guard let frame = engine.frame(for: resolved, in: display.visibleFrame, current: current) else { return }
            apply(frame, to: window, area: engine.usableArea(display.visibleFrame), action: resolved, id: id, before: before)
        }
    }

    /// Where `action` would put a window on `display`, for the drag preview.
    func preview(_ action: SnapAction, display: Display, current: CGRect) -> CGRect? {
        engine.frame(for: action, in: display.visibleFrame, current: current)
    }

    /// If the window is still where rook snapped it, returns its pre-snap size
    /// and forgets the snap (dragging it away "unsnaps" it).
    func takeUnsnapSize(window: AXWindow, current: CGRect) -> CGSize? {
        guard let id = window.windowID, let original = memory.snappedOriginal(window: id, current: current) else { return nil }
        memory.forget(window: id)
        return original.size
    }

    private func apply(_ target: CGRect, to window: AXWindow, area: CGRect, action: SnapAction, id: CGWindowID?, before: CGRect) {
        var final = window.setFrame(target) ?? target

        // The app may have refused the exact size (minimum size, size increments).
        // Keep it flush with the edge it was meant to be on.
        if !final.isApproximately(target, tolerance: 1) {
            let fixed = SnapEngine.reanchor(actual: final, target: target, area: area)
            if !fixed.isApproximately(final, tolerance: 1) {
                window.setPosition(fixed.origin)
                final = window.frame ?? fixed
            }
        }

        if let id {
            memory.record(window: id, action: action, before: before, after: final)
        }
    }
}
