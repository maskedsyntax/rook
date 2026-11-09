import AppKit

/// The menu bar item. Kept dumb: it renders state and forwards clicks.
@MainActor
public final class StatusMenu: NSObject, NSMenuDelegate {
    public struct State {
        public var enabled: Bool
        public var trusted: Bool
        /// Blocking problems (config errors, shortcuts that couldn't register).
        /// Any of these turns the icon into a warning.
        public var errors: [String]
        /// Non-blocking notes (unknown config keys).
        public var warnings: [String]

        public init(enabled: Bool, trusted: Bool, errors: [String] = [], warnings: [String] = []) {
            self.enabled = enabled
            self.trusted = trusted
            self.errors = errors
            self.warnings = warnings
        }
    }

    public var state: () -> State = { State(enabled: true, trusted: false) }
    public var onToggleEnabled: () -> Void = {}
    public var onOpenConfig: () -> Void = {}
    public var onRevealConfig: () -> Void = {}
    public var onReloadConfig: () -> Void = {}
    public var onQuit: () -> Void = { NSApp.terminate(nil) }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    public override init() {
        super.init()
        menu.delegate = self
        item.menu = menu
        refreshIcon()
    }

    /// Call whenever state changes so the icon reflects it without opening the menu.
    public func refreshIcon() {
        let s = state()
        let symbol: String
        let description: String
        if !s.errors.isEmpty {
            symbol = "exclamationmark.triangle"
            description = "rook: problem"
        } else if !s.enabled || !s.trusted {
            symbol = "rectangle.split.2x1.slash"
            description = "rook: inactive"
        } else {
            symbol = "rectangle.split.2x1"
            description = "rook"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: description)
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = s.errors.first.map { "rook: \($0)" } ?? description
    }

    /// Rebuilt on every open so it always reflects live state.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = state()

        let title = s.trusted ? (s.enabled ? "rook is running" : "rook is paused") : "rook: waiting for Accessibility access"
        menu.addItem(disabled(title))

        if !s.errors.isEmpty || !s.warnings.isEmpty {
            menu.addItem(.separator())
            // Clicking a problem opens the config, where it can be fixed.
            for e in s.errors { menu.addItem(action("⚠︎ \(e)", #selector(openConfig))) }
            for w in s.warnings { menu.addItem(action("ⓘ \(w)", #selector(openConfig))) }
        }

        menu.addItem(.separator())
        let toggle = action("Enabled", #selector(toggleEnabled))
        toggle.state = s.enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        menu.addItem(action("Open Config", #selector(openConfig), key: ","))
        menu.addItem(action("Reveal Config in Finder", #selector(revealConfig)))
        menu.addItem(action("Reload Config", #selector(reloadConfig), key: "r"))

        menu.addItem(.separator())
        menu.addItem(action("Quit rook", #selector(quit), key: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() { onToggleEnabled() }
    @objc private func openConfig() { onOpenConfig() }
    @objc private func revealConfig() { onRevealConfig() }
    @objc private func reloadConfig() { onReloadConfig() }
    @objc private func quit() { onQuit() }
}
