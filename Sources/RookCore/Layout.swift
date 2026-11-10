import CoreGraphics
import Foundation

/// Which display a layout entry or rule targets.
public enum DisplaySelector: Equatable, Sendable, CustomStringConvertible {
    /// The menu bar display.
    case main
    /// The first non-main display, left to right.
    case secondary
    /// 1-based, displays ordered left to right.
    case index(Int)
    /// Matches a display UUID, then exact name, then a name substring.
    case named(String)

    public init(string: String) {
        switch string.lowercased() {
        case "main", "primary": self = .main
        case "secondary", "external": self = .secondary
        default: self = .named(string)
        }
    }

    public var description: String {
        switch self {
        case .main: return "main"
        case .secondary: return "secondary"
        case .index(let i): return "\(i)"
        case .named(let s): return s
        }
    }
}

/// What a display looks like to the selector. `Display` (RookAX) conforms.
public protocol DisplayDescribing {
    var uuid: String? { get }
    var name: String { get }
    var isMain: Bool { get }
    var frame: CGRect { get }
}

extension DisplaySelector {
    /// Picks a display, falling back to the main one so a layout made for two
    /// monitors still does something sensible on a laptop alone.
    public func select<D: DisplayDescribing>(from displays: [D]) -> D? {
        let ordered = displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        let main = displays.first(where: \.isMain) ?? ordered.first
        switch self {
        case .main:
            return main
        case .secondary:
            return ordered.first { !$0.isMain } ?? main
        case .index(let i):
            return ordered.indices.contains(i - 1) ? ordered[i - 1] : main
        case .named(let s):
            let lower = s.lowercased()
            return displays.first { $0.uuid?.lowercased() == lower }
                ?? displays.first { $0.name.lowercased() == lower }
                ?? displays.first { $0.name.lowercased().contains(lower) }
                ?? main
        }
    }
}

/// Where a window goes on its display.
public enum LayoutRect: Equatable, Sendable, CustomStringConvertible {
    case action(SnapAction)
    /// Fractions of the usable area (inside outer gaps), no inner gaps.
    case unit(UnitRect)

    /// Actions that make sense as a fixed placement.
    public static func isPlacement(_ action: SnapAction) -> Bool {
        action.unitRect != nil || action == .almostMaximize || action == .center
    }

    public var description: String {
        switch self {
        case .action(let a): return a.rawValue
        case .unit(let u): return "{ x = \(u.x), y = \(u.y), w = \(u.w), h = \(u.h) }"
        }
    }
}

public struct LayoutEntry: Equatable, Sendable {
    /// Bundle identifier.
    public var app: String
    /// Optional case-insensitive substring of the window title.
    public var title: String?
    public var display: DisplaySelector
    public var rect: LayoutRect
    /// Launch the app if it isn't running.
    public var launch: Bool

    public init(app: String, title: String? = nil, display: DisplaySelector = .main, rect: LayoutRect, launch: Bool = true) {
        self.app = app
        self.title = title
        self.display = display
        self.rect = rect
        self.launch = launch
    }
}

public struct Layout: Equatable, Sendable {
    public var name: String
    public var entries: [LayoutEntry]
    /// The file it came from, if it was saved separately from config.toml.
    public var file: String?

    public init(name: String, entries: [LayoutEntry], file: String? = nil) {
        self.name = name
        self.entries = entries
        self.file = file
    }
}

/// Places new windows of an app automatically.
public struct Rule: Equatable, Sendable {
    public var app: String
    public var title: String?
    /// nil = whichever display the window opened on.
    public var display: DisplaySelector?
    public var rect: LayoutRect

    public init(app: String, title: String? = nil, display: DisplaySelector? = nil, rect: LayoutRect) {
        self.app = app
        self.title = title
        self.display = display
        self.rect = rect
    }

    public func matches(app bundleID: String, title windowTitle: String?) -> Bool {
        guard bundleID == app else { return false }
        guard let title else { return true }
        return windowTitle?.localizedCaseInsensitiveContains(title) ?? false
    }
}

// MARK: - Matching layout entries to windows

