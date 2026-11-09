import AppKit
import RookAX
import RookCore
import RookInput
import RookUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowController()
    private let statusMenu = StatusMenu()
    private let configURL = ConfigLocation.url
    private lazy var watcher = ConfigWatcher(url: configURL)

    private var config = Config.default
    private var enabled = true
    private var started = false

    /// Why the current file isn't in effect (nil = it is).
    private var configError: ConfigError?
    private var configWarnings: [ConfigError] = []
    private var hotkeyErrors: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AX.configureTimeout()

        statusMenu.state = { [unowned self] in
            var errors: [String] = []
            if let configError { errors.append("Config not applied: \(configError)") }
            errors += hotkeyErrors
            return .init(
                enabled: enabled,
                trusted: Accessibility.isTrusted,
                errors: errors,
                warnings: configWarnings.map(\.description)
            )
        }
        statusMenu.onToggleEnabled = { [unowned self] in
            enabled.toggle()
            registerHotkeys()
        }
        statusMenu.onOpenConfig = { [unowned self] in openConfig() }
        statusMenu.onRevealConfig = { [unowned self] in
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        }
        statusMenu.onReloadConfig = { [unowned self] in loadConfig() }

        do {
            try ConfigLocation.createIfMissing()
        } catch {
            configError = ConfigError("couldn't create \(configURL.path): \(error.localizedDescription)")
        }
        loadConfig()
        watcher.onChange = { [unowned self] in loadConfig() }
        watcher.start()

        Accessibility.ensureTrusted { [unowned self] in start() }
    }

    private func start() {
        guard !started else { return }
        started = true
        registerHotkeys()
    }

    // MARK: Config

    /// Reads and applies the config. On any error the previous config stays
    /// active, so a typo mid-edit never leaves you without shortcuts.
    private func loadConfig() {
        defer {
            watcher.markCurrent()
            statusMenu.refreshIcon()
        }

        let source: String
        do {
            source = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            configError = ConfigError("couldn't read \(configURL.path): \(error.localizedDescription)")
            return
        }

        switch Config.parse(source) {
        case .success(let result):
            config = result.config
            configWarnings = result.warnings
            configError = nil
            windows.engine = config.engine
            if started { registerHotkeys() }
        case .failure(let error):
            configError = error
        }
    }

    private func openConfig() {
        let workspace = NSWorkspace.shared
        if workspace.urlForApplication(toOpen: configURL) != nil {
            workspace.open(configURL)
        } else if let textEdit = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            // No app claims .toml on a fresh Mac; fall back to a plain-text editor.
            workspace.open([configURL], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Hotkeys

    private func registerHotkeys() {
        HotkeyManager.shared.unregisterAll()
        hotkeyErrors.removeAll()
        defer { statusMenu.refreshIcon() }
        guard enabled, started else { return }

        for binding in config.bindings {
            let command = binding.command
            do {
                try HotkeyManager.shared.register(binding.combo) { [unowned self] in
                    run(command)
                }
            } catch {
                hotkeyErrors.append("\(binding.shortcut): \(error)")
            }
        }
    }

    private func run(_ command: Command) {
        switch command {
        case .snap(let action): windows.perform(action)
        case .reloadConfig: loadConfig()
        }
    }
}
