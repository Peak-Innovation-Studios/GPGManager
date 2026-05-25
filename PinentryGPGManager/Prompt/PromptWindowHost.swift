import AppKit
import SwiftUI

final class PromptWindowHost: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var onClose: (() -> Void)?
    private var retainedSelf: PromptWindowHost?

    func show<Content: View>(
        title: String,
        @ViewBuilder content: (@escaping () -> Void) -> Content,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        self.retainedSelf = self

        let close: () -> Void = { [weak self] in
            self?.dismiss()
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 320),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false

        // NSHostingController with .preferredContentSize tracks the SwiftUI
        // view's natural size and resizes the panel as content changes. The
        // alternative (NSHostingView) doesn't update window size when the
        // hosted view's intrinsic content size changes.
        let hosting = NSHostingController(rootView: content(close))
        hosting.sizingOptions = .preferredContentSize
        panel.contentViewController = hosting
        panel.delegate = self
        centerOnActiveScreen(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        self.window = panel
    }

    /// Places the panel in the visible region of the screen the user is most
    /// likely looking at. NSWindow.center() always uses the main display, which
    /// is wrong when the calling app (Terminal, IDE, etc.) is on a secondary
    /// monitor. Mouse location is the best available proxy without requiring
    /// Accessibility permissions to query other apps' window frames.
    private func centerOnActiveScreen(_ panel: NSPanel) {
        guard let screen = activeScreen() else {
            panel.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visibleFrame.origin.x + (visibleFrame.width - size.width) / 2,
            y: visibleFrame.origin.y + (visibleFrame.height - size.height) / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return hit
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func dismiss() {
        window?.orderOut(nil)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
        window = nil
        retainedSelf = nil
    }
}
