import AppKit
import RookAX
import RookCore

/// Applies and captures named layouts.
@MainActor
final class LayoutRunner {
    /// How long to wait for a launched app's first window.
    static let launchTimeout: TimeInterval = 12
    /// Apps often move their first window right after showing it (state
    /// restoration), so wait this long after it appears before placing it.
    static let settleDelay: TimeInterval = 0.35

    var onFinish: (_ layout: String, _ problems: [String]) -> Void = { _, _ in }

    private let windows: WindowController
    private var task: Task<Void, Never>?

    init(windows: WindowController) {
        self.windows = windows
    }

    // MARK: Apply

    /// Starts applying a layout. A new apply cancels one still in progress.
    func apply(_ layout: Layout) {
        task?.cancel()
        task = Task { [weak self] in await self?.run(layout) }
    }

    private func run(_ layout: Layout) async {
        var problems: [String] = []
        let displays = DisplayManager.displays
        let started = Date()
        let covered = Self.displaysShowingFullscreen(displays)
        Log.layout.notice("applying '\(layout.name, privacy: .public)' (\(layout.entries.count) windows)")

        // Group entries by app, keeping the order they were written in.
        var apps: [String] = []
        var entries: [String: [LayoutEntry]] = [:]
        for entry in layout.entries {
            if entries[entry.app] == nil { apps.append(entry.app) }
            entries[entry.app, default: []].append(entry)
        }

        // Launch everything that's missing at once, without stealing focus,
        // then place apps as their windows show up.
        var launched: Set<String> = []
        var pending: [String] = []
        for app in apps {
            if let running = Self.running(app) {
                if running.isHidden { running.unhide() }
                pending.append(app)
            } else if entries[app]!.contains(where: \.launch) {
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else {
                    problems.append("\(app) isn't installed")
                    continue
                }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                launched.insert(app)
                pending.append(app)
            }
        }

        let deadline = Date().addingTimeInterval(Self.launchTimeout)
        var firstSeen: [String: Date] = [:]
        var frontApp: pid_t?

        while !pending.isEmpty, !Task.isCancelled {
            for app in pending {
                guard let running = Self.running(app) else { continue }
                // Fullscreen windows can't be placed; don't let one use up an entry.
                let found = AXWindow.windows(of: running.processIdentifier).filter { !$0.isFullscreen }
                if found.isEmpty {
                    if !launched.contains(app) {
                        // Accessibility only lists windows on the current Space.
                        problems.append("\(Self.displayName(app)) has no windows on the current Space")
                        pending.removeAll { $0 == app }
                    }
                    continue
                }
                if launched.contains(app) {
                    let seen = firstSeen[app] ?? Date()
                    firstSeen[app] = seen
                    guard Date().timeIntervalSince(seen) >= Self.settleDelay else { continue }
                }

                let appEntries = entries[app]!
                let assignment = LayoutMatcher.assign(entries: appEntries, windowTitles: found.map(\.title))
                let missing = assignment.filter { $0 == nil }.count
                if missing > 0 {
                    problems.append("\(Self.displayName(app)): \(missing) of \(appEntries.count) windows not found")
                }
                for (i, windowIndex) in assignment.enumerated() {
                    guard let windowIndex else { continue }
                    let entry = appEntries[i]
                    guard let display = entry.display.select(from: displays) else { continue }
                    if covered.contains(display.id) {
                        problems.append("\(Self.displayName(app)) went to \(display.name), which is showing a fullscreen app: it's on that display's desktop, behind it")
                    }
                    windows.place(entry.rect, on: found[windowIndex], display: display)
                    Log.layout.notice("  \(app, privacy: .public) → \(String(describing: entry.rect), privacy: .public) on \(display.name, privacy: .public): \(String(describing: found[windowIndex].frame), privacy: .public)")
                }
                if app == apps.first { frontApp = running.processIdentifier }
                pending.removeAll { $0 == app }
            }
            if pending.isEmpty || Date() > deadline { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !Task.isCancelled else {
            Log.layout.notice("'\(layout.name, privacy: .public)' cancelled")
            return
        }

        for app in pending {
            problems.append("\(Self.displayName(app)) didn't open a window in time")
        }
        // The first app in the layout ends up in front.
        if let frontApp { NSRunningApplication(processIdentifier: frontApp)?.activate() }
        Log.layout.notice("applied '\(layout.name, privacy: .public)' in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s, problems: \(problems, privacy: .public)")
        onFinish(layout.name, problems)
    }

    // MARK: Capture

    /// The current arrangement of visible windows, front to back.
    func capture() -> [LayoutEntry] {
        let displays = DisplayManager.displays
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var captured: [(order: Int, entry: LayoutEntry)] = []
        let zOrder = Self.zOrder()

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isHidden,
                  app.processIdentifier != ownPID,
                  let bundleID = app.bundleIdentifier
            else { continue }

            let appWindows = AXWindow.windows(of: app.processIdentifier).filter { !$0.isMinimized && !$0.isFullscreen }
            for window in appWindows {
                guard let frame = window.frame, let display = DisplayManager.display(for: frame) else { continue }
                var entry = LayoutEntry(
                    app: bundleID,
                    display: Self.selector(for: display, among: displays),
                    rect: LayoutCapture.rect(for: frame, visible: display.visibleFrame, engine: windows.engine)
                )
                // Titles only help tell an app's windows apart.
                if appWindows.count > 1, let title = window.title, !title.isEmpty { entry.title = title }
                let order = window.windowID.flatMap { zOrder[$0] } ?? Int.max
                captured.append((order, entry))
            }
        }
        return captured.sorted { $0.order < $1.order }.map(\.entry)
    }

    /// Prefers readable selectors, falling back to the UUID for identical monitors.
    private static func selector(for display: Display, among all: [Display]) -> DisplaySelector {
        if all.count == 1 || display.isMain { return .main }
        if all.filter({ $0.name == display.name }).count == 1 { return .named(display.name) }
        return display.uuid.map { .named($0) } ?? .main
    }

    /// Window ID → front-to-back position for on-screen windows.
    private static func zOrder() -> [CGWindowID: Int] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var order: [CGWindowID: Int] = [:]
        for (i, window) in info.enumerated() {
            if let number = window[kCGWindowNumber as String] as? NSNumber { order[CGWindowID(number.uint32Value)] = i }
        }
        return order
    }

    /// Displays whose current Space is a native-fullscreen app. A window moved
    /// there lands on the display's regular desktop Space, out of sight.
    private static func displaysShowingFullscreen(_ displays: [Display]) -> Set<CGDirectDisplayID> {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var covered: Set<CGDirectDisplayID> = []
        for window in info where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            for display in displays where bounds.isApproximately(display.frame, tolerance: 1) {
                covered.insert(display.id)
            }
        }
        return covered
    }

    private static func running(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    private static func displayName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}
