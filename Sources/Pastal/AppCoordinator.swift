import AppKit
import PastalCore

final class AppCoordinator {
    let store: Store
    let index = HistoryIndex()
    let monitor: ClipboardMonitor
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "pastal.poll", qos: .utility)

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pastal")
        let dbPath = appSupport.appendingPathComponent("history.sqlite").path
        let imagesDir = appSupport.appendingPathComponent("images").path
        store = try Store(path: dbPath, imagesDirectory: imagesDir)
        let reader = NSPasteboardReader()
        monitor = ClipboardMonitor(pasteboard: reader, writeImageBlob: { [store] data in
            try store.writeImageBlob(data)
        })

        index.replaceAll((try? store.recent(limit: 1000)) ?? [])
        monitor.onNewItem = { [weak self] item in
            guard let self else { return }
            try? self.store.upsert(item)
            DispatchQueue.main.async { self.index.prepend(item) }
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
