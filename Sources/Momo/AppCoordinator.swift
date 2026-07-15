import AppKit
import MomoCore

final class AppCoordinator {
    let store: Store
    let index = HistoryIndex()
    let monitor: ClipboardMonitor
    let imagesDir: String
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "momo.poll", qos: .utility)
    private var didWarnNoAccessibility = false

    // MARK: Store location

    static func appSupportDir() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Momo")
    }
    static var dbPath: String { appSupportDir().appendingPathComponent("history.sqlite").path }
    static var imagesDirPath: String { appSupportDir().appendingPathComponent("images").path }

    /// Moves a damaged database aside so a fresh one can be created on the next attempt.
    static func quarantineDatabase() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dbPath) else { return }
        let aside = dbPath + ".corrupt-\(Int(Date().timeIntervalSince1970))"
        try? fm.moveItem(atPath: dbPath, toPath: aside)
        NSLog("Momo: quarantined unreadable database to \(aside)")
    }

    lazy var historyView = HistoryView(
        index: index,
        imagesDir: imagesDir,
        onChoose: { [weak self] item in self?.paste(item) },
        onPinToggle: { [weak self] item in
            guard let self else { return }
            self.pollQueue.async {
                try? self.store.setPinned(id: item.id, pinned: !item.pinned)
                self.reloadIndexFromStore()
            }
        },
        onDelete: { [weak self] item in
            guard let self else { return }
            self.pollQueue.async {
                try? self.store.delete(id: item.id)
                self.reloadIndexFromStore()
            }
        },
        onCancel: { [weak self] in self?.dismiss() }
    )
    lazy var panel = PanelController(contentView: historyView)

    init() throws {
        imagesDir = Self.imagesDirPath
        store = try Store(path: Self.dbPath, imagesDirectory: imagesDir)
        let reader = NSPasteboardReader()
        monitor = ClipboardMonitor(pasteboard: reader, writeImageBlob: { [store] data in
            try store.writeImageBlob(data)
        })

        index.replaceAll((try? store.recent(limit: Settings.maxItems)) ?? [])
        monitor.onNewItem = { [weak self] item in
            guard let self else { return }
            do {
                try self.store.upsert(item)
            } catch {
                NSLog("Momo: failed to persist clipboard item: \(error)")
                return   // don't show an item we didn't save
            }
            DispatchQueue.main.async {
                self.index.prepend(item)
                self.historyView.reload(preserveSelection: true)
            }
            self.pollQueue.async { self.runPrune() }
        }

        // Reclaim any blobs left behind by a prior crash between blob-write and row-commit.
        let store = self.store
        pollQueue.async { _ = try? store.reapOrphanBlobs() }
    }

    func runPrune() {
        let deleted = (try? store.prune(maxItems: Settings.maxItems,
                                        maxImageBytes: Settings.maxImageBytes,
                                        imageMaxAge: Settings.imageMaxAge,
                                        now: Date())) ?? 0
        if deleted > 0 { reloadIndexFromStore() }   // skip the refetch/reload when nothing changed
    }

    func clearHistory() {
        pollQueue.async {
            try? self.store.deleteAll()
            self.reloadIndexFromStore()
        }
    }

    private func reloadIndexFromStore() {
        let items = (try? store.recent(limit: Settings.maxItems)) ?? []
        DispatchQueue.main.async {
            self.index.replaceAll(items)
            self.historyView.reload(preserveSelection: true)
        }
    }

    func dismiss() {
        panel.hide()
        panel.restorePreviousApp()
    }

    func paste(_ item: ClipboardItem) {
        let wrote = Paster.writeToPasteboard(item, imagesDir: imagesDir)
        panel.hide()
        panel.restorePreviousApp()
        guard wrote else {
            NSLog("Momo: nothing to paste for item \(item.id) (missing blob or empty payload)")
            return
        }
        guard Paster.isAccessibilityTrusted else {
            warnAccessibilityOnce()   // item is on the clipboard; can't synthesize the keystroke
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
