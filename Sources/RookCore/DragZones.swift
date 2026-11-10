import CoreGraphics

/// What dragging a window to the bottom screen edge does.
public enum BottomEdge: String, CaseIterable, Sendable {
    case thirds
    case half
    case none
}

/// Maps a cursor position during a window drag to a snap action. Pure: works
/// on display frames in AX coordinates.
public struct DragZones: Equatable, Sendable {
    /// How close to the edge (points) the cursor must be. The cursor stops at
    /// the screen edge, so this only needs to absorb a little slop.
    public var edgeThreshold: CGFloat
    /// Along an edge, how far from a corner still counts as that corner.
    public var cornerSize: CGFloat
    public var bottom: BottomEdge

    public init(edgeThreshold: CGFloat = 4, cornerSize: CGFloat = 80, bottom: BottomEdge = .thirds) {
        self.edgeThreshold = edgeThreshold
        self.cornerSize = cornerSize
        self.bottom = bottom
    }

    /// - Parameters:
    ///   - point: cursor, AX coordinates.
    ///   - display: full frame of the display under the cursor.
    ///   - others: the other displays' frames. Edges shared with another
    ///     display are ignored, so dragging a window across monitors doesn't
    ///     flash a preview at the seam.
    public func action(at point: CGPoint, display f: CGRect, others: [CGRect] = []) -> SnapAction? {
        let t = edgeThreshold
        // The cursor's maximum coordinate is maxX - 1 / maxY - 1.
        let atLeft = point.x <= f.minX + t && isOpen(.left, f, point, others)
        let atRight = point.x >= f.maxX - 1 - t && isOpen(.right, f, point, others)
        let atTop = point.y <= f.minY + t && isOpen(.top, f, point, others)
        let atBottom = point.y >= f.maxY - 1 - t && isOpen(.bottom, f, point, others)

        let c = cornerSize
        let nearTop = point.y <= f.minY + c
        let nearBottom = point.y >= f.maxY - c
        let nearLeft = point.x <= f.minX + c
        let nearRight = point.x >= f.maxX - c

        if atLeft { return nearTop ? .topLeft : nearBottom ? .bottomLeft : .leftHalf }
        if atRight { return nearTop ? .topRight : nearBottom ? .bottomRight : .rightHalf }
        if atTop { return nearLeft ? .topLeft : nearRight ? .topRight : .maximize }
        if atBottom {
            if nearLeft { return .bottomLeft }
            if nearRight { return .bottomRight }
            switch bottom {
            case .half: return .bottomHalf
            case .none: return nil
            case .thirds:
                let third = (point.x - f.minX) / f.width
                return third < 1.0 / 3.0 ? .leftThird : third < 2.0 / 3.0 ? .centerThird : .rightThird
            }
        }
        return nil
    }

    enum Edge { case left, right, top, bottom }

    /// An edge is open if no other display continues past it at the cursor's position.
    func isOpen(_ edge: Edge, _ f: CGRect, _ p: CGPoint, _ others: [CGRect]) -> Bool {
        let tol: CGFloat = 1
        return !others.contains { o in
            switch edge {
            case .left: return abs(o.maxX - f.minX) <= tol && p.y >= o.minY && p.y < o.maxY
            case .right: return abs(o.minX - f.maxX) <= tol && p.y >= o.minY && p.y < o.maxY
            case .top: return abs(o.maxY - f.minY) <= tol && p.x >= o.minX && p.x < o.maxX
            case .bottom: return abs(o.minY - f.maxY) <= tol && p.x >= o.minX && p.x < o.maxX
            }
        }
    }
}

/// Math for modifier+drag move and resize.
public enum ModDrag {
    public enum Corner: Sendable, Equatable {
        case topLeft, topRight, bottomLeft, bottomRight

        /// The corner of `frame` in whose quadrant `point` lies.
        public static func nearest(to point: CGPoint, in frame: CGRect) -> Corner {
            let left = point.x < frame.midX
            let top = point.y < frame.midY
            switch (left, top) {
            case (true, true): return .topLeft
            case (false, true): return .topRight
            case (true, false): return .bottomLeft
            case (false, false): return .bottomRight
            }
        }
    }

    public static func moved(_ start: CGRect, by delta: CGVector) -> CGRect {
        start.offsetBy(dx: delta.dx, dy: delta.dy).pixelAligned
    }

    /// Drags `corner` by `delta`, keeping the opposite corner fixed and never
    /// going below `minSize` (the fixed corner stays put when clamped).
    public static func resized(_ start: CGRect, corner: Corner, by delta: CGVector, minSize: CGSize) -> CGRect {
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        switch corner {
        case .topLeft:
            minX = min(start.minX + delta.dx, maxX - minSize.width)
            minY = min(start.minY + delta.dy, maxY - minSize.height)
        case .topRight:
            maxX = max(start.maxX + delta.dx, minX + minSize.width)
            minY = min(start.minY + delta.dy, maxY - minSize.height)
        case .bottomLeft:
            minX = min(start.minX + delta.dx, maxX - minSize.width)
            maxY = max(start.maxY + delta.dy, minY + minSize.height)
        case .bottomRight:
            maxX = max(start.maxX + delta.dx, minX + minSize.width)
            maxY = max(start.maxY + delta.dy, minY + minSize.height)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).pixelAligned
    }

    /// When a snapped window is dragged away it returns to its pre-snap size.
    /// Keep the cursor at the same relative spot along the title bar so the
    /// window doesn't jump out from under it.
    public static func unsnapped(current: CGRect, originalSize: CGSize, cursor: CGPoint) -> CGRect {
        let fx = current.width > 0 ? (cursor.x - current.minX) / current.width : 0.5
        let x = cursor.x - fx * originalSize.width
        let y = current.minY
        return CGRect(x: x, y: y, width: originalSize.width, height: originalSize.height).pixelAligned
    }
}
