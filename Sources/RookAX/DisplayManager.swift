import AppKit
import RookCore

/// A snapshot of one display, in AX coordinates.
public struct Display: Equatable, Sendable, DisplayDescribing {
    public let id: CGDirectDisplayID
    /// Stable across reboots and replugging; used to match saved layouts.
    public let uuid: String?
    public let name: String
    public let frame: CGRect
    /// Excludes the menu bar, Dock and notch area.
    public let visibleFrame: CGRect
    public let isMain: Bool
}

/// Reads displays fresh on every call. `NSScreen.screens` is cheap and this
/// avoids ever acting on a stale configuration after a plug/unplug.
@MainActor
public enum DisplayManager {
    public static var displays: [Display] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
            }
            return Display(
                id: id,
                uuid: uuid,
                name: screen.localizedName,
                frame: Coordinates.flip(screen.frame, primaryHeight: primaryHeight),
                visibleFrame: Coordinates.flip(screen.visibleFrame, primaryHeight: primaryHeight),
                isMain: screen == primary
            )
        }
    }

    /// The display holding most of `frame`, else the one under its centre, else main.
    public static func display(for frame: CGRect) -> Display? {
        let all = displays
        if let best = all.max(by: { $0.frame.overlapArea(with: frame) < $1.frame.overlapArea(with: frame) }),
           best.frame.overlapArea(with: frame) > 0 {
            return best
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return all.first { $0.frame.contains(center) } ?? all.first
    }

    /// Displays ordered left-to-right (then top-to-bottom), wrapping around.
    public static func neighbor(of display: Display, offset: Int) -> Display? {
        let ordered = displays.sorted {
            ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY)
        }
        guard ordered.count > 1, let index = ordered.firstIndex(where: { $0.id == display.id }) else { return nil }
        let next = ((index + offset) % ordered.count + ordered.count) % ordered.count
        return ordered[next]
    }
}
