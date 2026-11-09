import CoreGraphics
import Foundation
import TOMLKit

/// Something a shortcut can trigger.
public enum Command: Equatable, Hashable, Sendable, CustomStringConvertible {
    case snap(SnapAction)
    case reloadConfig

    public init?(name: String) {
        if name == "reload-config" {
            self = .reloadConfig
        } else if let action = SnapAction(rawValue: name) {
            self = .snap(action)
        } else {
            return nil
        }
    }

    public var description: String {
        switch self {
        case .snap(let a): return a.rawValue
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

/// A config problem pinned to a line when we can find one.
public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let message: String
    public let line: Int?

    public init(_ message: String, line: Int? = nil) {
        self.message = message
        self.line = line
    }

    public var description: String {
        line.map { "line \($0): \(message)" } ?? message
    }
}

extension Config {
    /// Top-level keys handled by later phases. Accepted silently so a config
    /// written ahead of time doesn't error.
    static let reservedKeys: Set<String> = ["drag", "layouts", "rules"]
    static let knownKeys: Set<String> = ["gaps", "almost_maximize", "resize_step", "keys"]

    /// Parses a config file. Any error rejects the whole file so a half-valid
    /// config never replaces a working one. Warnings are for things that are
    /// safe to ignore (unknown keys, probably typos).
    public static func parse(_ source: String) -> Result<(config: Config, warnings: [ConfigError]), ConfigError> {
        let root: TOMLTable
        do {
            root = try TOMLTable(string: source)
        } catch let error as TOMLParseError {
            return .failure(ConfigError(error.description, line: error.source.begin.line))
        } catch {
            return .failure(ConfigError("\(error)"))
        }

        var parser = Parser(source: source)
        let config = parser.parse(root)
        if let first = parser.errors.first {
            return .failure(first)
        }
        return .success((config, parser.warnings))
    }

    private struct Parser {
        let lines: [Substring]
        var errors: [ConfigError] = []
        var warnings: [ConfigError] = []

        init(source: String) {
            lines = source.split(separator: "\n", omittingEmptySubsequences: false)
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
            errors.append(ConfigError(message, line: line(of: key)))
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

            if let value = root["keys"] {
                guard let table = value.table else {
                    error("[keys] must be a table of \"shortcut\" = \"action\"", key: "keys")
                    return config
                }
                config.bindings = parseKeys(table)
            }

            return config
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
