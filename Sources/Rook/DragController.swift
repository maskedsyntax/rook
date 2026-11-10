import AppKit
import RookAX
import RookCore
import RookInput
import RookUI

/// Turns raw mouse events into two gestures:
///
/// **Drag-to-snap.** The user drags a window by its title bar as usual; rook
/// never consumes these events. On the first real movement it looks up the
/// window under the cursor (deferred, so clicks never wait on AX), then checks
/// once that the window is actually moving with the cursor, which rules out text
/// selection, edge resizes and scrollbars. From then on, cursor position alone
/// drives the preview, and mouse-up snaps.
///
/// **Modifier-drag.** With the configured modifiers held, rook consumes the
/// click and moves (left) or resizes (right) the window under the cursor.
/// AX updates are coalesced: at most one is in flight, always targeting the
/// latest cursor position, so the window keeps up instead of lagging behind a
/// queue of stale moves.
@MainActor
final class DragController {
    private struct Drag {
        let window: AXWindow
        var startFrame: CGRect
        let startMouse: CGPoint
        let displays: [Display]
    }

    private struct ModGesture {
        let window: AXWindow
        var startFrame: CGRect
        let startMouse: CGPoint
        let displays: [Display]
        let enhancedUI: Bool
    }

    private enum State {
        case idle
        /// Left button down, no movement yet.
        case pressed(CGPoint)
        /// Window lookup scheduled.
        case probing
        /// Window found; waiting to confirm it's moving with the cursor.
        case candidate(Drag, checking: Bool)
        /// Confirmed title-bar drag; zones are live.
        case moving(Drag)
        /// Not a window move (selection, resize…); ignore until mouse-up.
        case ignoring
        case modMove(ModGesture)
        case modResize(ModGesture, ModDrag.Corner)
    }

    var config = DragConfig() {
        didSet { refreshTap() }
    }
    var active = false {
        didSet { refreshTap() }
    }
    /// Set when the tap couldn't be created.
    private(set) var tapError: String?

    private let windows: WindowController
    private let overlay = SnapOverlay()
    private let tap = MouseTap()
    private var state: State = .idle
    private var zone: (action: SnapAction, display: Display)?
    private var pendingPoint: CGPoint?
    private var applyScheduled = false

    private static let minModResize = CGSize(width: 160, height: 100)

    init(windows: WindowController) {
        self.windows = windows
        tap.handler = { [unowned self] event in handle(event) }
    }

    private func refreshTap() {
        let wanted = active && (config.enabled || config.modifier != nil)
        if wanted, !tap.isRunning {
            tapError = tap.start() ? nil : "couldn't watch the mouse (check Accessibility access)"
        } else if !wanted, tap.isRunning {
            reset()
            tap.stop()
        }
    }

    // MARK: Event handling (runs inside the event tap: keep it fast)

    private func handle(_ event: MouseEvent) -> Bool {
        switch event {
        case let .down(button, point, modifiers):
            return mouseDown(button, point, modifiers)
        case let .dragged(button, point):
            return mouseDragged(button, point)
        case let .up(button, point):
            return mouseUp(button, point)
        }
    }

    private func mouseDown(_ button: MouseButton, _ point: CGPoint, _ modifiers: KeyCombo.Modifiers) -> Bool {
        reset() // recovers if a previous mouse-up was missed

        if let mod = config.modifier, modifiers == mod {
            // The user explicitly asked for rook here, so a synchronous AX lookup is fine.
            guard let window = AXWindow.at(point), !window.isFullscreen, let frame = window.frame else { return false }
            window.raise()
            var gesture = ModGesture(
                window: window, startFrame: frame, startMouse: point,
                displays: DisplayManager.displays, enhancedUI: window.suspendEnhancedUI()
            )
            switch button {
            case .left:
                if let unsnapped = unsnap(window, frame: frame, cursor: point) { gesture.startFrame = unsnapped }
                state = .modMove(gesture)
            case .right:
                state = .modResize(gesture, .nearest(to: point, in: frame))
            }
            return true
        }

        if button == .left, config.enabled { state = .pressed(point) }
        return false
    }

    private func mouseDragged(_ button: MouseButton, _ point: CGPoint) -> Bool {
        switch state {
        case .pressed(let start):
            guard hypot(point.x - start.x, point.y - start.y) > 4 else { return false }
            state = .probing
            // The window under the cursor right now is the one being dragged.
            DispatchQueue.main.async { [weak self] in self?.probe(at: point) }
            return false

        case .candidate(let drag, checking: false):
            guard hypot(point.x - drag.startMouse.x, point.y - drag.startMouse.y) > 10 else { return false }
            state = .candidate(drag, checking: true)
            DispatchQueue.main.async { [weak self] in self?.confirm(drag) }
            return false

        case .moving(let drag):
            updateZone(point, window: drag.window, current: drag.startFrame, displays: drag.displays)
            return false

        case .modMove(let gesture):
            guard button == .left else { return true }
            if config.enabled {
                updateZone(point, window: gesture.window, current: gesture.startFrame, displays: gesture.displays)
            }
            schedule(point)
            return true

        case .modResize:
            guard button == .right else { return true }
            schedule(point)
            return true

        case .idle, .probing, .candidate, .ignoring:
            return false
        }
    }