public enum LayoutMatcher {
    /// Assigns an app's windows to its layout entries.
    ///
    /// Entries with a `title` claim the first window whose title contains it.
    /// The rest take the remaining windows in order (front to back). Entries
    /// with no window left get nothing: rook never opens new windows.
    /// - Returns: for each entry, the index of its window, or nil.
    public static func assign(entries: [LayoutEntry], windowTitles: [String?]) -> [Int?] {
        var taken = Set<Int>()
        var result = [Int?](repeating: nil, count: entries.count)

        for (i, entry) in entries.enumerated() {
            guard let title = entry.title else { continue }
            if let w = windowTitles.indices.first(where: {
                !taken.contains($0) && (windowTitles[$0]?.localizedCaseInsensitiveContains(title) ?? false)
            }) {
                taken.insert(w)
                result[i] = w
            }
        }
        for (i, entry) in entries.enumerated() where entry.title == nil {
            if let w = windowTitles.indices.first(where: { !taken.contains($0) }) {
                taken.insert(w)
                result[i] = w
            }
        }
        return result
    }
}

// MARK: - Capturing the current arrangement

public enum LayoutCapture {
    /// Describes `frame` on a display: a snap action name if it matches one
    /// (so saved layouts read naturally and pick up gap changes), otherwise
    /// fractions of the usable area rounded to 3 decimals.
    public static func rect(for frame: CGRect, visible: CGRect, engine: SnapEngine) -> LayoutRect {
        let candidates = SnapAction.allCases.filter { $0.unitRect != nil || $0 == .almostMaximize }
        for action in candidates {
            if let f = engine.frame(for: action, in: visible, current: frame), f.isApproximately(frame, tolerance: 4) {
                return .action(action)
            }
        }
        let a = engine.usableArea(visible)
        func r(_ v: CGFloat) -> CGFloat { (min(max(v, 0), 1) * 10000).rounded() / 10000 }
        let x = r((frame.minX - a.minX) / a.width)
        let y = r((frame.minY - a.minY) / a.height)
        let w = min(r(frame.width / a.width), 1 - x)
        let h = min(r(frame.height / a.height), 1 - y)
        return .unit(UnitRect(x: x, y: y, w: w, h: h))
    }

    /// TOML for a saved layout file. Parsed back by `Config.parseLayoutFile`.
    public static func serialize(_ entries: [LayoutEntry], comment: String) -> String {
        var out = "# \(comment)\n# Edit freely. Each [[windows]] places one window.\n"
        for e in entries {
            out += "\n[[windows]]\n"
            out += "app = \(quote(e.app))\n"
            if let title = e.title { out += "title = \(quote(title))\n" }
            switch e.display {
            case .index(let i): out += "display = \(i)\n"
            default: out += "display = \(quote(e.display.description))\n"
            }
            switch e.rect {
            case .action(let a): out += "rect = \(quote(a.rawValue))\n"
            case .unit(let u): out += "rect = { x = \(num(u.x)), y = \(num(u.y)), w = \(num(u.w)), h = \(num(u.h)) }\n"
            }
            if !e.launch { out += "launch = false\n" }
        }
        return out
    }

    static func quote(_ s: String) -> String {
        var escaped = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\t": escaped += "\\t"
            case "\r": escaped += "\\r"
            default:
                if ch.value < 0x20 || ch.value == 0x7F {
                    escaped += String(format: "\\u%04X", ch.value)
                } else {
                    escaped.unicodeScalars.append(ch)
                }
            }
        }
        return "\"\(escaped)\""
    }

    static func num(_ v: CGFloat) -> String {
        let s = String(format: "%.4f", Double(v))
        // Trim trailing zeros but keep it a float: 0.5000 -> 0.5, 1.0000 -> 1.0.
        // Four places keeps restores within a fraction of a point on a 6K screen.
        var t = s
        while t.hasSuffix("0") && !t.hasSuffix(".0") { t.removeLast() }
        return t
    }

    /// Layout names become file names; keep them filesystem- and TOML-key-safe.
    public static func sanitizedName(_ name: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = name.trimmingCharacters(in: .whitespaces).lowercased().unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        }
        let collapsed = String(mapped).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? nil : collapsed
    }
}

extension SnapEngine {
    /// Maps fractions onto the usable area with no inner gaps, so a captured
    /// frame comes back exactly where it was.
    public func frame(forRaw unit: UnitRect, in visible: CGRect) -> CGRect {
        let a = usableArea(visible)
        return CGRect(
            x: a.minX + unit.x * a.width,
            y: a.minY + unit.y * a.height,
            width: unit.w * a.width,
            height: unit.h * a.height
        ).pixelAligned
    }
}
