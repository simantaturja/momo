import AppKit

final class PanelController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private let content: NSView
    private(set) var previousApp: NSRunningApplication?
    var onResignKey: (() -> Void)?
    /// Screen frame of the menu-bar icon; the panel drops down beneath it (centered if nil).
    var anchorFrame: (() -> NSRect?)?
    /// Called with `true` on show and `false` on hide, e.g. to highlight the menu-bar icon.
    var onVisibilityChange: ((Bool) -> Void)?
    private var lastResignHide = Date.distantPast

    init(contentView: NSView) {
        content = contentView
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false                 // a dropdown stays pinned under its icon
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.allowsToolTipsWhenApplicationIsInactive = true   // a row's "Copied from" tooltip
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
            self.lastResignHide = Date()
            self.onResignKey?()
        }
    }

    func toggle() {
        if panel.isVisible { hide(); restorePreviousApp() }
        // A click on the menu-bar icon can first dismiss the open panel via resign-key;
        // that same click must close it, not immediately reopen it.
        else if Date().timeIntervalSince(lastResignHide) > 0.25 { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        position()
        let start = DispatchTime.now()
        panel.makeKeyAndOrderFront(nil)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        NSLog("Momo open render: \(ms) ms")
        NSApp.activate(ignoringOtherApps: true)
        (content as? HistoryView)?.prepareForShow()
        onVisibilityChange?(true)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        (content as? HistoryView)?.clearHover()
        (content as? HistoryView)?.resetForNextOpen()
        onVisibilityChange?(false)
    }

    /// Drop down from the menu-bar icon like a menu: top edge just under the bar, left edge
    /// aligned with the icon, clamped so the panel stays fully on that screen.
    private func position() {
        guard let icon = anchorFrame?(),
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: icon.midX, y: icon.midY)) }) else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame
        let width = panel.frame.width
        let x = min(max(icon.minX, visible.minX + 8), visible.maxX - width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: min(icon.minY, visible.maxY) - 4))
    }

    func restorePreviousApp() {
        previousApp?.activate()
    }
}
