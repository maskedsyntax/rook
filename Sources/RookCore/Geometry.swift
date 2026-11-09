import CoreGraphics

/// Rook's canonical coordinate space is the one the Accessibility API and
/// CoreGraphics use: origin at the top-left of the primary display, y grows
/// downward. AppKit (`NSScreen`) uses bottom-left origin, y up. Every rect that
/// comes from AppKit goes through `Coordinates.flip` exactly once.
public enum Coordinates {
    /// Converts between AppKit and AX/CG coordinates. The transform is its own
    /// inverse, so the same call works in both directions.
    /// - Parameter primaryHeight: height of the primary (menu bar) display's full frame.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// A rect expressed as fractions (0...1) of a screen's usable area, top-left origin.
public struct UnitRect: Equatable, Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var w: CGFloat
    public var h: CGFloat

    public init(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

public struct Gaps: Equatable, Sendable {
    /// Space between windows and the screen edge.
    public var outer: CGFloat
    /// Space between two adjacent snapped windows.
    public var inner: CGFloat

    public init(outer: CGFloat, inner: CGFloat) {
        self.outer = outer; self.inner = inner
    }

    public static let none = Gaps(outer: 0, inner: 0)
}

extension CGRect {
    public func isApproximately(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }

    public var area: CGFloat { isNull || isEmpty ? 0 : width * height }

    public func overlapArea(with other: CGRect) -> CGFloat { intersection(other).area }

    /// Shrinks the rect to fit inside `bounds` if needed, then shifts it inside.
    public func clamped(into bounds: CGRect) -> CGRect {
        let w = min(width, bounds.width)
        let h = min(height, bounds.height)
        let x = min(max(minX, bounds.minX), bounds.maxX - w)
        let y = min(max(minY, bounds.minY), bounds.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Rounds edges (not width/height independently) to whole points so that
    /// adjacent snapped windows share an exact edge.
    public var pixelAligned: CGRect {
        let x0 = minX.rounded(), y0 = minY.rounded()
        let x1 = maxX.rounded(), y1 = maxY.rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
