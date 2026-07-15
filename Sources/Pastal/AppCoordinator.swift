import AppKit
import PastalCore

final class AppCoordinator {
    let store: Store
    let index = HistoryIndex()
    let monitor: ClipboardMonitor
    let imagesDir: String
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "pastal.poll", qos: .utility)

    lazy var historyView = HistoryView(
        index: index,
        imagesDir: imagesDir,
        onChoose: { [weak self] item in self?.paste(item) },   // paste() added in Task 11
        onPinToggle: { [weak self] item in try? self?.store.setPinned(id: item.id, pinned: !item.pinned) }
    )
    lazy var panel = PanelController(contentView: historyView)

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pastal")
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
    }

    func paste(_ item: ClipboardItem) {
        Paster.writeToPasteboard(item, imagesDir: imagesDir)
        panel.hide()
        panel.restorePreviousApp()
        // Give focus a beat to return, then synth Cmd+V.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
            Paster.synthesizePaste()
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
