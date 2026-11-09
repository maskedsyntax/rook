import AppKit
import RookAX
import RookCore

/// Executes a `SnapAction` against the focused window. Every trigger (hotkey,
/// drag, menu, later the CLI) funnels through `perform`.
@MainActor
final class WindowController {
    var engine = SnapEngine()
    private var memory = WindowMemory()

    func perform(_ action: SnapAction) {
        guard let window = AXWindow.focused(),
              !window.isFullscreen,
              !window.isMinimized,
              let current = window.frame,
              let display = DisplayManager.display(for: current)
        else {
            NSSound.beep()
            return
        }
        let id = window.windowID

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
            apply(frame, to: window, area: to, action: action, id: id, before: current)

        default:
            let resolved = id.map { memory.resolve(action, window: $0, current: current) } ?? action
            guard let frame = engine.frame(for: resolved, in: display.visibleFrame, current: current) else { return }
            apply(frame, to: window, area: engine.usableArea(display.visibleFrame), action: resolved, id: id, before: current)
        }
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
