import CoreGraphics
import Testing
@testable import RookCore

// A 1440x900 laptop screen with a 25pt menu bar, in AX coordinates.
let laptopVisible = CGRect(x: 0, y: 25, width: 1440, height: 875)

@Suite struct CoordinatesTests {
    @Test func flipIsSelfInverse() {
        let r = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(Coordinates.flip(Coordinates.flip(r, primaryHeight: 900), primaryHeight: 900) == r)
    }

    @Test func primaryVisibleFrameFlipsBelowMenuBar() {
        // AppKit: visibleFrame starts at the bottom (no Dock) and stops under the menu bar.
        let appKit = CGRect(x: 0, y: 0, width: 1440, height: 875)
        #expect(Coordinates.flip(appKit, primaryHeight: 900) == laptopVisible)
    }

    @Test func secondaryDisplayAboveAndLeftOfPrimary() {
        // External 2560x1440 sitting above-left of the primary: AppKit y = 900 (above).
        let appKit = CGRect(x: -1000, y: 900, width: 2560, height: 1440)
        let ax = Coordinates.flip(appKit, primaryHeight: 900)
        #expect(ax == CGRect(x: -1000, y: -1440, width: 2560, height: 1440))
    }

    @Test func secondaryDisplayBelowPrimary() {
        let appKit = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        #expect(Coordinates.flip(appKit, primaryHeight: 900) == CGRect(x: 0, y: 900, width: 1920, height: 1080))
    }
}

@Suite struct SnapEngineTests {
    let noGaps = SnapEngine(gaps: .none)
    let gapped = SnapEngine(gaps: Gaps(outer: 10, inner: 10))

    @Test func halvesWithoutGapsTile() {
        let l = noGaps.frame(for: .leftHalf, in: laptopVisible, current: .zero)!
        let r = noGaps.frame(for: .rightHalf, in: laptopVisible, current: .zero)!
        #expect(l == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(r == CGRect(x: 720, y: 25, width: 720, height: 875))
    }

    @Test func halvesWithGaps() {
        let l = gapped.frame(for: .leftHalf, in: laptopVisible, current: .zero)!
        let r = gapped.frame(for: .rightHalf, in: laptopVisible, current: .zero)!
        #expect(l.minX == 10)
        #expect(r.maxX == 1430)
        #expect(r.minX - l.maxX == 10) // exactly one inner gap between them
        #expect(l.minY == 35 && l.maxY == 890)
    }

    @Test func thirdsShareEdges() {
        let a = gapped.frame(for: .leftThird, in: laptopVisible, current: .zero)!
        let b = gapped.frame(for: .centerThird, in: laptopVisible, current: .zero)!
        let c = gapped.frame(for: .rightThird, in: laptopVisible, current: .zero)!
        #expect(b.minX - a.maxX == 10)
        #expect(c.minX - b.maxX == 10)
        #expect(a.minX == 10 && c.maxX == 1430)
    }

    @Test func twoThirdsPlusThirdTile() {
        let big = gapped.frame(for: .leftTwoThirds, in: laptopVisible, current: .zero)!
        let small = gapped.frame(for: .rightThird, in: laptopVisible, current: .zero)!
        #expect(small.minX - big.maxX == 10)
    }

    @Test func quartersMeetInMiddle() {
        let tl = gapped.frame(for: .topLeft, in: laptopVisible, current: .zero)!
        let br = gapped.frame(for: .bottomRight, in: laptopVisible, current: .zero)!
        #expect(br.minX - tl.maxX == 10)
        #expect(br.minY - tl.maxY == 10)
    }

    @Test func maximizeUsesOuterGapOnly() {
        let m = gapped.frame(for: .maximize, in: laptopVisible, current: .zero)!
        #expect(m == CGRect(x: 10, y: 35, width: 1420, height: 855))
    }

    @Test func almostMaximizeIsCentered() {
        let e = SnapEngine(gaps: .none, almostMaximizeRatio: 0.5)
        let f = e.frame(for: .almostMaximize, in: laptopVisible, current: .zero)!
        #expect(f == CGRect(x: 360, y: 244, width: 720, height: 437))
    }

    @Test func centerKeepsSizeAndClampsOversize() {
        let f = noGaps.frame(for: .center, in: laptopVisible, current: CGRect(x: 0, y: 0, width: 400, height: 300))!
        #expect(f.size == CGSize(width: 400, height: 300))
        #expect(f.midX == laptopVisible.midX)
        let big = noGaps.frame(for: .center, in: laptopVisible, current: CGRect(x: 0, y: 0, width: 5000, height: 5000))!
        #expect(big == laptopVisible)
    }

    @Test func largerStaysOnScreen() {
        let f = gapped.frame(for: .larger, in: laptopVisible, current: CGRect(x: 15, y: 40, width: 500, height: 400))!
        #expect(gapped.usableArea(laptopVisible).contains(f))
        #expect(f.width > 500)
    }

    @Test func smallerRespectsMinimum() {
        let e = SnapEngine(gaps: .none, resizeStep: 100, minimumSize: CGSize(width: 300, height: 200))
        let f = e.frame(for: .smaller, in: laptopVisible, current: CGRect(x: 100, y: 100, width: 350, height: 250))!
        #expect(f.width == 300 && f.height == 200)
    }

