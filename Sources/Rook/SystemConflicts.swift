import Foundation
import RookUI

/// macOS features that fight rook's drag snapping. Read fresh each time the
/// menu opens, so the warning disappears as soon as the user flips the setting.
enum SystemConflicts {
    private static var domain: CFString { "com.apple.WindowManager" as CFString }
    static let desktopSettings = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")

    static func notices(dragEnabled: Bool) -> [StatusMenu.Notice] {
        CFPreferencesAppSynchronize(domain)
        var notices: [StatusMenu.Notice] = []

        // macOS 15 added edge-drag tiling. Absent keys mean the default: on.
        if dragEnabled, ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) {
            let edge = bool("EnableTilingByEdgeDrag") ?? true
            let top = bool("EnableTopTilingByEdgeDrag") ?? true
            if edge || top {
                notices.append(.init(
                    "macOS edge tiling is also on: turn off “Drag windows to screen edges/menu bar” in Desktop & Dock",
                    kind: .info, url: desktopSettings
                ))
            }
        }

        if bool("GloballyEnabled") == true {
            notices.append(.init(
                "Stage Manager is on and may move windows rook places",
                kind: .info, url: desktopSettings
            ))
        }
        return notices
    }

    private static func bool(_ key: String) -> Bool? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain) else { return nil }
        return (value as? NSNumber)?.boolValue
    }
}
