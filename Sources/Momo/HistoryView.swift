import AppKit
import MomoCore

final class HistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let index: HistoryIndex
    private let imagesDir: String
    private let onChoose: (ClipboardItem) -> Void
    private let onPinToggle: (ClipboardItem) -> Void
    private let onCancel: () -> Void

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var results: [ClipboardItem] = []

    init(index: HistoryIndex, imagesDir: String,
         onChoose: @escaping (ClipboardItem) -> Void,
         onPinToggle: @escaping (ClipboardItem) -> Void,
         onCancel: @escaping () -> Void) {
        self.index = index; self.imagesDir = imagesDir
        self.onChoose = onChoose; self.onPinToggle = onPinToggle
        self.onCancel = onCancel
        super.init(frame: .zero)
        buildUI()
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(chooseSelected)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField); addSubview(scroll)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func focusSearch() { window?.makeFirstResponder(searchField) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "p" {
            let row = tableView.selectedRow
            if row >= 0, row < results.count {
                onPinToggle(results[row])
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    func reload() {
        let start = DispatchTime.now()
        results = index.search(searchField.stringValue)
        tableView.reloadData()
        if !results.isEmpty { tableView.selectRowIndexes([0], byExtendingSelection: false) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        if ms > 16 { NSLog("Momo search+render slow: \(ms) ms for \(results.count)") }
    }

    // Search typing
    func controlTextDidChange(_ obj: Notification) { reload() }

    // Enter / arrows from the search field
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): chooseSelected(); return true
        case #selector(NSResponder.moveDown(_:)): moveSelection(+1); return true
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
        case #selector(NSResponder.cancelOperation(_:)): onCancel(); return true
        default: return false
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let next = min(max(0, tableView.selectedRow + delta), results.count - 1)
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func chooseSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        onChoose(results[row])
    }

    // DataSource / Delegate
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryRowView) ?? {
            let v = HistoryRowView(); v.identifier = id; return v
        }()
        cell.configure(results[row], imagesDir: imagesDir)
        return cell
    }
}
