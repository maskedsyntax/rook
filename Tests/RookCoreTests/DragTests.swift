import CoreGraphics
import Testing
@testable import RookCore

// Full frame of a 1440x900 display at the origin, AX coordinates.
private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

@Suite struct DragZoneTests {
    let zones = DragZones()

    @Test func edgesAreHalvesAndTopIsMaximize() {
        #expect(zones.action(at: CGPoint(x: 0, y: 450), display: screen) == .leftHalf)
        #expect(zones.action(at: CGPoint(x: 1439, y: 450), display: screen) == .rightHalf)
        #expect(zones.action(at: CGPoint(x: 720, y: 0), display: screen) == .maximize)
    }

    @Test func middleOfScreenIsNoZone() {
        #expect(zones.action(at: CGPoint(x: 720, y: 450), display: screen) == nil)
        #expect(zones.action(at: CGPoint(x: 10, y: 450), display: screen) == nil) // past the threshold
    }

    @Test func cornersAreQuartersFromEitherEdge() {
        #expect(zones.action(at: CGPoint(x: 0, y: 30), display: screen) == .topLeft)
        #expect(zones.action(at: CGPoint(x: 30, y: 0), display: screen) == .topLeft)
        #expect(zones.action(at: CGPoint(x: 1439, y: 899), display: screen) == .bottomRight)
        #expect(zones.action(at: CGPoint(x: 1400, y: 0), display: screen) == .topRight)
        #expect(zones.action(at: CGPoint(x: 0, y: 880), display: screen) == .bottomLeft)
    }

    @Test func bottomEdgeModes() {
        let p = { (x: CGFloat) in CGPoint(x: x, y: 899) }
        #expect(zones.action(at: p(300), display: screen) == .leftThird)
        #expect(zones.action(at: p(720), display: screen) == .centerThird)
        #expect(zones.action(at: p(1100), display: screen) == .rightThird)
        #expect(DragZones(bottom: .half).action(at: p(720), display: screen) == .bottomHalf)
        #expect(DragZones(bottom: .none).action(at: p(720), display: screen) == nil)
        // Corners still work with bottom disabled.
        #expect(DragZones(bottom: .none).action(at: p(10), display: screen) == .bottomLeft)
    }

    @Test func sharedEdgeBetweenDisplaysIsIgnored() {
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        // Cursor at the seam on the left display's right edge…
        #expect(zones.action(at: CGPoint(x: 1439, y: 450), display: screen, others: [right]) == nil)
        // …and at the right display's left edge.
        #expect(zones.action(at: CGPoint(x: 1440, y: 450), display: right, others: [screen]) == nil)
        // The outer edges still snap.
        #expect(zones.action(at: CGPoint(x: 0, y: 450), display: screen, others: [right]) == .leftHalf)
    }

    @Test func partiallySharedEdgeOpensWhereNoNeighbor() {
        // A shorter display to the right covers only y 0..<500 of the left screen's edge.
        let right = CGRect(x: 1440, y: 0, width: 800, height: 500)
        #expect(zones.action(at: CGPoint(x: 1439, y: 300), display: screen, others: [right]) == nil)
        #expect(zones.action(at: CGPoint(x: 1439, y: 700), display: screen, others: [right]) == .rightHalf)
    }

    @Test func displayAboveBlocksTopEdge() {
        let above = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        #expect(zones.action(at: CGPoint(x: 720, y: 0), display: screen, others: [above]) == nil)
    }
}

@Suite struct ModDragTests {
    let start = CGRect(x: 100, y: 100, width: 400, height: 300)
    let minSize = CGSize(width: 160, height: 100)

    @Test func nearestCorner() {
        #expect(ModDrag.Corner.nearest(to: CGPoint(x: 110, y: 110), in: start) == .topLeft)
        #expect(ModDrag.Corner.nearest(to: CGPoint(x: 490, y: 390), in: start) == .bottomRight)
        #expect(ModDrag.Corner.nearest(to: CGPoint(x: 490, y: 110), in: start) == .topRight)
    }

