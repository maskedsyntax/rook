import CoreGraphics
import Foundation
import TOMLKit

/// Something a shortcut can trigger.
public enum Command: Equatable, Hashable, Sendable, CustomStringConvertible {
    case snap(SnapAction)
    case layout(String)
    case reloadConfig

    public init?(name: String) {
        if name == "reload-config" {
            self = .reloadConfig
        } else if name.hasPrefix("layout:") {
            let layout = String(name.dropFirst("layout:".count)).trimmingCharacters(in: .whitespaces)
            guard !layout.isEmpty else { return nil }
            self = .layout(layout)
        } else if let action = SnapAction(rawValue: name) {
            self = .snap(action)
        } else {
            return nil
        }
    }

    public var description: String {
        switch self {
        case .snap(let a): return a.rawValue
        case .layout(let name): return "layout:\(name)"
        case .reloadConfig: return "reload-config"
        }
    }
}

public struct Binding: Equatable, Sendable {
    /// Exactly as written in the config, for error messages.
    public let shortcut: String
    public let combo: KeyCombo
    public let command: Command

    public init(shortcut: String, combo: KeyCombo, command: Command) {
        self.shortcut = shortcut
        self.combo = combo
        self.command = command
    }
}

public struct Config: Equatable, Sendable {
    public var gaps: Gaps
    public var almostMaximize: CGFloat
    public var resizeStep: CGFloat
    public var bindings: [Binding]
    public var drag: DragConfig = DragConfig()
    /// From config.toml first, then saved layout files (config wins on a name clash).
    public var layouts: [Layout] = []
    public var rules: [Rule] = []

    public func layout(named name: String) -> Layout? {
        layouts.first { $0.name == name }
    }

    public static let `default`: Config = {
        let bindings = DefaultBindings.all.map { shortcut, action in
            // DefaultBindings is covered by a test, so this can't fail at runtime.
            Binding(shortcut: shortcut, combo: try! KeyCombo.parse(shortcut), command: .snap(action))
        }
        return Config(gaps: Gaps(outer: 8, inner: 8), almostMaximize: 0.9, resizeStep: 40, bindings: bindings)
    }()

    public var engine: SnapEngine {
        SnapEngine(gaps: gaps, almostMaximizeRatio: almostMaximize, resizeStep: resizeStep)
    }
}

public struct DragConfig: Equatable, Sendable {
    /// Drag a window to a screen edge or corner to snap it. Off by default:
    /// rook only watches the mouse when you opt in.
    public var enabled: Bool = false
    public var bottomEdge: BottomEdge = .thirds
    /// Dragging a snapped window away gives it back its pre-snap size.
    public var restoreSizeOnUnsnap: Bool = true
    /// Hold these and drag anywhere in a window to move it (right-drag to
    /// resize). nil (the default) disables modifier-drag.
    public var modifier: KeyCombo.Modifiers? = nil

    public init() {}

    public var zones: DragZones { DragZones(bottom: bottomEdge) }
}

/// A config problem pinned to a line when we can find one.
public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public let line: Int?
    /// Set for problems in a saved layout file rather than config.toml.
    public let file: String?

    public init(_ message: String, line: Int? = nil, file: String? = nil) {
        self.message = message
        self.line = line
        self.file = file
    }

    public var description: String {
        let location = [file, line.map { "line \($0)" }].compactMap { $0 }.joined(separator: " ")
        return location.isEmpty ? message : "\(location): \(message)"
    }
}

/// A saved layout file (`layouts/<name>.toml`) handed to the parser.
public struct LayoutFile: Sendable {
    public let name: String
    public let path: String
    public let source: String

    public init(name: String, path: String, source: String) {
        self.name = name
        self.path = path
        self.source = source
    }
}

extension Config {
    static let reservedKeys: Set<String> = []
    static let knownKeys: Set<String> = ["gaps", "almost_maximize", "resize_step", "keys", "drag", "layouts", "rules"]