    private func mouseUp(_ button: MouseButton, _ point: CGPoint) -> Bool {
        let finished = state
        let target = zone
        state = .idle
        zone = nil
        overlay.hide()

        switch finished {
        case .moving(let drag):
            if let target {
                // Let the mouse-up reach the window server first so the app's
                // own drag ends before we set the final frame.
                DispatchQueue.main.async { [weak self] in
                    self?.windows.perform(target.action, on: drag.window, display: target.display, before: drag.startFrame)
                }
            }
            return false

        case .modMove(let gesture):
            flush(gesture, corner: nil, at: point)
            gesture.window.resumeEnhancedUI(gesture.enhancedUI)
            if let target {
                windows.perform(target.action, on: gesture.window, display: target.display, before: gesture.startFrame)
            }
            return true

        case .modResize(let gesture, let corner):
            flush(gesture, corner: corner, at: point)
            gesture.window.resumeEnhancedUI(gesture.enhancedUI)
            return true

        default:
            return false
        }
    }

    // MARK: Deferred work

    private func probe(at point: CGPoint) {
        guard case .probing = state else { return }
        guard let window = AXWindow.at(point), !window.isFullscreen, let frame = window.frame else {
            state = .ignoring
            return
        }
        state = .candidate(Drag(window: window, startFrame: frame, startMouse: point, displays: DisplayManager.displays), checking: false)
    }

    /// One AX read decides whether this is a title-bar move: the window must
    /// have moved and kept its size.
    private func confirm(_ drag: Drag) {
        guard case .candidate(let current, checking: true) = state, current.window === drag.window else { return }
        guard let frame = drag.window.frame else {
            state = .ignoring
            return
        }
        let sizeSame = abs(frame.width - drag.startFrame.width) <= 1 && abs(frame.height - drag.startFrame.height) <= 1
        let moved = hypot(frame.minX - drag.startFrame.minX, frame.minY - drag.startFrame.minY) > 2

        if sizeSame && moved {
            var confirmed = drag
            if let cursor = CGEvent(source: nil)?.location,
               let unsnapped = unsnap(drag.window, frame: frame, cursor: cursor) {
                confirmed.startFrame = unsnapped
            } else {
                confirmed.startFrame = frame
            }
            state = .moving(confirmed)
        } else if !sizeSame {
            state = .ignoring
        } else {
            // Not moving yet. Some apps start the window drag late, so look again
            // on the next movement, up to a point.
            let cursor = CGEvent(source: nil)?.location ?? drag.startMouse
            let travelled = hypot(cursor.x - drag.startMouse.x, cursor.y - drag.startMouse.y)
            state = travelled > 60 ? .ignoring : .candidate(drag, checking: false)
        }
    }

    /// Gives a snapped window back its original size, keeping it under the cursor.
    private func unsnap(_ window: AXWindow, frame: CGRect, cursor: CGPoint) -> CGRect? {
        guard config.restoreSizeOnUnsnap,
              let size = windows.takeUnsnapSize(window: window, current: frame),
              size != frame.size
        else { return nil }
        let target = ModDrag.unsnapped(current: frame, originalSize: size, cursor: cursor)
        return window.setFrame(target) ?? target
    }

    private func updateZone(_ point: CGPoint, window: AXWindow, current: CGRect, displays: [Display]) {
        guard let display = displays.first(where: { $0.frame.contains(point) }) else { return }
        let others = displays.filter { $0.id != display.id }.map(\.frame)
        guard let action = config.zones.action(at: point, display: display.frame, others: others),
              let frame = windows.preview(action, display: display, current: current)
        else {
            zone = nil
            overlay.hide()
            return
        }
        zone = (action, display)
        overlay.show(frame)
    }

    // MARK: Coalesced modifier-drag updates

    private func schedule(_ point: CGPoint) {
        pendingPoint = point
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            applyScheduled = false
            switch state {
            case .modMove(let g): apply(g, corner: nil)
            case .modResize(let g, let c): apply(g, corner: c)
            default: pendingPoint = nil
            }
        }
    }

    /// Applies the final cursor position synchronously at mouse-up.
    private func flush(_ gesture: ModGesture, corner: ModDrag.Corner?, at point: CGPoint) {
        pendingPoint = point
        apply(gesture, corner: corner)
    }

    private func apply(_ gesture: ModGesture, corner: ModDrag.Corner?) {
        guard let point = pendingPoint else { return }
        pendingPoint = nil
        let delta = CGVector(dx: point.x - gesture.startMouse.x, dy: point.y - gesture.startMouse.y)
        guard let corner else {
            gesture.window.setPosition(ModDrag.moved(gesture.startFrame, by: delta).origin)
            return
        }
        let frame = ModDrag.resized(gesture.startFrame, corner: corner, by: delta, minSize: Self.minModResize)
        gesture.window.setSize(frame.size)
        if corner != .bottomRight { gesture.window.setPosition(frame.origin) }
    }

    private func reset() {
        switch state {
        case .modMove(let g), .modResize(let g, _): g.window.resumeEnhancedUI(g.enhancedUI)
        default: break
        }
        state = .idle
        zone = nil
        pendingPoint = nil
        overlay.hide()
    }
}
