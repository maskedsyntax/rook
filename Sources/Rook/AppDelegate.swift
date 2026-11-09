import AppKit
import RookAX
import RookCore
import RookInput
import RookUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowController()
    private let statusMenu = StatusMenu()
    private var enabled = true
    private var started = false
    private var problems: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AX.configureTimeout()

        statusMenu.state = { [unowned self] in
            .init(enabled: enabled, trusted: Accessibility.isTrusted, problems: problems)
        }
        statusMenu.onToggleEnabled = { [unowned self] in
            enabled.toggle()
            enabled ? registerHotkeys() : HotkeyManager.shared.unregisterAll()
        }

        Accessibility.ensureTrusted { [unowned self] in start() }
    }

    private func start() {
        guard !started else { return }
        started = true
        registerHotkeys()
    }

    private func registerHotkeys() {
        HotkeyManager.shared.unregisterAll()
        problems.removeAll()
        for (shortcut, action) in DefaultBindings.all {
            do {
                let combo = try KeyCombo.parse(shortcut)
                try HotkeyManager.shared.register(combo) { [unowned self] in
                    windows.perform(action)
                }
            } catch {
                problems.append("\(shortcut): \(error)")
            }
        }
    }
}
