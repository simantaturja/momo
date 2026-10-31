import AppKit
import MomoCore

final class AppCoordinator {
    let store: Store
    let index = HistoryIndex()
    let monitor: ClipboardMonitor
    let imagesDir: String
    private var pollTimer: DispatchSourceTimer?
    /// Called on main after a choice actually landed on the clipboard.
    var onCopied: (() -> Void)?
    private let pollQueue = DispatchQueue(label: "momo.poll", qos: .utility)

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
        onChoose: { [weak self] items in self?.paste(items) },
        onPinToggle: { [weak self] items in
            guard let self else { return }
            let pin = items.contains { !$0.pinned }   // pin all unless every one is already pinned
            self.pollQueue.async {
                for item in items { try? self.store.setPinned(id: item.id, pinned: pin) }
                self.reloadIndexFromStore()
            }
        },
        onDelete: { [weak self] items in
            guard let self else { return }
            self.pollQueue.async {
                for item in items { try? self.store.delete(id: item.id) }
                self.reloadIndexFromStore()
            }
        },
        onCancel: { [weak self] in self?.dismiss() }
    )
    lazy var panel: PanelController = {
        let controller = PanelController(contentView: historyView)
        // Click-outside: hide only. Don't restorePreviousApp() — the user is
        // intentionally moving to another app; reactivating would yank focus.
        controller.onResignKey = { [weak controller] in controller?.hide() }
        return controller
    }()

    init() throws {
        imagesDir = Self.imagesDirPath
        store = try Store(path: Self.dbPath, imagesDirectory: imagesDir)
        let reader = NSPasteboardReader()
        monitor = ClipboardMonitor(pasteboard: reader, writeImageBlob: { [store] data in
            try store.writeImageBlob(data)
        }, allowsConcealed: { Settings.savePasswords })

        index.replaceAll((try? store.recent(limit: Settings.maxItems)) ?? [])
        monitor.onNewItem = { [weak self] item in
            guard let self else { return }
            let stored: ClipboardItem
            do {
                stored = try self.store.upsert(item)
            } catch {
                NSLog("Momo: failed to persist clipboard item: \(error)")
                return   // don't show an item we didn't save
            }
            DispatchQueue.main.async {
                self.index.prepend(stored)   // the stored row: on a dedupe hit, its id, pin and blob
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

    /// Choosing items copies them (together, if several are selected) to the clipboard and
    /// closes the panel — it does NOT synthesize a paste. The user pastes manually with ⌘V.
    func paste(_ items: [ClipboardItem]) {
        let wrote = Paster.writeToPasteboard(items, imagesDir: imagesDir)
        panel.hide()
        panel.restorePreviousApp()
        if wrote {
            onCopied?()
        } else {
            NSLog("Momo: nothing to copy for \(items.count) item(s) (missing blob or empty payload)")
        }
    }

    func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.monitor.poll(now: Date()) }
        timer.resume()
        pollTimer = timer
    }
}
