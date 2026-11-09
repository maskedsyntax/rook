import Foundation

/// A parsed shortcut like `"ctrl+alt+left"`. Key codes are macOS virtual key
/// codes (ANSI layout, same values as Carbon's `kVK_*`).
public struct KeyCombo: Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public let keyCode: UInt32
    public let modifiers: Modifiers
    public let keyName: String

    public init(keyCode: UInt32, modifiers: Modifiers, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyName = keyName
    }

    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty
        case unknownKey(String)
        case missingKey(String)
        case multipleKeys(String)

        public var description: String {
            switch self {
            case .empty: return "empty shortcut"
            case .unknownKey(let k): return "unknown key '\(k)'"
            case .missingKey(let s): return "shortcut '\(s)' has no key, only modifiers"
            case .multipleKeys(let s): return "shortcut '\(s)' has more than one non-modifier key"
            }
        }
    }

    public static func parse(_ string: String) throws(ParseError) -> KeyCombo {
        let tokens = string.lowercased()
            .split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { throw .empty }

        var mods: Modifiers = []
        var key: (code: UInt32, name: String)?
        for token in tokens {
            if let m = modifierNames[token] {
                mods.insert(m)
                continue
            }
            guard let code = keyCodes[token] else { throw .unknownKey(token) }
            guard key == nil else { throw .multipleKeys(string) }
            key = (code, canonicalName[token] ?? token)
        }
        guard let key else { throw .missingKey(string) }
        return KeyCombo(keyCode: key.code, modifiers: mods, keyName: key.name)
    }

    static let modifierNames: [String: Modifiers] = [
        "ctrl": .control, "control": .control, "⌃": .control,
        "alt": .option, "opt": .option, "option": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "cmd": .command, "command": .command, "⌘": .command,
    ]

    static let canonicalName: [String: String] = [
        "enter": "return", "backspace": "delete", "esc": "escape",
        "-": "minus", "=": "equal", "[": "leftbracket", "]": "rightbracket",
        ";": "semicolon", "'": "quote", ",": "comma", ".": "period", "/": "slash",
        "\\": "backslash", "`": "grave",
    ]

    static let keyCodes: [String: UInt32] = {
        var m: [String: UInt32] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06,
            "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E,
            "r": 0x0F, "y": 0x10, "t": 0x11, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23,
            "l": 0x25, "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
            "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17, "6": 0x16,
            "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
            "equal": 0x18, "minus": 0x1B, "rightbracket": 0x1E, "leftbracket": 0x21,
            "quote": 0x27, "semicolon": 0x29, "backslash": 0x2A, "comma": 0x2B,
            "slash": 0x2C, "period": 0x2F, "grave": 0x32,
            "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "escape": 0x35,
            "forwarddelete": 0x75, "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
            "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
            "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
            "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        ]
        for (alias, canonical) in canonicalName { m[alias] = m[canonical] }
        return m
    }()
}
