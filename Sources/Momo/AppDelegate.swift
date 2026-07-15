import AppKit
import MomoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var coordinator: AppCoordinator!
    private var hotkey: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = try! AppCoordinator()
        coordinator.startPolling()
        _ = coordinator.panel  // eager pre-warm: build panel/HistoryView at launch, not on first hotkey press

        // Auto-paste synthesizes ⌘V, which needs Accessibility trust. Prompt once on first run.
        Paster.promptForAccessibilityIfNeeded()

        hotkey = HotkeyManager { [weak self] in self?.coordinator.panel.toggle() }
        if !hotkey.register() { warnHotkeyRegistrationFailed() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.momoIcon()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Momo", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = Settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit Momo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func showPanel() { coordinator.panel.show() }

    private func warnHotkeyRegistrationFailed() {
        let alert = NSAlert()
        alert.messageText = "Momo couldn't register its ⌘⇧V shortcut"
        alert.informativeText = "Another app may already use ⌘⇧V. You can still open Momo any time from the menu bar icon (\"Show Momo\")."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // Momo: solid pouch silhouette, flat bottom, ruffled topknot, pleats punched out.
    private static func momoIcon() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 2.6, y: 4.0))
            body.line(to: NSPoint(x: 15.4, y: 4.0))
            body.curve(to: NSPoint(x: 11.6, y: 12.0),
                       controlPoint1: NSPoint(x: 16.6, y: 7.8), controlPoint2: NSPoint(x: 14.8, y: 11.0))
            body.curve(to: NSPoint(x: 9.9, y: 13.3),
                       controlPoint1: NSPoint(x: 12.1, y: 13.6), controlPoint2: NSPoint(x: 10.9, y: 14.1))
            body.curve(to: NSPoint(x: 8.1, y: 13.3),
                       controlPoint1: NSPoint(x: 9.4, y: 14.9), controlPoint2: NSPoint(x: 8.6, y: 14.9))
            body.curve(to: NSPoint(x: 6.4, y: 12.0),
                       controlPoint1: NSPoint(x: 7.1, y: 14.1), controlPoint2: NSPoint(x: 5.9, y: 13.6))
            body.curve(to: NSPoint(x: 2.6, y: 4.0),
                       controlPoint1: NSPoint(x: 3.2, y: 11.0), controlPoint2: NSPoint(x: 1.4, y: 7.8))
            body.close()
            NSColor.black.setFill()
            body.fill()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setStroke()
            let pleats: [(NSPoint, NSPoint, NSPoint)] = [
                (NSPoint(x: 6.6, y: 11.2), NSPoint(x: 4.6, y: 6.0), NSPoint(x: 5.0, y: 9.0)),
                (NSPoint(x: 8.9, y: 11.6), NSPoint(x: 8.6, y: 5.6), NSPoint(x: 8.2, y: 8.8)),
                (NSPoint(x: 11.2, y: 11.2), NSPoint(x: 13.2, y: 6.0), NSPoint(x: 12.8, y: 9.0)),
            ]
            for (from, to, cp) in pleats {
                let p = NSBezierPath()
                p.move(to: from)
                p.curve(to: to, controlPoint1: cp, controlPoint2: cp)
                p.lineWidth = 1.1
                p.lineCapStyle = .round
                p.stroke()
            }
            let notch = NSBezierPath()
            notch.move(to: NSPoint(x: 6.6, y: 12.1))
            notch.curve(to: NSPoint(x: 11.4, y: 12.1),
                        controlPoint1: NSPoint(x: 8.0, y: 11.3), controlPoint2: NSPoint(x: 10.0, y: 11.3))
            notch.lineWidth = 0.9
            notch.lineCapStyle = .round
            notch.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        Settings.launchAtLogin.toggle()
        sender.state = Settings.launchAtLogin ? .on : .off
    }
}
