import CoreGraphics

/// Per-window state that makes snapping feel continuous: the frame to restore
/// to, and what rook last did (so repeated presses cycle sizes).
///
/// If the user moves a window by hand after rook placed it, that new frame
/// becomes the restore point the next time rook touches it.
public struct WindowMemory: Sendable {
    struct Entry: Sendable {
        var original: CGRect
        var lastAction: SnapAction?
        var lastFrame: CGRect
    }

    /// How far a window may drift from where rook left it and still count as
    /// "untouched". Apps with size increments (Terminal) land a few points off.
    public var tolerance: CGFloat

    private var entries: [UInt32: Entry] = [:]

    public init(tolerance: CGFloat = 4) {
        self.tolerance = tolerance
    }

    private func untouched(_ entry: Entry, current: CGRect) -> Bool {
        entry.lastFrame.isApproximately(current, tolerance: tolerance)
    }

    /// The action to actually perform when `action` is requested, taking
    /// size cycling into account.
    public func resolve(_ action: SnapAction, window: UInt32, current: CGRect) -> SnapAction {
        let sequence = action.cycle
        guard sequence.count > 1,
              let entry = entries[window],
              untouched(entry, current: current),
              let last = entry.lastAction,
              let index = sequence.firstIndex(of: last)
        else { return action }
        return sequence[(index + 1) % sequence.count]
    }

    /// Call after rook moved a window from `before` to `after`.
    public mutating func record(window: UInt32, action: SnapAction?, before: CGRect, after: CGRect) {
        if var entry = entries[window], untouched(entry, current: before) {
            entry.lastAction = action
            entry.lastFrame = after
            entries[window] = entry
        } else {
            entries[window] = Entry(original: before, lastAction: action, lastFrame: after)
        }
    }

    /// The frame to restore to, if rook has moved this window. Clears the entry.
    public mutating func takeRestoreFrame(window: UInt32) -> CGRect? {
        entries.removeValue(forKey: window)?.original
    }

    public mutating func forget(window: UInt32) {
        entries.removeValue(forKey: window)
    }

    public func hasEntry(window: UInt32) -> Bool { entries[window] != nil }
}
