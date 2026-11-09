import AppKit
import ApplicationServices

/// Accessibility permission handling. rook can't do anything without it, so
/// the flow is: explain once, open the right Settings pane, then poll and start
/// automatically the moment the user flips the switch. No relaunch needed.
@MainActor
public enum Accessibility {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    private static var pollTimer: Timer?

    public static func ensureTrusted(then start: @escaping @MainActor () -> Void) {
        if isTrusted {
            start()
            return
        }

        let alert = NSAlert()
        alert.messageText = "rook needs Accessibility access"
        alert.informativeText = """
            macOS only lets apps move and resize other apps' windows with Accessibility \
            permission. Turn on rook in System Settings → Privacy & Security → Accessibility. \
            rook starts working as soon as it's enabled.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            // The prompt option also adds rook to the list so the user only has to toggle it.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard isTrusted else { return }
                pollTimer?.invalidate()
                pollTimer = nil
                start()
            }
        }
    }
}
