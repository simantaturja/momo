import AppKit
import PastalCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var coordinator: AppCoordinator!
    private var hotkey: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = try! AppCoordinator()
        coordinator.startPolling()

        hotkey = HotkeyManager { [weak self] in self?.coordinator.panel.toggle() }
        hotkey.register()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "📋"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Pastal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
