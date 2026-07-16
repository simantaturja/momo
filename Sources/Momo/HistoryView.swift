import AppKit
import MomoCore

/// A search field that reports focus changes so its capsule can draw an accent ring.
private final class FocusRingSearchField: NSSearchField {
    var onFocusChange: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocusChange?(true) }
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onFocusChange?(false) }
        return ok
    }
}

/// Rounded filled capsule that hosts the search field; draws a 1.5pt accent ring when focused.
/// Drawing (not layer CGColors) so the neutral fill and accent ring track light/dark natively.
private final class SearchCapsule: NSView {
    var focused = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill(with: Theme.searchFill)
        guard focused else { return }
        let ringRect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let ring = NSBezierPath(roundedRect: ringRect, xRadius: ringRect.height / 2, yRadius: ringRect.height / 2)
        ring.lineWidth = 1.5
        Theme.accent.setStroke()
        ring.stroke()
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor) { color.setFill(); fill() }
}

final class HistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let index: HistoryIndex
    private let imagesDir: String
    private let onChoose: (ClipboardItem) -> Void
    private let onPinToggle: (ClipboardItem) -> Void
    private let onDelete: (ClipboardItem) -> Void
    private let onCancel: () -> Void

    private let searchField = FocusRingSearchField()
    private let capsule = SearchCapsule()
    private let tableView = NSTableView()
    private let emptyEmoji = NSTextField(labelWithString: "🥟")
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptySubtitle = NSTextField(labelWithString: "")
    private let emptyStack = NSStackView()
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
        // Search capsule: leading magnifier + borderless field. Keep the free clear button.
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.isBezeled = false
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 15)
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil   // we draw our own magnifier
        searchField.onFocusChange = { [weak self] focused in self?.capsule.focused = focused }

        let magnifier = NSImageView()
        magnifier.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        magnifier.contentTintColor = Theme.badgeSymbol
        magnifier.translatesAutoresizingMaskIntoConstraints = false

        capsule.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(magnifier); capsule.addSubview(searchField)
        NSLayoutConstraint.activate([
            magnifier.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 14),
            magnifier.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
            magnifier.widthAnchor.constraint(equalToConstant: 16),
            magnifier.heightAnchor.constraint(equalToConstant: 16),
            searchField.leadingAnchor.constraint(equalTo: magnifier.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])

        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 44
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(chooseSelected)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        buildEmptyState()
        let footer = buildFooter()

        addSubview(capsule); addSubview(scroll); addSubview(emptyStack); addSubview(footer)
        NSLayoutConstraint.activate([
            capsule.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            capsule.heightAnchor.constraint(equalToConstant: 40),

            scroll.topAnchor.constraint(equalTo: capsule.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),

            emptyStack.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func buildEmptyState() {
        emptyEmoji.font = .systemFont(ofSize: 44)
        emptyEmoji.alignment = .center
        emptyTitle.font = .systemFont(ofSize: 15, weight: .medium)
        emptyTitle.textColor = .secondaryLabelColor
        emptyTitle.alignment = .center
        emptySubtitle.font = .systemFont(ofSize: 13)
        emptySubtitle.textColor = Theme.dimText
        emptySubtitle.alignment = .center
        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 8
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyStack.addArrangedSubview(emptyEmoji)
        emptyStack.addArrangedSubview(emptyTitle)
        emptyStack.addArrangedSubview(emptySubtitle)
        emptyStack.isHidden = true
    }

    private func buildFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        let hint = NSTextField(labelWithString: "↑↓ move · ↵ copy · ⌘P pin · ⌘⌫ delete")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = Theme.dimText
        hint.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(separator); footer.addSubview(hint)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            hint.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            hint.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        return footer
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
        updateEmptyState()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        if ms > 16 { NSLog("Momo search+render slow: \(ms) ms for \(results.count)") }
    }

    private func updateEmptyState() {
        guard results.isEmpty else { emptyStack.isHidden = true; return }
        let query = searchField.stringValue
        if query.isEmpty {
            emptyEmoji.isHidden = false
            emptySubtitle.isHidden = false
            emptyTitle.stringValue = "Nothing copied yet"
            emptySubtitle.stringValue = "Copy anything — it'll show up here."
        } else {
            emptyEmoji.isHidden = true
            emptySubtitle.isHidden = true
            emptyTitle.stringValue = "No matches for \"\(query)\""
        }
        emptyStack.isHidden = false
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

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("pill")
        return (tableView.makeView(withIdentifier: id, owner: self) as? PillRowView) ?? {
            let v = PillRowView(); v.identifier = id; return v
        }()
    }
}
