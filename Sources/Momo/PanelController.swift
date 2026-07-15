import AppKit

final class PanelController {
    let panel: NSPanel
    private(set) var previousApp: NSRunningApplication?

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