    /// Parses a config file. Any error rejects the whole file so a half-valid
    /// config never replaces a working one. Warnings are for things that are
    /// safe to ignore (unknown keys, probably typos).
    ///
    /// Saved layout files are more forgiving: a broken one is skipped with a
    /// warning, because it shouldn't cost you your shortcuts.
    public static func parse(_ source: String, layoutFiles: [LayoutFile] = []) -> Result<(config: Config, warnings: [ConfigError]), ConfigError> {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: source)
        } catch let error as TOMLParseError {
            return .failure(ConfigError(error.description, line: error.source.begin.line))
        } catch {
            return .failure(ConfigError("\(error)"))
        }

        var parser = Parser(source: source)
        var config = parser.parse(root)
        if let first = parser.errors.first {
            return .failure(first)
        }
        var warnings = parser.warnings

        for file in layoutFiles.sorted(by: { $0.name < $1.name }) {
            if config.layout(named: file.name) != nil {
                warnings.append(ConfigError("layout '\(file.name)' is also defined in config.toml; using that one", file: file.path))
                continue
            }
            switch parseLayoutFile(file) {
            case .success(let layout): config.layouts.append(layout)
            case .failure(let error): warnings.append(error)
            }
        }

        // Shortcuts may name layouts from either place, so check them last.
        for binding in config.bindings {
            if case .layout(let name) = binding.command, config.layout(named: name) == nil {
                let known = config.layouts.map(\.name).joined(separator: ", ")
                return .failure(ConfigError(
                    "'\(binding.shortcut)' uses unknown layout '\(name)'" + (known.isEmpty ? "" : " (layouts: \(known))"),
                    line: parser.line(of: binding.shortcut)
                ))
            }
        }
        return .success((config, warnings))
    }

    /// A file holding `[[windows]]` entries.
    public static func parseLayoutFile(_ file: LayoutFile) -> Result<Layout, ConfigError> {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: file.source)
        } catch let error as TOMLParseError {
            return .failure(ConfigError(error.description, line: error.source.begin.line, file: file.path))
        } catch {
            return .failure(ConfigError("\(error)", file: file.path))
        }
        var parser = Parser(source: file.source, file: file.path)
        guard let array = root["windows"]?.array else {
            return .failure(ConfigError("expected [[windows]] entries", file: file.path))
        }
        let entries = parser.parseEntries(array, context: "windows")
        if let first = parser.errors.first { return .failure(first) }
        return .success(Layout(name: file.name, entries: entries, file: file.path))
    }

    private struct Parser {
        let lines: [Substring]
        let file: String?
        var errors: [ConfigError] = []
        var warnings: [ConfigError] = []

        init(source: String, file: String? = nil) {
            lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            self.file = file
        }

        /// TOMLKit doesn't expose node positions, so locate a key textually.
        func line(of key: String) -> Int? {
            let quoted = "\"\(key)\""
            let pattern = try? NSRegularExpression(pattern: "^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*=")
            for (i, line) in lines.enumerated() {
                let s = String(line)
                if s.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
                if s.contains(quoted) { return i + 1 }
                if let pattern, pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { return i + 1 }
                if s.contains("[\(key)]") { return i + 1 }
            }
            return nil
        }

        mutating func error(_ message: String, key: String) {
            errors.append(ConfigError(message, line: line(of: key), file: file))
        }

        func number(_ value: TOMLValueConvertible?) -> Double? {
            value?.double ?? value?.int.map(Double.init)
        }

        mutating func parse(_ root: TOMLTable) -> Config {
            var config = Config.default

            for key in root.keys where !knownKeys.contains(key) && !reservedKeys.contains(key) {
                warnings.append(ConfigError("unknown setting '\(key)' (ignored)", line: line(of: key)))
            }

            if let value = root["gaps"] {
                if let n = number(value) {
                    guard n >= 0 else { error("gaps must be ≥ 0", key: "gaps"); return config }
                    config.gaps = Gaps(outer: n, inner: n)
                } else if let table = value.table {
                    for key in table.keys where key != "outer" && key != "inner" {
                        warnings.append(ConfigError("unknown gaps setting '\(key)' (ignored)", line: line(of: "gaps")))
                    }
                    let fields: [(String, WritableKeyPath<Gaps, CGFloat>)] = [("outer", \.outer), ("inner", \.inner)]
                    for (key, path) in fields {
                        guard let raw = table[key] else { continue }
                        guard let n = number(raw), n >= 0 else {
                            error("gaps.\(key) must be a number ≥ 0", key: "gaps")
                            continue
                        }
                        config.gaps[keyPath: path] = n
                    }
                } else {
                    error("gaps must be a number or { outer = …, inner = … }", key: "gaps")
                }
            }

            if let value = root["almost_maximize"] {
                if let n = number(value), n > 0, n <= 1 {
                    config.almostMaximize = n
                } else {
                    error("almost_maximize must be a number between 0 and 1 (e.g. 0.9)", key: "almost_maximize")
                }
            }

            if let value = root["resize_step"] {
                if let n = number(value), n > 0 {
                    config.resizeStep = n
                } else {
                    error("resize_step must be a positive number of points", key: "resize_step")
                }
            }

            if let value = root["drag"] {
                if let table = value.table {
                    config.drag = parseDrag(table)
                } else {
                    error("[drag] must be a table", key: "drag")
                }
            }

            if let value = root["layouts"] {
                if let table = value.table {
                    for name in table.keys.sorted(by: { (line(of: $0) ?? 0) < (line(of: $1) ?? 0) }) {
                        guard LayoutCapture.sanitizedName(name) == name.lowercased() else {
                            error("layout name '\(name)' may only use letters, digits, - and _", key: name)
                            continue
                        }
                        guard let array = table[name]?.array else {
                            error("layout '\(name)' must be a list: use [[layouts.\(name)]] for each window", key: name)
                            continue
                        }
                        config.layouts.append(Layout(name: name, entries: parseEntries(array, context: "layouts.\(name)")))
                    }
                } else {
                    error("layouts must be written as [[layouts.<name>]] sections", key: "layouts")
                }
            }

            if let value = root["rules"] {
                if let array = value.array {
                    config.rules = parseRules(array)
                } else {
                    error("rules must be written as [[rules]] sections", key: "rules")
                }
            }

            if let value = root["keys"] {
                guard let table = value.table else {
                    error("[keys] must be a table of \"shortcut\" = \"action\"", key: "keys")
                    return config
                }
                config.bindings = parseKeys(table)
            }

            return config
        }

        // MARK: Layouts and rules

        mutating func parseEntries(_ array: TOMLArray, context: String) -> [LayoutEntry] {
            var entries: [LayoutEntry] = []
            for value in array {
                guard let table = value.table else {
                    error("each [[\(context)]] entry must be a table", key: context)
                    continue
                }
                let known: Set<String> = ["app", "title", "display", "rect", "launch"]
                warnUnknown(table, known: known, context: context)

                guard let app = table["app"]?.string, !app.isEmpty else {
                    error("[[\(context)]] entry needs app = \"<bundle id>\" (e.g. \"com.apple.Safari\")", key: context)
                    continue
                }
                guard let rect = parseRect(table["rect"], context: context, app: app) else { continue }
                var entry = LayoutEntry(app: app, rect: rect)
                entry.title = table["title"]?.string
                if let display = parseDisplay(table["display"], context: context, app: app) { entry.display = display }
                if let launch = table["launch"] {
                    if let b = launch.bool { entry.launch = b } else { error("launch must be true or false", key: app) }
                }
                entries.append(entry)
            }
            return entries
        }

        mutating func parseRules(_ array: TOMLArray) -> [Rule] {
            var rules: [Rule] = []
            for value in array {
                guard let table = value.table else {
                    error("each [[rules]] entry must be a table", key: "rules")
                    continue
                }
                warnUnknown(table, known: ["app", "title", "display", "rect"], context: "rules")
                guard let app = table["app"]?.string, !app.isEmpty else {
                    error("[[rules]] entry needs app = \"<bundle id>\"", key: "rules")
                    continue
                }
                guard let rect = parseRect(table["rect"], context: "rules", app: app) else { continue }
                var rule = Rule(app: app, rect: rect)
                rule.title = table["title"]?.string
                rule.display = parseDisplay(table["display"], context: "rules", app: app)
                rules.append(rule)
            }
            return rules
        }

        mutating func warnUnknown(_ table: TOMLTable, known: Set<String>, context: String) {
            for key in table.keys where !known.contains(key) {
                warnings.append(ConfigError("unknown setting '\(key)' in [[\(context)]] (ignored)", line: line(of: key), file: file))
            }
        }

        mutating func parseRect(_ value: TOMLValueConvertible?, context: String, app: String) -> LayoutRect? {
            guard let value else {
                error("[[\(context)]] entry for \(app) needs rect = \"<action>\" or { x, y, w, h }", key: app)
                return nil
            }
            if let name = value.string {
                guard let action = SnapAction(rawValue: name), LayoutRect.isPlacement(action) else {
                    let suggestion = Self.closestAction(to: name).map { " (did you mean '\($0)'?)" } ?? ""
                    error("rect '\(name)' isn't a placement\(suggestion)", key: name)
                    return nil
                }
                return .action(action)
            }
            if let t = value.table {
                var v: [String: CGFloat] = [:]
                for k in ["x", "y", "w", "h"] {
                    guard let n = number(t[k]) else {
                        error("rect for \(app) needs numbers x, y, w, h (fractions of the screen)", key: app)
                        return nil
                    }
                    v[k] = n
                }
                let u = UnitRect(x: v["x"]!, y: v["y"]!, w: v["w"]!, h: v["h"]!)
                let eps: CGFloat = 0.0005
                guard u.x >= 0, u.y >= 0, u.w > 0, u.h > 0, u.x + u.w <= 1 + eps, u.y + u.h <= 1 + eps else {
                    error("rect for \(app) must stay within 0…1 (x + w ≤ 1, y + h ≤ 1)", key: app)
                    return nil
                }
                return .unit(u)
            }
            error("rect for \(app) must be an action name or { x, y, w, h }", key: app)
            return nil
        }

        mutating func parseDisplay(_ value: TOMLValueConvertible?, context: String, app: String) -> DisplaySelector? {
            guard let value else { return nil }
            if let s = value.string { return DisplaySelector(string: s) }
            if let i = value.int {
                guard i >= 1 else {
                    error("display numbers start at 1 (left to right)", key: app)
                    return nil
                }
                return .index(i)
            }
            error("display must be \"main\", \"secondary\", a number, or a display name", key: app)
            return nil
        }

        mutating func parseDrag(_ table: TOMLTable) -> DragConfig {
            var drag = DragConfig()
            let known: Set<String> = ["enabled", "bottom_edge", "restore_size", "modifier"]
            for key in table.keys where !known.contains(key) {
                warnings.append(ConfigError("unknown drag setting '\(key)' (ignored)", line: line(of: key)))
            }
            if let v = table["enabled"] {
                if let b = v.bool { drag.enabled = b } else { error("drag.enabled must be true or false", key: "enabled") }
            }
            if let v = table["restore_size"] {
                if let b = v.bool { drag.restoreSizeOnUnsnap = b } else { error("drag.restore_size must be true or false", key: "restore_size") }
            }
            if let v = table["bottom_edge"] {
                if let s = v.string, let edge = BottomEdge(rawValue: s) {
                    drag.bottomEdge = edge
                } else {
                    error("drag.bottom_edge must be \"thirds\", \"half\" or \"none\"", key: "bottom_edge")
                }
            }
            if let v = table["modifier"] {
                if let s = v.string, s == "none" {
                    drag.modifier = nil
                } else if let s = v.string, let mods = KeyCombo.parseModifiers(s) {
                    drag.modifier = mods
                } else {
                    error("drag.modifier must be modifiers like \"ctrl+cmd\", or \"none\"", key: "modifier")
                }
            }
            return drag
        }

        /// `[keys]` replaces the defaults entirely, so the file is the whole truth.
        mutating func parseKeys(_ table: TOMLTable) -> [Binding] {
            var bindings: [Binding] = []
            var seen: [KeyCombo: String] = [:]

            for shortcut in table.keys.sorted(by: { (line(of: $0) ?? 0) < (line(of: $1) ?? 0) }) {
                guard let name = table[shortcut]?.string else {
                    error("value for '\(shortcut)' must be an action name in quotes", key: shortcut)
                    continue
                }
                if name == "none" || name.isEmpty { continue }

                let combo: KeyCombo
                do {
                    combo = try KeyCombo.parse(shortcut)
                } catch {
                    self.error(error.description, key: shortcut)
                    continue
                }

                guard let command = Command(name: name) else {
                    let suggestion = Self.closestAction(to: name).map { " (did you mean '\($0)'?)" } ?? ""
                    error("unknown action '\(name)'\(suggestion)", key: shortcut)
                    continue
                }

                if let previous = seen[combo] {
                    error("'\(shortcut)' is the same shortcut as '\(previous)'", key: shortcut)
                    continue
                }
                seen[combo] = shortcut
                bindings.append(Binding(shortcut: shortcut, combo: combo, command: command))
            }
            return bindings
        }

        static func closestAction(to name: String) -> String? {
            let candidates = SnapAction.allCases.map(\.rawValue) + ["reload-config"]
            let scored = candidates.map { ($0, editDistance(name, $0)) }
            guard let best = scored.min(by: { $0.1 < $1.1 }), best.1 <= 3 else { return nil }
            return best.0
        }

        static func editDistance(_ a: String, _ b: String) -> Int {
            let a = Array(a), b = Array(b)
            if a.isEmpty { return b.count }
            var prev = Array(0...b.count)
            for i in 1...a.count {
                var cur = [i] + Array(repeating: 0, count: b.count)
                for j in 1...max(b.count, 1) where !b.isEmpty {
                    cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                }
                prev = cur
            }
            return prev[b.count]
        }
    }
}
