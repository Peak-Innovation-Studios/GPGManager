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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 240),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: content(close))
        panel.delegate = self
        panel.center()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        self.window = panel
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
