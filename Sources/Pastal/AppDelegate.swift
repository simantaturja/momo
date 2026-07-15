import AppKit
import PastalCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var coordinator: AppCoordinator!
    private var hotkey: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = try! AppCoordinator()
        coordinator.startPolling()
        _ = coordinator.panel  // eager pre-warm: build panel/HistoryView at launch, not on first hotkey press

        hotkey = HotkeyManager { [weak self] in self?.coordinator.panel.toggle() }
        hotkey.register()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📋"
        let menu = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = Settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit Pastal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        Settings.launchAtLogin.toggle()
        sender.state = Settings.launchAtLogin ? .on : .off
    }
}
