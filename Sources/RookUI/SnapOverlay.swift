import AppKit
import QuartzCore
import RookCore

/// The translucent preview showing where a dragged window will land.
/// Click-through, never activates, follows the user across Spaces.
@MainActor
public final class SnapOverlay {
    private let panel: NSPanel
    private let box = NSView()
    private var shownFrame: CGRect?
    /// Guards against a finished fade-out hiding a panel that was re-shown meanwhile.
    private var generation = 0

    public init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 2
        box.autoresizingMask = [.width, .height]
        panel.contentView = box
    }

    /// - Parameter frame: target frame in AX coordinates.
    public func show(_ frame: CGRect) {
        guard frame != shownFrame else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitFrame = Coordinates.flip(frame, primaryHeight: primaryHeight)
        generation += 1

        // Resolve the accent colour now so it tracks the user's setting.
        let accent = NSColor.controlAccentColor
        box.layer?.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        box.layer?.borderColor = accent.withAlphaComponent(0.75).cgColor

        if shownFrame == nil {
            panel.setFrame(appKitFrame, display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                panel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(appKitFrame, display: true)
                panel.animator().alphaValue = 1
            }
        }
        shownFrame = frame
    }

    public func hide() {
        guard shownFrame != nil else { return }
        shownFrame = nil
        generation += 1
        let current = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
            }
        })
    }
}
