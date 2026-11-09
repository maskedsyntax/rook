import CoreGraphics

/// Everything rook can do to a single window. Raw values are the names used in
/// the config file (`"ctrl+alt+left" = "left-half"`).
public enum SnapAction: String, CaseIterable, Sendable {
    case leftHalf = "left-half"
    case rightHalf = "right-half"
    case topHalf = "top-half"
    case bottomHalf = "bottom-half"

    case leftThird = "left-third"
    case centerThird = "center-third"
    case rightThird = "right-third"
    case leftTwoThirds = "left-two-thirds"
    case rightTwoThirds = "right-two-thirds"

    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"

    case maximize
    case almostMaximize = "almost-maximize"
    case center

    case larger
    case smaller

    case restore
    case nextDisplay = "next-display"
    case previousDisplay = "previous-display"

    /// Fixed grid placements. `nil` for actions whose frame depends on the
    /// current window or on other displays.
    public var unitRect: UnitRect? {
        let third: CGFloat = 1.0 / 3.0
        switch self {
        case .leftHalf: return UnitRect(x: 0, y: 0, w: 0.5, h: 1)
        case .rightHalf: return UnitRect(x: 0.5, y: 0, w: 0.5, h: 1)
        case .topHalf: return UnitRect(x: 0, y: 0, w: 1, h: 0.5)
        case .bottomHalf: return UnitRect(x: 0, y: 0.5, w: 1, h: 0.5)
        case .leftThird: return UnitRect(x: 0, y: 0, w: third, h: 1)
        case .centerThird: return UnitRect(x: third, y: 0, w: third, h: 1)
        case .rightThird: return UnitRect(x: 2 * third, y: 0, w: third, h: 1)
        case .leftTwoThirds: return UnitRect(x: 0, y: 0, w: 2 * third, h: 1)
        case .rightTwoThirds: return UnitRect(x: third, y: 0, w: 2 * third, h: 1)
        case .topLeft: return UnitRect(x: 0, y: 0, w: 0.5, h: 0.5)
        case .topRight: return UnitRect(x: 0.5, y: 0, w: 0.5, h: 0.5)
        case .bottomLeft: return UnitRect(x: 0, y: 0.5, w: 0.5, h: 0.5)
        case .bottomRight: return UnitRect(x: 0.5, y: 0.5, w: 0.5, h: 0.5)
        case .maximize: return UnitRect(x: 0, y: 0, w: 1, h: 1)
        default: return nil
        }
    }

    /// Pressing the same key repeatedly walks this sequence (½ → ⅔ → ⅓).
    public var cycle: [SnapAction] {
        switch self {
        case .leftHalf: return [.leftHalf, .leftTwoThirds, .leftThird]
        case .rightHalf: return [.rightHalf, .rightTwoThirds, .rightThird]
        default: return [self]
        }
    }
}
