import AppKit

/// The menu bar item. Kept dumb: it renders state and forwards clicks.
@MainActor
public final class StatusMenu: NSObject, NSMenuDelegate {
    /// A line in the menu describing a problem. Clicking it opens `url`, or
    /// the config file when `url` is nil.
    public struct Notice {
        public enum Kind { case error, info }
        public var text: String
        public var kind: Kind
        public var url: URL?

        public init(_ text: String, kind: Kind, url: URL? = nil) {
            self.text = text
            self.kind = kind
            self.url = url
        }
    }

    public struct State {
        public var enabled: Bool
        public var trusted: Bool
        /// Errors (config not applied, shortcut taken) turn the icon into a warning.
        public var notices: [Notice]

        public init(enabled: Bool, trusted: Bool, notices: [Notice] = []) {
            self.enabled = enabled
            self.trusted = trusted
            self.notices = notices
        }

        var hasErrors: Bool { notices.contains { $0.kind == .error } }
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
        if s.hasErrors {
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
        item.button?.toolTip = s.notices.first { $0.kind == .error }.map { "rook: \($0.text)" } ?? description
    }

    /// Rebuilt on every open so it always reflects live state.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = state()

        let title = s.trusted ? (s.enabled ? "rook is running" : "rook is paused") : "rook: waiting for Accessibility access"
        menu.addItem(disabled(title))

        if !s.notices.isEmpty {
            menu.addItem(.separator())
            for notice in s.notices.sorted(by: { $0.kind == .error && $1.kind != .error }) {
                let prefix = notice.kind == .error ? "⚠︎" : "ⓘ"
                let item = action("\(prefix) \(notice.text)", #selector(openNotice(_:)))
                item.representedObject = notice.url
                menu.addItem(item)
            }
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
    @objc private func openNotice(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) } else { onOpenConfig() }
    }
    @objc private func revealConfig() { onRevealConfig() }
    @objc private func reloadConfig() { onReloadConfig() }
    @objc private func quit() { onQuit() }
}
