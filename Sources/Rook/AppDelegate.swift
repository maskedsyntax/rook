import AppKit
import RookAX
import RookCore
import RookInput
import RookUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let windows = WindowController()
    private lazy var drag = DragController(windows: windows)
    private lazy var layouts = LayoutRunner(windows: windows)
    private let windowObserver = WindowObserver()
    private let statusMenu = StatusMenu()
    private let configURL = ConfigLocation.url
    private lazy var watcher = ConfigWatcher(url: configURL, directories: [ConfigLocation.layoutsDirectory])

    private var config = Config.default
    private var enabled = true
    private var started = false

    /// Why the current file isn't in effect (nil = it is).
    private var configError: ConfigError?
    private var configWarnings: [ConfigError] = []
    private var hotkeyErrors: [String] = []
    /// From the last layout apply; cleared on the next one.
    private var layoutProblems: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AX.configureTimeout()

        statusMenu.state = { [unowned self] in
            var notices: [StatusMenu.Notice] = []
            if let configError { notices.append(.init("Config not applied: \(configError)", kind: .error)) }
            notices += hotkeyErrors.map { .init($0, kind: .error) }
            if let tapError = drag.tapError { notices.append(.init(tapError, kind: .error)) }
            notices += configWarnings.map { .init($0.description, kind: .info) }
            notices += layoutProblems.map { .init($0, kind: .info) }
            notices += SystemConflicts.notices(dragEnabled: config.drag.enabled)
            let shortcuts = Dictionary(
                config.bindings.compactMap { b -> (String, String)? in
                    if case .layout(let name) = b.command { return (name, b.shortcut) }
                    return nil
                },
                uniquingKeysWith: { first, _ in first }
            )
            return .init(
                enabled: enabled,
                trusted: Accessibility.isTrusted,
                notices: notices,
                layouts: config.layouts.map { ($0.name, shortcuts[$0.name]) }
            )
        }
        statusMenu.onToggleEnabled = { [unowned self] in
            enabled.toggle()
            registerHotkeys()
            drag.active = enabled && started
        }
        statusMenu.onOpenConfig = { [unowned self] in openConfig() }
        statusMenu.onRevealConfig = { [unowned self] in
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        }
        statusMenu.onReloadConfig = { [unowned self] in loadConfig() }
        statusMenu.onApplyLayout = { [unowned self] name in run(.layout(name)) }
        statusMenu.onSaveLayout = { [unowned self] in saveCurrentLayout() }
        statusMenu.onOpenLayoutsFolder = { NSWorkspace.shared.open(ConfigLocation.layoutsDirectory) }

        layouts.onFinish = { [unowned self] name, problems in
            layoutProblems = problems.map { "layout '\(name)': \($0)" }
            statusMenu.refreshIcon()
        }
        windowObserver.onWindowCreated = { [unowned self] bundleID, window in
            applyRules(to: window, bundleID: bundleID)
        }

        do {
            try ConfigLocation.createIfMissing()
        } catch {
            configError = ConfigError("couldn't create \(configURL.path): \(error.localizedDescription)")
        }
        loadConfig()
        watcher.onChange = { [unowned self] in loadConfig() }
        watcher.start()

        Log.app.notice("launched, accessibility trusted: \(Accessibility.isTrusted)")
        Accessibility.ensureTrusted { [unowned self] in start() }
    }

    /// `rook://` URLs; see `URLCommand`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = URLCommand(url: url) else {
                Log.app.error("ignored URL \(url.absoluteString, privacy: .public)")
                NSSound.beep()
                continue
            }
            Log.app.notice("URL \(url.absoluteString, privacy: .public)")
            switch command {
            case .run(let command): run(command)
            case .saveLayout(let name):
                if let problem = saveLayout(named: name, entries: layouts.capture(), overwrite: false) {
                    Log.app.error("save-layout \(name, privacy: .public): \(problem, privacy: .public)")
                    NSSound.beep()
                }
            }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        registerHotkeys()
        drag.active = enabled
        windowObserver.watch(bundleIDs: Set(config.rules.map(\.app)))
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

        switch Config.parse(source, layoutFiles: ConfigLocation.layoutFiles()) {
        case .success(let result):
            config = result.config
            configWarnings = result.warnings
            configError = nil
            windows.engine = config.engine
            drag.config = config.drag
            if started {
                registerHotkeys()
                windowObserver.watch(bundleIDs: Set(config.rules.map(\.app)))
            }
            Log.app.notice("config loaded: \(self.config.bindings.count) keys, \(self.config.layouts.count) layouts, \(self.config.rules.count) rules, \(result.warnings.count) warnings")
        case .failure(let error):
            configError = error
            Log.app.error("config not applied: \(error.description, privacy: .public)")
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
        defer {
            for problem in hotkeyErrors { Log.app.error("hotkey \(problem, privacy: .public)") }
        }

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
        case .layout(let name):
            guard enabled, started, let layout = config.layout(named: name) else {
                Log.layout.error("can't apply '\(name, privacy: .public)': \(self.config.layout(named: name) == nil ? "no such layout" : "rook is disabled or not trusted")")
                NSSound.beep()
                return
            }
            layoutProblems = []
            layouts.apply(layout)
        }
    }

    // MARK: Rules

    private func applyRules(to window: AXWindow, bundleID: String) {
        guard enabled,
              let rule = config.rules.first(where: { $0.matches(app: bundleID, title: window.title) }),
              let frame = window.frame
        else { return }
        let displays = DisplayManager.displays
        let display = rule.display?.select(from: displays) ?? DisplayManager.display(for: frame)
        guard let display else { return }
        windows.place(rule.rect, on: window, display: display)
        Log.layout.notice("rule \(bundleID, privacy: .public) → \(String(describing: rule.rect), privacy: .public) on \(display.name, privacy: .public): \(String(describing: window.frame), privacy: .public)")
    }

    // MARK: Saving layouts

    private func saveCurrentLayout() {
        let entries = layouts.capture()
        guard !entries.isEmpty else {
            NSSound.beep()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Save current layout"
        alert.informativeText = "Saves where your \(entries.count) visible window\(entries.count == 1 ? "" : "s") are now. Bind it in config.toml with \"<shortcut>\" = \"layout:<name>\"."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "e.g. coding"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let name = LayoutCapture.sanitizedName(field.stringValue) else {
            NSSound.beep()
            return
        }
        let file = ConfigLocation.layoutsDirectory.appendingPathComponent("\(name).toml")
        if FileManager.default.fileExists(atPath: file.path) {
            let confirm = NSAlert()
            confirm.messageText = "Replace layout '\(name)'?"
            confirm.addButton(withTitle: "Replace")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }
        if let problem = saveLayout(named: name, entries: entries, overwrite: true) {
            showError(problem)
        }
    }

    /// Writes `layouts/<name>.toml` and reloads. Returns why it didn't, if it didn't.
    private func saveLayout(named name: String, entries: [LayoutEntry], overwrite: Bool) -> String? {
        guard !entries.isEmpty else { return "there are no windows to save" }
        if let existing = config.layout(named: name), existing.file == nil {
            return "A layout named '\(name)' is already defined in config.toml. Pick another name."
        }
        let file = ConfigLocation.layoutsDirectory.appendingPathComponent("\(name).toml")
        if !overwrite, FileManager.default.fileExists(atPath: file.path) {
            return "layouts/\(name).toml already exists"
        }

        let date = Date().formatted(date: .abbreviated, time: .shortened)
        let text = LayoutCapture.serialize(entries, comment: "Layout '\(name)', saved by rook on \(date).")
        do {
            try FileManager.default.createDirectory(at: ConfigLocation.layoutsDirectory, withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return "Couldn't save the layout: \(error.localizedDescription)"
        }
        Log.layout.notice("saved layout '\(name, privacy: .public)' with \(entries.count) windows")
        loadConfig()
        return nil
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }
}
