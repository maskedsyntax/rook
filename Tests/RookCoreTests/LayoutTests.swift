import CoreGraphics
import Foundation
import Testing
@testable import RookCore

struct FakeDisplay: DisplayDescribing, Equatable {
    var uuid: String?
    var name: String
    var isMain: Bool
    var frame: CGRect
}

private let laptop = FakeDisplay(uuid: "AAAA-1111", name: "Built-in Retina Display", isMain: true,
                                 frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
private let leftMonitor = FakeDisplay(uuid: "BBBB-2222", name: "DELL U2723QE", isMain: false,
                                      frame: CGRect(x: -2560, y: -400, width: 2560, height: 1440))
private let rightMonitor = FakeDisplay(uuid: "CCCC-3333", name: "LG HDR 4K", isMain: false,
                                       frame: CGRect(x: 1512, y: -300, width: 3840, height: 2160))

@Suite struct DisplaySelectorTests {
    let all = [laptop, rightMonitor, leftMonitor]

    @Test func mainAndSecondary() {
        #expect(DisplaySelector.main.select(from: all) == laptop)
        // Secondary = first non-main, left to right.
        #expect(DisplaySelector.secondary.select(from: all) == leftMonitor)
    }

    @Test func indexIsLeftToRightAndFallsBackToMain() {
        #expect(DisplaySelector.index(1).select(from: all) == leftMonitor)
        #expect(DisplaySelector.index(2).select(from: all) == laptop)
        #expect(DisplaySelector.index(3).select(from: all) == rightMonitor)
        #expect(DisplaySelector.index(9).select(from: all) == laptop)
    }

    @Test func namedMatchesUUIDNameAndSubstring() {
        #expect(DisplaySelector.named("cccc-3333").select(from: all) == rightMonitor)
        #expect(DisplaySelector.named("DELL U2723QE").select(from: all) == leftMonitor)
        #expect(DisplaySelector.named("lg").select(from: all) == rightMonitor)
        #expect(DisplaySelector.named("unplugged").select(from: all) == laptop)
    }

    @Test func laptopOnlyEverythingGoesToMain() {
        for s in [DisplaySelector.secondary, .index(2), .named("DELL")] {
            #expect(s.select(from: [laptop]) == laptop)
        }
    }

    @Test func stringParsing() {
        #expect(DisplaySelector(string: "Main") == .main)
        #expect(DisplaySelector(string: "external") == .secondary)
        #expect(DisplaySelector(string: "LG") == .named("LG"))
    }
}

@Suite struct LayoutMatcherTests {
    func entry(_ title: String? = nil) -> LayoutEntry {
        LayoutEntry(app: "x", title: title, rect: .action(.maximize))
    }

    @Test func untitledEntriesTakeWindowsInOrder() {
        #expect(LayoutMatcher.assign(entries: [entry(), entry()], windowTitles: ["a", "b", "c"]) == [0, 1])
    }

    @Test func titledEntriesClaimFirstThenRestFill() {
        let result = LayoutMatcher.assign(
            entries: [entry(), entry("inbox")],
            windowTitles: ["Inbox – Mail", "Drafts"]
        )
        #expect(result == [1, 0])
    }

    @Test func moreEntriesThanWindows() {
        #expect(LayoutMatcher.assign(entries: [entry(), entry(), entry()], windowTitles: ["a"]) == [0, nil, nil])
    }

    @Test func titleWithNoMatchGetsNothing() {
        #expect(LayoutMatcher.assign(entries: [entry("nope")], windowTitles: ["a"]) == [nil])
    }
}

@Suite struct LayoutCaptureTests {
    let engine = SnapEngine(gaps: Gaps(outer: 8, inner: 8))
    let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func snappedFramesBecomeActionNames() {
        for action in [SnapAction.leftHalf, .rightThird, .topLeft, .maximize, .almostMaximize, .leftTwoThirds] {
            let frame = engine.frame(for: action, in: visible, current: .zero)!
            #expect(LayoutCapture.rect(for: frame, visible: visible, engine: engine) == .action(action))
        }
    }

    @Test func arbitraryFrameRoundTripsThroughUnit() {
        let frame = CGRect(x: 200, y: 140, width: 700, height: 500)
        guard case .unit(let u) = LayoutCapture.rect(for: frame, visible: visible, engine: engine) else {
            Issue.record("expected unit rect")
            return
        }
        let back = engine.frame(forRaw: u, in: visible)
        #expect(back.isApproximately(frame, tolerance: 1))
        // On a 6K-wide screen too: rounding must not shift windows visibly.
        let wide = CGRect(x: 0, y: 30, width: 3360, height: 1800)
        let big = CGRect(x: 595, y: 125, width: 2548, height: 1542)
        guard case .unit(let w) = LayoutCapture.rect(for: big, visible: wide, engine: engine) else { return }
        #expect(engine.frame(forRaw: w, in: wide).isApproximately(big, tolerance: 1))
    }

    @Test func offscreenFrameIsClamped() {
        let frame = CGRect(x: -300, y: 25, width: 3000, height: 875)
        guard case .unit(let u) = LayoutCapture.rect(for: frame, visible: visible, engine: engine) else {
            Issue.record("expected unit rect")
            return
        }
        #expect(u.x >= 0 && u.x + u.w <= 1.0001)
    }

    @Test func serializeParsesBack() throws {
        let entries = [
            LayoutEntry(app: "com.microsoft.VSCode", display: .main, rect: .action(.leftTwoThirds)),
            LayoutEntry(app: "com.apple.Safari", title: "Docs \"API\" \\ notes", display: .named("LG HDR 4K"),
                        rect: .unit(UnitRect(x: 0.1, y: 0, w: 0.5, h: 1)), launch: false),
            LayoutEntry(app: "com.mitchellh.ghostty", display: .index(2), rect: .action(.rightThird)),
        ]
        let text = LayoutCapture.serialize(entries, comment: "test")
        let layout = try Config.parseLayoutFile(LayoutFile(name: "coding", path: "layouts/coding.toml", source: text)).get()
        #expect(layout.entries == entries)
        #expect(layout.name == "coding")
    }

    @Test func numberFormatting() {
        #expect(LayoutCapture.num(0.5) == "0.5")
        #expect(LayoutCapture.num(1) == "1.0")
        #expect(LayoutCapture.num(0.333333) == "0.3333")
        #expect(LayoutCapture.num(0) == "0.0")
    }

    @Test func sanitizedNames() {
        #expect(LayoutCapture.sanitizedName("My Coding Setup!") == "my-coding-setup")
        #expect(LayoutCapture.sanitizedName("work_2") == "work_2")
        #expect(LayoutCapture.sanitizedName("   ") == nil)
        #expect(LayoutCapture.sanitizedName("../etc") == "etc")
    }
}

@Suite struct LayoutConfigTests {
    let source = """
        [keys]
        "ctrl+alt+1" = "layout:coding"
        "ctrl+alt+2" = "layout:saved"

        [[layouts.coding]]
        app = "com.microsoft.VSCode"
        rect = "left-two-thirds"

        [[layouts.coding]]
        app = "com.mitchellh.ghostty"
        rect = { x = 0.667, y = 0, w = 0.333, h = 1 }
        display = 2
        launch = false

        [[rules]]
        app = "com.apple.Terminal"
        title = "ssh"
        rect = "right-half"
        display = "secondary"
        """

    let saved = LayoutFile(name: "saved", path: "layouts/saved.toml", source: """
        [[windows]]
        app = "com.apple.Safari"
        rect = "maximize"
        """)

    @Test func parsesLayoutsRulesAndBindings() throws {
        let result = try Config.parse(source, layoutFiles: [saved]).get()
        let c = result.config
        #expect(result.warnings.isEmpty)
        #expect(c.layouts.map(\.name) == ["coding", "saved"])
        let coding = c.layout(named: "coding")!
        #expect(coding.entries[0] == LayoutEntry(app: "com.microsoft.VSCode", rect: .action(.leftTwoThirds)))
        #expect(coding.entries[1].rect == .unit(UnitRect(x: 0.667, y: 0, w: 0.333, h: 1)))
        #expect(coding.entries[1].display == .index(2))
        #expect(coding.entries[1].launch == false)
        #expect(c.layout(named: "saved")?.file == "layouts/saved.toml")
        #expect(c.rules == [Rule(app: "com.apple.Terminal", title: "ssh", display: .secondary, rect: .action(.rightHalf))])
        #expect(c.bindings.map(\.command) == [.layout("coding"), .layout("saved")])
    }

    @Test func unknownLayoutInBindingIsAnError() {
        guard case .failure(let e) = Config.parse(source, layoutFiles: []) else {
            Issue.record("expected failure: layout 'saved' isn't available")
            return
        }
        #expect(e.message.contains("unknown layout 'saved'"))
        #expect(e.line == 3)
    }

    @Test func brokenLayoutFileIsOnlyAWarning() throws {
        let broken = LayoutFile(name: "bad", path: "layouts/bad.toml", source: "[[windows]]\napp = \"x\"\nrect = \"sideways\"")
        let r = try Config.parse("", layoutFiles: [broken]).get()
        #expect(r.config.layouts.isEmpty)
        #expect(r.warnings.count == 1)
        #expect(r.warnings[0].description.hasPrefix("layouts/bad.toml"))
    }

    @Test func configLayoutWinsNameClash() throws {
        let clash = LayoutFile(name: "coding", path: "layouts/coding.toml", source: "[[windows]]\napp = \"x\"\nrect = \"maximize\"")
        let r = try Config.parse(source, layoutFiles: [clash, saved]).get()
        #expect(r.config.layout(named: "coding")?.file == nil)
        #expect(r.warnings.count == 1)
    }

    @Test func invalidEntries() {
        let bad = [
            "[[layouts.a]]\nrect = \"maximize\"",                              // no app
            "[[layouts.a]]\napp = \"x\"",                                     // no rect
            "[[layouts.a]]\napp = \"x\"\nrect = \"restore\"",                 // not a placement
            "[[layouts.a]]\napp = \"x\"\nrect = { x = 0.8, y = 0, w = 0.5, h = 1 }", // overflows
            "[[layouts.a]]\napp = \"x\"\nrect = \"maximize\"\ndisplay = 0",    // display index from 1
            "[layouts.a]\napp = \"x\"",                                       // table, not array
            "[[layouts.\"has space\"]]\napp = \"x\"\nrect = \"maximize\"",
            "[[rules]]\nrect = \"maximize\"",
        ]
        for source in bad {
            if case .success = Config.parse(source) { Issue.record("expected failure for:\n\(source)") }
        }
    }

    @Test func layoutCommandParsing() {
        #expect(Command(name: "layout:coding") == .layout("coding"))
        #expect(Command(name: "layout:") == nil)
    }

    @Test func ruleMatching() {
        let rule = Rule(app: "com.apple.Terminal", title: "SSH", rect: .action(.maximize))
        #expect(rule.matches(app: "com.apple.Terminal", title: "user@host — ssh"))
        #expect(!rule.matches(app: "com.apple.Terminal", title: "zsh"))
        #expect(!rule.matches(app: "com.apple.Safari", title: "ssh"))
        #expect(Rule(app: "a", rect: .action(.maximize)).matches(app: "a", title: nil))
    }
}

@Suite struct URLCommandTests {
    func parse(_ s: String) -> URLCommand? { URLCommand(url: URL(string: s)!) }

    @Test func verbs() {
        #expect(parse("rook://layout/coding") == .run(.layout("coding")))
        #expect(parse("rook://snap/left-half") == .run(.snap(.leftHalf)))
        #expect(parse("rook://reload") == .run(.reloadConfig))
        #expect(parse("rook://save-layout/My%20Setup") == .saveLayout("my-setup"))
        #expect(parse("ROOK://Layout/coding") == .run(.layout("coding")))
    }

    @Test func rejects() {
        #expect(parse("rook://layout") == nil)
        #expect(parse("rook://snap/sideways") == nil)
        #expect(parse("rook://save-layout/%20") == nil)
        #expect(parse("rook://format-disk") == nil)
        #expect(parse("https://layout/coding") == nil)
    }
}