    @Test func move() {
        #expect(ModDrag.moved(start, by: CGVector(dx: 50, dy: -20)) == CGRect(x: 150, y: 80, width: 400, height: 300))
    }

    @Test func resizeBottomRightKeepsOrigin() {
        let r = ModDrag.resized(start, corner: .bottomRight, by: CGVector(dx: 100, dy: 50), minSize: minSize)
        #expect(r == CGRect(x: 100, y: 100, width: 500, height: 350))
    }

    @Test func resizeTopLeftKeepsOppositeCorner() {
        let r = ModDrag.resized(start, corner: .topLeft, by: CGVector(dx: -50, dy: -50), minSize: minSize)
        #expect(r.maxX == start.maxX && r.maxY == start.maxY)
        #expect(r.minX == 50 && r.minY == 50)
    }

    @Test func resizeClampsAtMinimumWithoutMovingFixedCorner() {
        let r = ModDrag.resized(start, corner: .topLeft, by: CGVector(dx: 1000, dy: 1000), minSize: minSize)
        #expect(r.size == minSize)
        #expect(r.maxX == start.maxX && r.maxY == start.maxY)
        let r2 = ModDrag.resized(start, corner: .bottomRight, by: CGVector(dx: -1000, dy: -1000), minSize: minSize)
        #expect(r2.origin == start.origin && r2.size == minSize)
    }

    @Test func unsnapKeepsCursorProportionalAndTopFixed() {
        let snapped = CGRect(x: 0, y: 25, width: 720, height: 875)
        let cursor = CGPoint(x: 360, y: 35) // middle of the title bar
        let r = ModDrag.unsnapped(current: snapped, originalSize: CGSize(width: 400, height: 300), cursor: cursor)
        #expect(r.size == CGSize(width: 400, height: 300))
        #expect(r.midX == cursor.x)
        #expect(r.minY == snapped.minY)
    }
}

@Suite struct DragConfigTests {
    @Test func defaults() throws {
        let c = try Config.parse("").get().config
        #expect(c.drag == DragConfig())
        #expect(c.drag.modifier == [.control, .command])
    }

    @Test func parsesAllFields() throws {
        let c = try Config.parse("""
            [drag]
            enabled = false
            bottom_edge = "half"
            restore_size = false
            modifier = "alt+shift"
            """).get().config
        #expect(c.drag.enabled == false)
        #expect(c.drag.bottomEdge == .half)
        #expect(c.drag.restoreSizeOnUnsnap == false)
        #expect(c.drag.modifier == [.option, .shift])
    }

    @Test func modifierNoneDisables() throws {
        let c = try Config.parse("[drag]\nmodifier = \"none\"").get().config
        #expect(c.drag.modifier == nil)
    }

    @Test func badValuesAreErrors() {
        for source in ["[drag]\nmodifier = \"ctrl+x\"", "[drag]\nbottom_edge = \"quarters\"", "[drag]\nenabled = \"yes\"", "drag = 3"] {
            if case .success = Config.parse(source) { Issue.record("expected failure for \(source)") }
        }
    }

    @Test func unknownDragKeyWarns() throws {
        let r = try Config.parse("[drag]\nenabeld = true").get()
        #expect(r.warnings.count == 1)
    }

    @Test func parseModifiers() {
        #expect(KeyCombo.parseModifiers("ctrl+cmd") == [.control, .command])
        #expect(KeyCombo.parseModifiers("ctrl+a") == nil)
        #expect(KeyCombo.parseModifiers("") == nil)
    }
}

@Suite struct UnsnapMemoryTests {
    @Test func snappedOriginalOnlyWhileUntouched() {
        var m = WindowMemory()
        let original = CGRect(x: 100, y: 100, width: 400, height: 300)
        let half = CGRect(x: 0, y: 25, width: 720, height: 875)
        m.record(window: 7, action: .leftHalf, before: original, after: half)
        #expect(m.snappedOriginal(window: 7, current: half) == original)
        #expect(m.snappedOriginal(window: 7, current: half.offsetBy(dx: 30, dy: 0)) == nil)
    }
}