    @Test func nonPlacementActionsReturnNil() {
        #expect(noGaps.frame(for: .restore, in: laptopVisible, current: .zero) == nil)
        #expect(noGaps.frame(for: .nextDisplay, in: laptopVisible, current: .zero) == nil)
    }

    @Test func translateKeepsRelativePlacement() {
        let small = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let big = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let leftHalf = CGRect(x: 0, y: 0, width: 500, height: 1000)
        #expect(SnapEngine.translate(leftHalf, from: small, to: big) == CGRect(x: 1000, y: 0, width: 1000, height: 1000))
    }

    @Test func reanchorKeepsRightEdgeFlush() {
        let area = laptopVisible
        let target = CGRect(x: 720, y: 25, width: 720, height: 875)
        // Terminal accepted a slightly narrower, shorter size.
        let actual = CGRect(x: 720, y: 25, width: 713, height: 868)
        let fixed = SnapEngine.reanchor(actual: actual, target: target, area: area)
        #expect(fixed.maxX == area.maxX)
        #expect(fixed.minY == 25) // top edge flush wins over bottom
    }

    @Test func reanchorCentersWhenNotTouchingEdges() {
        let area = laptopVisible
        let target = CGRect(x: 480, y: 25, width: 480, height: 875)
        let actual = CGRect(x: 480, y: 25, width: 600, height: 875) // min width bigger than a third
        let fixed = SnapEngine.reanchor(actual: actual, target: target, area: area)
        #expect(fixed.midX == target.midX)
    }
}

@Suite struct WindowMemoryTests {
    let a = CGRect(x: 100, y: 100, width: 600, height: 400)
    let half = CGRect(x: 0, y: 25, width: 720, height: 875)
    let twoThirds = CGRect(x: 0, y: 25, width: 960, height: 875)

    @Test func cyclesOnRepeat() {
        var m = WindowMemory()
        #expect(m.resolve(.leftHalf, window: 1, current: a) == .leftHalf)
        m.record(window: 1, action: .leftHalf, before: a, after: half)
        #expect(m.resolve(.leftHalf, window: 1, current: half) == .leftTwoThirds)
        m.record(window: 1, action: .leftTwoThirds, before: half, after: twoThirds)
        #expect(m.resolve(.leftHalf, window: 1, current: twoThirds) == .leftThird)
    }

    @Test func noCycleIfUserMovedWindow() {
        var m = WindowMemory()
        m.record(window: 1, action: .leftHalf, before: a, after: half)
        let moved = half.offsetBy(dx: 50, dy: 0)
        #expect(m.resolve(.leftHalf, window: 1, current: moved) == .leftHalf)
    }

    @Test func restoreReturnsOriginalAcrossSeveralSnaps() {
        var m = WindowMemory()
        m.record(window: 1, action: .leftHalf, before: a, after: half)
        m.record(window: 1, action: .leftTwoThirds, before: half, after: twoThirds)
        #expect(m.takeRestoreFrame(window: 1) == a)
        #expect(m.takeRestoreFrame(window: 1) == nil)
    }

    @Test func manualMoveBecomesNewRestorePoint() {
        var m = WindowMemory()
        m.record(window: 1, action: .leftHalf, before: a, after: half)
        let manual = CGRect(x: 300, y: 300, width: 500, height: 500)
        m.record(window: 1, action: .maximize, before: manual, after: half)
        #expect(m.takeRestoreFrame(window: 1) == manual)
    }

    @Test func windowsAreIndependent() {
        var m = WindowMemory()
        m.record(window: 1, action: .leftHalf, before: a, after: half)
        #expect(m.resolve(.leftHalf, window: 2, current: half) == .leftHalf)
    }
}

@Suite struct KeyComboTests {
    @Test func parsesModifiersAndKey() throws {
        let c = try KeyCombo.parse("ctrl+alt+left")
        #expect(c.keyCode == 0x7B)
        #expect(c.modifiers == [.control, .option])
    }

    @Test func aliasesAndCase() throws {
        let c = try KeyCombo.parse("Command + Option + Enter")
        #expect(c.keyCode == 0x24)
        #expect(c.modifiers == [.command, .option])
        #expect(c.description == "alt+cmd+return")
    }

    @Test func punctuationKeys() throws {
        #expect(try KeyCombo.parse("ctrl+=").keyCode == 0x18)
        #expect(try KeyCombo.parse("ctrl+minus").keyCode == 0x1B)
    }

    @Test func errors() {
        #expect(throws: KeyCombo.ParseError.unknownKey("blah")) { try KeyCombo.parse("ctrl+blah") }
        #expect(throws: KeyCombo.ParseError.missingKey("ctrl+alt")) { try KeyCombo.parse("ctrl+alt") }
        #expect(throws: KeyCombo.ParseError.multipleKeys("a+b")) { try KeyCombo.parse("a+b") }
        #expect(throws: KeyCombo.ParseError.empty) { try KeyCombo.parse("  ") }
    }

    @Test func allDefaultBindingsParse() throws {
        var seen = Set<KeyCombo>()
        for (shortcut, _) in DefaultBindings.all {
            let combo = try KeyCombo.parse(shortcut)
            #expect(seen.insert(combo).inserted, "duplicate binding \(shortcut)")
        }
    }
}
