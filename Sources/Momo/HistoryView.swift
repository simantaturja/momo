import AppKit
import MomoCore

final class HistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let index: HistoryIndex
    private let imagesDir: String
    private let onChoose: (ClipboardItem) -> Void
    private let onPinToggle: (ClipboardItem) -> Void
    private let onDelete: (ClipboardItem) -> Void
    private let onCancel: () -> Void

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var results: [ClipboardItem] = []

    init(index: HistoryIndex, imagesDir: String,
         onChoose: @escaping (ClipboardItem) -> Void,
         onPinToggle: @escaping (ClipboardItem) -> Void,
         onDelete: @escaping (ClipboardItem) -> Void,
         onCancel: @escaping () -> Void) {
        self.index = index; self.imagesDir = imagesDir
        self.onChoose = onChoose; self.onPinToggle = onPinToggle
        self.onDelete = onDelete; self.onCancel = onCancel
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
        tableView.action = #selector(rowClicked)
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
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "p", let item = selectedItem() {
                onPinToggle(item); return true
            }
            if event.keyCode == 51, let item = selectedItem() {   // ⌘⌫ deletes the selected item
                onDelete(item); return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func selectedItem() -> ClipboardItem? {
        let row = tableView.selectedRow
        return (row >= 0 && row < results.count) ? results[row] : nil
    }

    /// Re-run the query and refresh the table. `preserveSelection` keeps the currently
    /// selected item selected across data-driven refreshes (a background capture must not
    /// yank the user's selection back to the top); search-driven reloads pass false so the
    /// best match is highlighted.
    func reload(preserveSelection: Bool = false) {
        let start = DispatchTime.now()
        let keep = preserveSelection ? selectedItem()?.id : nil
        results = index.search(searchField.stringValue)
        tableView.reloadData()
        if let keep, let idx = results.firstIndex(where: { $0.id == keep }) {
            tableView.selectRowIndexes([idx], byExtendingSelection: false)
        } else if !results.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
        }
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
        guard let item = selectedItem() else { return }
        onChoose(item)
    }

    /// A single click selects the row but makes the table the first responder, which
    /// would strand ↵/Esc/↑↓ (they route through the search field's delegate). Hand
    /// first responder back to the search field so keys keep working; selection stays.
    @objc private func rowClicked() {
        window?.makeFirstResponder(searchField)
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
