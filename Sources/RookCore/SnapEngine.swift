import CoreGraphics

/// Pure frame math. All rects are in AX coordinates (top-left origin).
public struct SnapEngine: Sendable {
    public var gaps: Gaps
    /// Fraction of the usable area that `almost-maximize` covers.
    public var almostMaximizeRatio: CGFloat
    /// Points added/removed on each side by `larger` / `smaller`.
    public var resizeStep: CGFloat
    /// `smaller` never shrinks below this.
    public var minimumSize: CGSize

    public init(
        gaps: Gaps = Gaps(outer: 8, inner: 8),
        almostMaximizeRatio: CGFloat = 0.9,
        resizeStep: CGFloat = 40,
        minimumSize: CGSize = CGSize(width: 320, height: 200)
    ) {
        self.gaps = gaps
        self.almostMaximizeRatio = almostMaximizeRatio
        self.resizeStep = resizeStep
        self.minimumSize = minimumSize
    }

    /// The screen's visible frame minus outer gaps.
    public func usableArea(_ visible: CGRect) -> CGRect {
        visible.insetBy(dx: gaps.outer, dy: gaps.outer)
    }

    /// Places a fractional rect, applying half the inner gap on every edge that
    /// doesn't touch the screen edge, so two neighbours end up `inner` apart.
    public func frame(for unit: UnitRect, in visible: CGRect) -> CGRect {
        let a = usableArea(visible)
        var minX = a.minX + unit.x * a.width
        var maxX = a.minX + (unit.x + unit.w) * a.width
        var minY = a.minY + unit.y * a.height
        var maxY = a.minY + (unit.y + unit.h) * a.height

        let half = gaps.inner / 2
        let eps: CGFloat = 1e-6
        if unit.x > eps { minX += half }
        if unit.x + unit.w < 1 - eps { maxX -= half }
        if unit.y > eps { minY += half }
        if unit.y + unit.h < 1 - eps { maxY -= half }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).pixelAligned
    }

    /// Target frame for a placement action, or `nil` for actions that aren't
    /// placements within a single screen (`restore`, display moves).
    public func frame(for action: SnapAction, in visible: CGRect, current: CGRect) -> CGRect? {
        if let unit = action.unitRect {
            return frame(for: unit, in: visible)
        }
        let a = usableArea(visible)
        switch action {
        case .almostMaximize:
            let w = a.width * almostMaximizeRatio
            let h = a.height * almostMaximizeRatio
            return CGRect(x: a.midX - w / 2, y: a.midY - h / 2, width: w, height: h).pixelAligned

        case .center:
            let w = min(current.width, a.width)
            let h = min(current.height, a.height)
            return CGRect(x: a.midX - w / 2, y: a.midY - h / 2, width: w, height: h).pixelAligned

        case .larger:
            return current.insetBy(dx: -resizeStep, dy: -resizeStep)
                .intersection(a)
                .pixelAligned

        case .smaller:
            let shrunk = current.insetBy(dx: resizeStep, dy: resizeStep)
            let w = max(shrunk.width, min(minimumSize.width, current.width))
            let h = max(shrunk.height, min(minimumSize.height, current.height))
            return CGRect(x: current.midX - w / 2, y: current.midY - h / 2, width: w, height: h)
                .pixelAligned

        default:
            return nil
        }
    }

    /// Maps a frame from one screen to another keeping its relative position
    /// and size, so a left-half stays a left-half on a differently sized display.
    public static func translate(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return frame.clamped(into: target) }
        let sx = target.width / source.width
        let sy = target.height / source.height
        let mapped = CGRect(
            x: target.minX + (frame.minX - source.minX) * sx,
            y: target.minY + (frame.minY - source.minY) * sy,
            width: frame.width * sx,
            height: frame.height * sy
        )
        return mapped.clamped(into: target).pixelAligned
    }

    /// Apps can refuse a size (minimum sizes, Terminal's character grid). Given
    /// the frame the app actually accepted, keep the window flush with whatever
    /// screen edge the target was flush with; otherwise centre it in the target.
    public static func reanchor(actual: CGRect, target: CGRect, area: CGRect) -> CGRect {
        let tol: CGFloat = 1

        func axis(actualLen: CGFloat, tMin: CGFloat, tMax: CGFloat, aMin: CGFloat, aMax: CGFloat) -> CGFloat {
            let touchesMin = abs(tMin - aMin) <= tol
            let touchesMax = abs(tMax - aMax) <= tol
            if touchesMin { return tMin }
            if touchesMax { return tMax - actualLen }
            return (tMin + tMax) / 2 - actualLen / 2
        }

        let x = abs(actual.width - target.width) <= tol
            ? target.minX
            : axis(actualLen: actual.width, tMin: target.minX, tMax: target.maxX, aMin: area.minX, aMax: area.maxX)
        let y = abs(actual.height - target.height) <= tol
            ? target.minY
            : axis(actualLen: actual.height, tMin: target.minY, tMax: target.maxY, aMin: area.minY, aMax: area.maxY)

        return CGRect(x: x, y: y, width: actual.width, height: actual.height)
            .clamped(into: area)
            .pixelAligned
    }
}
