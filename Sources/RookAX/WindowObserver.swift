import AppKit
import ApplicationServices

/// Reports windows as they're created, for the apps it's told to watch.
///
/// One AXObserver per watched, running app (cheap: apps without rules are
/// never observed). Apps that launch later are picked up from NSWorkspace.
/// A window that already existed before rook started watching is never
/// reported, so loading rules doesn't rearrange your screen.
@MainActor
public final class WindowObserver {
    /// Called with the app's bundle id and the new window.
    public var onWindowCreated: (String, AXWindow) -> Void = { _, _ in }

    private var bundleIDs: Set<String> = []
    private var observers: [pid_t: AXObserver] = [:]
    private var seen: Set<CGWindowID> = []
    private var workspaceTokens: [NSObjectProtocol] = []

    public init() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid, let bundleID, self.bundleIDs.contains(bundleID) else { return }
                self.observe(pid: pid, bundleID: bundleID, isLaunch: true)
            }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid else { return }
                self.stopObserving(pid: pid)
            }
        })
    }

    /// Replaces the set of watched apps.
    public func watch(bundleIDs newIDs: Set<String>) {
        guard newIDs != bundleIDs else { return }
        bundleIDs = newIDs
        for pid in Array(observers.keys) { stopObserving(pid: pid) }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, newIDs.contains(id) else { continue }
            observe(pid: app.processIdentifier, bundleID: id, isLaunch: false)
        }
    }

    private func observe(pid: pid_t, bundleID: String, isLaunch: Bool) {
        guard observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<WindowObserver>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            nonisolated(unsafe) let element = element
            MainActor.assumeIsolated { me.created(element, pid: pid) }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer

        let existing = AXWindow.windows(of: pid)
        if isLaunch {
            // The first window often exists before the launch notification
            // arrives, so the created notification is missed. Report windows
            // that appear during launch, once they've had a moment to settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for window in AXWindow.windows(of: pid) { self.report(window, bundleID: bundleID) }
                }
            }
        } else {
            for window in existing { if let id = window.windowID { seen.insert(id) } }
        }
    }

    private func stopObserving(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func created(_ element: AXUIElement, pid: pid_t) {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return }
        let window = AXWindow(element: element, app: AXUIElementCreateApplication(pid), pid: pid)
        // Apps often set their final frame (state restoration) just after
        // creating the window; place it after that, not before.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            MainActor.assumeIsolated { self?.report(window, bundleID: bundleID) }
        }
    }

    private func report(_ window: AXWindow, bundleID: String) {
        guard window.subrole == kAXStandardWindowSubrole, let id = window.windowID, !seen.contains(id) else { return }
        seen.insert(id)
        onWindowCreated(bundleID, window)
    }
}
