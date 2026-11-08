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
    /// Posted on main after the index's items change.
    static let historyDidChange = Notification.Name("MomoHistoryDidChange")
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
        }, allowsConcealed: { Settings.savePasswords }, sourceApp: Self.frontmostApp,
           rules: { Settings.captureRules }, isPaused: { Settings.ignoreEvents },
           consumeIgnoreNext: Settings.consumeIgnoreNext)

        index.sort = Settings.sortBy
        index.pinPlacement = Settings.pinsAt
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
                NotificationCenter.default.post(name: Self.historyDidChange, object: nil)
            }
            self.pollQueue.async { self.runPrune() }
        }
        _ = NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        }

        // Reclaim any blobs left behind by a prior crash between blob-write and row-commit.
        let store = self.store
        pollQueue.async { _ = try? store.reapOrphanBlobs() }
    }

    /// The app in front when a copy is seen, i.e. the one it was copied from; nil when that's
    /// Momo itself. Called on the poll queue (NSRunningApplication's properties are atomic).
    private static func frontmostApp() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let name = app.localizedName else { return nil }
        return SourceApp(name: name, bundleID: app.bundleIdentifier)
    }

    func runPrune() {
        let deleted = (try? store.prune(maxItems: Settings.maxItems,
                                        maxImageBytes: Settings.maxImageBytes,
                                        imageMaxAge: Settings.imageMaxAge,
                                        now: Date())) ?? 0
        if deleted > 0 { reloadIndexFromStore() }   // skip the refetch/reload when nothing changed
    }

    /// Applies the settings the shell holds: list order, panel placement and look, and the item cap.
    /// Runs at launch and on every change; on main.
    func applySettings() {
        index.sort = Settings.sortBy
        index.pinPlacement = Settings.pinsAt
        panel.popupAt = Settings.popupAt
        historyView.highlight = Settings.highlightMatches
        historyView.showsFooter = Settings.showFooter
        historyView.reload(preserveSelection: true)
        pollQueue.async { self.runPrune() }   // maxItems may have dropped
    }

    func clearHistory() {
        pollQueue.async {
            try? self.store.deleteAll()
            self.reloadIndexFromStore()
        }
    }

    /// Clear-on-quit: runs before returning, since the app exits right after.
    func deleteUnpinnedNow() {
        pollQueue.sync { _ = try? store.deleteUnpinned() }
    }

    /// Runs a Store edit on the poll queue, reloads the index, then reports on main whether it took.
    func edit(_ change: @escaping (Store) throws -> Bool, done: @escaping (Bool) -> Void) {
        pollQueue.async {
            let ok = (try? change(self.store)) ?? false
            self.reloadIndexFromStore()
            DispatchQueue.main.async { done(ok) }
        }
    }

    /// The most recent copy, for the menu bar title.
    var latestCopy: HistoryRow? {
        index.search("").max { $0.item.createdAt < $1.item.createdAt }
    }

    private func reloadIndexFromStore() {
        let items = (try? store.recent(limit: Settings.maxItems)) ?? []
        DispatchQueue.main.async {
            self.index.replaceAll(items)
            self.historyView.reload(preserveSelection: true)
            NotificationCenter.default.post(name: Self.historyDidChange, object: nil)
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
