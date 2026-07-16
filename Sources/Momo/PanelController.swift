import AppKit

final class PanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private(set) var previousApp: NSRunningApplication?
    var onResignKey: (() -> Void)?

    init(contentView: NSView) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false      // never torn down -> pre-warmed
        panel.contentView = contentView
        panel.center()
        super.init()
        panel.delegate = self
    }

    func windowDidResignKey(_ notification: Notification) {
        // Dismiss on focus loss (click-outside). Re-check async so a transient key
        // flutter during show() does not dismiss the freshly-opened panel.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.onResignKey?()
        }
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        panel.center()
        let start = DispatchTime.now()
        panel.makeKeyAndOrderFront(nil)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        NSLog("Momo open render: \(ms) ms")
        NSApp.activate(ignoringOtherApps: true)
        (panel.contentView as? HistoryView)?.focusSearch()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func restorePreviousApp() {
        previousApp?.activate()
    }
}
