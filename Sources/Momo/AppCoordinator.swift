import AppKit
import MomoCore

final class AppCoordinator {
    let store: Store
    let index = HistoryIndex()
    let monitor: ClipboardMonitor
    let imagesDir: String
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "momo.poll", qos: .utility)

    lazy var historyView = HistoryView(
        index: index,
        imagesDir: imagesDir,
        onChoose: { [weak self] item in self?.paste(item) },   // paste() added in Task 11
        onPinToggle: { [weak self] item in
            guard let self else { return }
            self.pollQueue.async {
                try? self.store.setPinned(id: item.id, pinned: !item.pinned)
                self.reloadIndexFromStore()
            }
        },
        onCancel: { [weak self] in self?.dismiss() }
    )
    lazy var panel = PanelController(contentView: historyView)

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Momo")
        let dbPath = appSupport.appendingPathComponent("history.sqlite").path
        imagesDir = appSupport.appendingPathComponent("images").path
        store = try Store(path: dbPath, imagesDirectory: imagesDir)
        let reader = NSPasteboardReader()
        monitor = ClipboardMonitor(pasteboard: reader, writeImageBlob: { [store] data in
            try store.writeImageBlob(data)
        })

        index.replaceAll((try? store.recent(limit: 1000)) ?? [])
        monitor.onNewItem = { [weak self] item in
            guard let self else { return }
            try? self.store.upsert(item)
            DispatchQueue.main.async {
                self.index.prepend(item)
                self.historyView.reload()
            }
            self.pollQueue.async { self.runPrune() }
        }
    }

    func runPrune() {
        try? store.prune(maxItems: Settings.maxItems,
                         maxImageBytes: Settings.maxImageBytes,
                         imageMaxAge: Settings.imageMaxAge,
                         now: Date())
        reloadIndexFromStore()
    }

    private func reloadIndexFromStore() {
        let items = (try? store.recent(limit: 1000)) ?? []
        DispatchQueue.main.async {
            self.index.replaceAll(items)
            self.historyView.reload()
        }
    }

    func dismiss() {
        panel.hide()
        panel.restorePreviousApp()
    }

    private var didWarnNoAccessibility = false

    func paste(_ item: ClipboardItem) {
        Paster.writeToPasteboard(item, imagesDir: imagesDir)
        panel.hide()
        panel.restorePreviousApp()
        guard Paster.isAccessibilityTrusted else {
            warnAccessibilityOnce()   // item is already on the clipboard; can't synth the keystroke
            return
        }
        // Give focus a beat to return, then synth Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
            Paster.synthesizePaste()
        }
    }

    private func warnAccessibilityOnce() {
        Paster.promptForAccessibilityIfNeeded()
        guard !didWarnNoAccessibility else { return }
        didWarnNoAccessibility = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Momo needs Accessibility permission to paste automatically"
        alert.informativeText = "Your item is already on the clipboard — press ⌘V to paste it now.\n\nTo enable automatic paste, allow Momo under System Settings ▸ Privacy & Security ▸ Accessibility."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.monitor.poll(now: Date()) }
        timer.resume()
        pollTimer = timer
    }
}
