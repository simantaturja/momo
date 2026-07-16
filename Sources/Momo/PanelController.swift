import AppKit

final class PanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private let content: NSView
    private(set) var previousApp: NSRunningApplication?
    var onResignKey: (() -> Void)?

    init(contentView: NSView) {
        content = contentView
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false      // never torn down -> pre-warmed

        // Translucent rounded card: a vibrancy view is the window's content, with the
        // history view pinned inside it. Built once here (pre-warm) — nothing on show().
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: effect.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
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
        (content as? HistoryView)?.focusSearch()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func restorePreviousApp() {
        previousApp?.activate()
    }
}
