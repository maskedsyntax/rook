import Foundation
import ServiceManagement

/// Launch at login through `SMAppService` (macOS 13+). It registers the app
/// at its current path, so it should be the copy in /Applications.
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Whether the user still has to allow it in System Settings ▸ Login Items.
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static var isInApplications: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path.hasSuffix("/Applications")
    }

    /// Flips the setting. Returns an error message to show, if any.
    static func toggle() -> String? {
        do {
            if isEnabled || needsApproval {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            }
            return nil
        } catch {
            return "Couldn't change Launch at Login: \(error.localizedDescription)"
        }
    }
}
