import CoreGraphics
import Testing
@testable import RookCore

private func parsed(_ source: String) throws -> (config: Config, warnings: [ConfigError]) {
    try Config.parse(source).get()
}

private func failure(_ source: String) -> ConfigError? {
    if case .failure(let e) = Config.parse(source) { return e }
    return nil
}

@Suite struct ConfigTests {
    @Test func templateParsesToDefaults() throws {
        let result = try parsed(Config.template)
        #expect(result.config == Config.default)
        #expect(result.warnings.isEmpty)
    }

    @Test func emptyFileIsDefaults() throws {
        #expect(try parsed("").config == Config.default)
    }

    @Test func scalarGapsSetsBoth() throws {
        let c = try parsed("gaps = 12").config
        #expect(c.gaps == Gaps(outer: 12, inner: 12))
    }

    @Test func partialGapsTableKeepsOtherDefault() throws {
        let c = try parsed("gaps = { inner = 0 }").config
        #expect(c.gaps == Gaps(outer: 8, inner: 0))
    }

    @Test func floatAndIntNumbers() throws {
        let c = try parsed("gaps = 6.5\nresize_step = 25\nalmost_maximize = 1").config
        #expect(c.gaps.outer == 6.5)
        #expect(c.resizeStep == 25)
        #expect(c.almostMaximize == 1)
    }

    @Test func keysReplaceDefaults() throws {
        let c = try parsed("""
            [keys]
            "cmd+alt+h" = "left-half"
            "cmd+alt+l" = "right-half"
            "cmd+alt+r" = "reload-config"
            """).config
        #expect(c.bindings.map(\.command) == [.snap(.leftHalf), .snap(.rightHalf), .reloadConfig])
        #expect(c.bindings.map(\.shortcut) == ["cmd+alt+h", "cmd+alt+l", "cmd+alt+r"])
    }

    @Test func noneDisablesBinding() throws {
        let c = try parsed("""
            [keys]
            "ctrl+alt+left" = "none"
            "ctrl+alt+right" = "right-half"
            """).config
        #expect(c.bindings.count == 1)
    }

    @Test func syntaxErrorHasLine() {
        let e = failure("gaps = 8\nalmost_maximize = = 0.9\n")
        #expect(e?.line == 2)
    }

    @Test func unknownActionSuggestsFix() {
        let e = failure("""
            gaps = 8

            [keys]
            "ctrl+alt+left" = "left-hlaf"
            """)
        #expect(e?.line == 4)
        #expect(e?.message.contains("did you mean 'left-half'") == true)
    }

    @Test func badShortcutReported() {
        let e = failure("[keys]\n\"ctrl+alt+banana\" = \"maximize\"")
        #expect(e?.line == 2)
        #expect(e?.message.contains("banana") == true)
    }

    @Test func duplicateComboInDifferentSpelling() {
        let e = failure("""
            [keys]
            "ctrl+alt+left" = "left-half"
            "alt+ctrl+left" = "right-half"
            """)
        #expect(e?.line == 3)
    }

    @Test func outOfRangeValues() {
        #expect(failure("almost_maximize = 1.5") != nil)
        #expect(failure("gaps = -1") != nil)
        #expect(failure("resize_step = 0") != nil)
        #expect(failure("gaps = \"big\"") != nil)
    }

    @Test func unknownKeysWarnButApply() throws {
        let r = try parsed("gap = 4\ngaps = 2")
        #expect(r.config.gaps.outer == 2)
        #expect(r.warnings.count == 1)
        #expect(r.warnings.first?.line == 1)
    }

    @Test func otherSectionsDontWarn() throws {
        let r = try parsed("""
            [drag]
            enabled = true

            [[layouts.coding]]
            app = "com.microsoft.VSCode"
            rect = "maximize"
            """)
        #expect(r.warnings.isEmpty)
    }

    @Test func commentsDontConfuseLineLookup() {
        let e = failure("""
            # "ctrl+alt+x" = "maximize" is an example
            [keys]
            "ctrl+alt+x" = "nope"
            """)
        #expect(e?.line == 3)
    }

    @Test func engineReflectsConfig() throws {
        let c = try parsed("gaps = { outer = 0, inner = 20 }\nalmost_maximize = 0.5").config
        #expect(c.engine.gaps.inner == 20)
        #expect(c.engine.almostMaximizeRatio == 0.5)
    }
}
