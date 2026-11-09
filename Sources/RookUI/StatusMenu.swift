import AppKit

/// The menu bar item. Kept dumb: it renders state and forwards clicks.
@MainActor
public final class StatusMenu: NSObject, NSMenuDelegate {
    public struct State {
        public var enabled: Bool
        public var trusted: Bool
        public var problems: [String]

        public init(enabled: Bool, trusted: Bool, problems: [String] = []) {
            self.enabled = enabled
            self.trusted = trusted
            self.problems = problems
        }
    }

    public var state: () -> State = { State(enabled: true, trusted: false) }
    public var onToggleEnabled: () -> Void = {}
    public var onQuit: () -> Void = { NSApp.terminate(nil) }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    public override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "rook")
        item.button?.image?.isTemplate = true
        menu.delegate = self
        item.menu = menu
    }

    /// Rebuilt on every open so it always reflects live state.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = state()

        let header = NSMenuItem(title: s.trusted ? "rook is running" : "rook: waiting for Accessibility access", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for problem in s.problems {
            let p = NSMenuItem(title: "⚠︎ \(problem)", action: nil, keyEquivalent: "")
            p.isEnabled = false
            menu.addItem(p)
        }

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = s.enabled ? .on : .off
        menu.addItem(toggle)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit rook", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() { onToggleEnabled() }
    @objc private func quit() { onQuit() }
}
