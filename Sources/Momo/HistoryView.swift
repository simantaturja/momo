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

final class HistoryView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    private let index: HistoryIndex
    private let imagesDir: String
    private let onChoose: ([ClipboardItem]) -> Void
    private let onPinToggle: ([ClipboardItem]) -> Void
    private let onDelete: ([ClipboardItem]) -> Void
    private let onCancel: () -> Void

    private let searchField = FocusRingSearchField()
    private let capsule = SearchCapsule()
    private let tableView = NSTableView()
    private let preview = PreviewPaneView()
    private let emptyEmoji = NSTextField(labelWithString: "🥟")
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptySubtitle = NSTextField(labelWithString: "")
    private let emptyStack = NSStackView()
    private var results: [HistoryRow] = []
    private var scope: HistoryScope = .all
    private var scopeButtons: [NSButton] = []
    private let countLabel = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "↵ Copy   ⌘1–9 Quick copy   ○ or ⇧↑↓ Select more   ⌘P Pin   ⌘⌫ Delete")
    private let actionBar = NSStackView()
    private let copyButton = NSButton()
    // Holding ⌘ alone swaps the first nine rows' times for their ⌘1…⌘9 quick keys.
    private var quickKeys = false
    private var flagsMonitor: Any?
    // Keyboard range selection: ⇧↑/⇧↓ moves `cursorRow` and selects everything back to `anchorRow`.
    private var anchorRow = 0
    private var cursorRow = 0

    /// Scope chips in display (and ⇥) order. The Files chip stands for every `.files(extension:)`.
    private static let chips: [(title: String, scope: HistoryScope)] = [
        ("All", .all), ("Text", .text), ("Links", .links),
        ("Images", .images), ("Files", .files(extension: nil)), ("Pinned", .pinned),
    ]

    init(index: HistoryIndex, imagesDir: String,
         onChoose: @escaping ([ClipboardItem]) -> Void,
         onPinToggle: @escaping ([ClipboardItem]) -> Void,
         onDelete: @escaping ([ClipboardItem]) -> Void,
         onCancel: @escaping () -> Void) {
        self.index = index; self.imagesDir = imagesDir
        self.onChoose = onChoose; self.onPinToggle = onPinToggle
        self.onDelete = onDelete; self.onCancel = onCancel
        super.init(frame: .zero)
        buildUI()
        reload()
        // HistoryView lives as long as the app (the panel is never torn down), so this
        // monitor is never removed.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            let flags = event.modifierFlags
            let commandAlone = flags.contains(.command) && flags.isDisjoint(with: [.shift, .option, .control])
            // Only pressing ⌘ itself (left 55 / right 54) shows them, so letting go of ⇧ after the
            // ⌘⇧V hotkey doesn't flash them; any other modifier change can only hide them.
            let isCommandKey = event.keyCode == 54 || event.keyCode == 55
            self.setQuickKeys(commandAlone && (isCommandKey || self.quickKeys))
            return event
        }
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
            searchField.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])

        let col = NSTableColumn(identifier: .init("main"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.rowHeight = 38
        tableView.style = .plain
        // No gap between rows: the pill inset already spaces them, and nine 38pt rows then fit
        // the ~344pt list so every ⌘1–⌘9 row is visible.
        tableView.intercellSpacing = NSSize(width: tableView.intercellSpacing.width, height: 0)
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(chooseSelected)
        let contextMenu = NSMenu()
        contextMenu.delegate = self   // filled per click in menuNeedsUpdate
        tableView.menu = contextMenu

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let scopeBar = buildScopeBar()
        let topSeparator = NSBox()
        topSeparator.boxType = .separator
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox()   // vertical, between the list and the preview
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        preview.translatesAutoresizingMaskIntoConstraints = false

        buildEmptyState()
        let footer = buildFooter()

        for view in [capsule, scopeBar, topSeparator, scroll, divider, preview, emptyStack, footer] as [NSView] {
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            capsule.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            capsule.heightAnchor.constraint(equalToConstant: 40),

            scopeBar.topAnchor.constraint(equalTo: capsule.bottomAnchor, constant: 8),
            scopeBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scopeBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            // A fixed height, so the list (not the bar) takes the spare space. With the 6pt gap
            // below, the list gets 343pt: all nine ⌘1–⌘9 rows (9 × 38pt).
            scopeBar.heightAnchor.constraint(equalToConstant: 22),

            topSeparator.topAnchor.constraint(equalTo: scopeBar.bottomAnchor, constant: 6),
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.widthAnchor.constraint(equalToConstant: 330),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),

            divider.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: scroll.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.bottomAnchor.constraint(equalTo: footer.topAnchor),

            preview.topAnchor.constraint(equalTo: topSeparator.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: footer.topAnchor),

            emptyStack.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.leadingAnchor, constant: 24),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor, constant: -24),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    /// The scope chips plus a dim "⇥ next scope" hint at the right end.
    private func buildScopeBar() -> NSView {
        for (i, chip) in Self.chips.enumerated() {
            let button = NSButton(title: chip.title, target: self, action: #selector(scopeClicked(_:)))
            button.bezelStyle = .recessed
            button.setButtonType(.pushOnPushOff)
            button.showsBorderOnlyWhileMouseInside = true
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.refusesFirstResponder = true
            button.tag = i
            scopeButtons.append(button)
        }
        let chipStack = NSStackView(views: scopeButtons)
        chipStack.spacing = 2
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        let scopeHint = NSTextField(labelWithString: "⇥ next scope")
        scopeHint.font = .systemFont(ofSize: 11)
        scopeHint.textColor = Theme.dimText
        scopeHint.lineBreakMode = .byTruncatingTail
        scopeHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scopeHint.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(chipStack); bar.addSubview(scopeHint)
        NSLayoutConstraint.activate([
            chipStack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            chipStack.topAnchor.constraint(equalTo: bar.topAnchor),
            chipStack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            scopeHint.leadingAnchor.constraint(greaterThanOrEqualTo: chipStack.trailingAnchor, constant: 8),
            scopeHint.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            scopeHint.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        updateScopeChips()
        return bar
    }

    private func buildEmptyState() {
        emptyEmoji.font = .systemFont(ofSize: 44)
        emptyEmoji.alignment = .center
        emptyTitle.font = .systemFont(ofSize: 15, weight: .medium)
        emptyTitle.textColor = .secondaryLabelColor
        emptyTitle.alignment = .center
        emptyTitle.lineBreakMode = .byTruncatingTail   // a long query must fit the 330pt list
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
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = Theme.dimText
        hint.alignment = .right
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hint.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        // Shown instead of the hint while ≥2 rows are selected.
        let clearButton = NSButton()
        styleFooterButton(clearButton, title: "Clear", color: .secondaryLabelColor, action: #selector(clearSelection))
        styleFooterButton(copyButton, title: "Copy", color: Theme.accent, action: #selector(chooseSelected))
        actionBar.setViews([clearButton, copyButton], in: .trailing)
        actionBar.spacing = 12
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBar.isHidden = true

        footer.addSubview(separator); footer.addSubview(countLabel); footer.addSubview(hint); footer.addSubview(actionBar)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            countLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            countLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 12),
            hint.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            hint.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            actionBar.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 8),
            actionBar.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            actionBar.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        return footer
    }

    private func styleFooterButton(_ button: NSButton, title: String, color: NSColor, action: Selector) {
        button.isBordered = false
        button.attributedTitle = footerTitle(title, color: color)
        button.target = self
        button.action = action
    }

    private func footerTitle(_ title: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: color,
        ])
    }

    /// Called by `PanelController.show()`. Everything else was reset on hide (`resetForNextOpen`).
    func prepareForShow() {
        window?.makeFirstResponder(searchField)
    }

    /// Called by `PanelController.hide()`: the next open starts on All with no query and no quick
    /// keys, on the newest copy scrolled to the top. Done on hide so opening is a pure reveal.
    func resetForNextOpen() {
        setQuickKeys(false)
        searchField.stringValue = ""
        if scope != .all { scope = .all; updateScopeChips() }
        reload()   // the panel is hidden, so this lands on the newest row and builds its preview
        selectNewest()
    }

    // MARK: Scopes

    @objc private func scopeClicked(_ sender: NSButton) {
        let chosen = Self.chips[sender.tag].scope
        if case .files = chosen, case .files = scope, !index.distinctFileExtensions().isEmpty {
            showFileExtensionMenu(from: sender)
        } else if chosen != scope {
            setScope(chosen)
        }
        updateScopeChips()   // the click toggled the push-on-push-off chip itself; re-sync
        focusSearchKeepingText()
    }

    private func showFileExtensionMenu(from sender: NSButton) {
        let menu = NSMenu()
        let anyFile = NSMenuItem(title: "All Files", action: #selector(selectFileExtension(_:)), keyEquivalent: "")
        anyFile.target = self
        anyFile.state = scope == .files(extension: nil) ? .on : .off
        menu.addItem(anyFile)
        menu.addItem(.separator())
        for ext in index.distinctFileExtensions() {
            let extItem = NSMenuItem(title: ".\(ext)", action: #selector(selectFileExtension(_:)), keyEquivalent: "")
            extItem.target = self
            extItem.representedObject = ext
            extItem.state = scope == .files(extension: ext) ? .on : .off
            menu.addItem(extItem)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func selectFileExtension(_ sender: NSMenuItem) {
        setScope(.files(extension: sender.representedObject as? String))
    }

    private func setScope(_ newScope: HistoryScope) {
        scope = newScope
        updateScopeChips()
        reload()
    }

    /// Exactly the active chip is on; the Files chip names a chosen extension.
    private func updateScopeChips() {
        let active = Self.chipIndex(of: scope)
        for (i, button) in scopeButtons.enumerated() {
            button.state = i == active ? .on : .off
            button.title = Self.chips[i].title
        }
        if case .files(let ext?) = scope { scopeButtons[active].title = "Files: .\(ext)" }
    }

    /// ⇥ / ⇧⇥ step through the chips, wrapping around.
    private func cycleScope(_ step: Int) {
        let n = Self.chips.count
        setScope(Self.chips[(Self.chipIndex(of: scope) + step + n) % n].scope)
    }

    /// The chip a scope belongs to; every file extension belongs to Files.
    private static func chipIndex(of scope: HistoryScope) -> Int {
        var chipScope = scope
        if case .files = scope { chipScope = .files(extension: nil) }
        return chips.firstIndex { $0.scope == chipScope } ?? 0
    }

    // MARK: Selection

    /// The newest copy, scrolled to the top: where every open starts.
    private func selectNewest() {
        guard !results.isEmpty else { return }
        tableView.selectRowIndexes([0], byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
        anchorRow = 0; cursorRow = 0
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        if flags.contains(.command) {
            let items = selectedItems()
            if event.charactersIgnoringModifiers == "p", !items.isEmpty {
                onPinToggle(items); return true
            }
            if event.keyCode == 51, !items.isEmpty {   // ⌘⌫ deletes the selected items
                onDelete(items); return true
            }
            // ⌘1…⌘9 (⌘ alone) copies that row straight away.
            if flags.isDisjoint(with: [.shift, .option, .control]),
               let n = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
               (1...9).contains(n), n <= results.count {
                onChoose([results[n - 1].item]); return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func setQuickKeys(_ on: Bool) {
        guard on != quickKeys else { return }
        quickKeys = on
        tableView.enumerateAvailableRowViews { rowView, _ in
            (rowView.view(atColumn: 0) as? HistoryRowView)?.setQuickKey(on)
        }
    }

    /// Selected rows in display order (top to bottom) — also the order they're copied in.
    private func selectedRows() -> [HistoryRow] {
        tableView.selectedRowIndexes.filter { $0 < results.count }.map { results[$0] }
    }

    private func selectedItems() -> [ClipboardItem] {
        selectedRows().map(\.item)
    }

    /// Re-run the query and refresh the table. `preserveSelection` keeps the currently
    /// selected items selected across data-driven refreshes (a background capture must not
    /// yank the user's selection back to the top) and, if none survive (e.g. they were just
    /// deleted), stays where the selection started; search-driven reloads pass false so the
    /// best match is highlighted. While the panel is hidden nothing is preserved: the next open
    /// lands on the newest copy anyway, and selecting it now builds its preview off the open path.
    func reload(preserveSelection: Bool = false) {
        let start = DispatchTime.now()
        let preserve = preserveSelection && window?.isVisible == true
        let keep = preserve ? Set(selectedItems().map(\.id)) : []
        let place = tableView.selectedRowIndexes.first
        results = index.search(searchField.stringValue, scope: scope)
        tableView.reloadData()
        let kept = IndexSet(results.indices.filter { keep.contains(results[$0].item.id) })
        if let first = kept.first, let last = kept.last {
            tableView.selectRowIndexes(kept, byExtendingSelection: false)
            anchorRow = first; cursorRow = last
        } else if !results.isEmpty {
            let row = preserve ? min(place ?? 0, results.count - 1) : 0
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            anchorRow = row; cursorRow = row
        }
        updateEmptyState()
        // The selected indexes can stay the same while the items under them change, so
        // selectionDidChange alone would leave a stale preview.
        refreshDetail()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        if ms > 16 { NSLog("Momo search+render slow: \(ms) ms for \(results.count)") }
    }

    private func updateEmptyState() {
        guard results.isEmpty else { emptyStack.isHidden = true; return }
        let query = searchField.stringValue
        if !query.isEmpty {
            emptyEmoji.isHidden = true
            emptySubtitle.isHidden = true
            emptyTitle.stringValue = "No matches for \"\(query)\""
        } else if scope == .all {
            emptyEmoji.isHidden = false
            emptySubtitle.isHidden = false
            emptyTitle.stringValue = "Nothing copied yet"
            emptySubtitle.stringValue = "Copy anything — it'll show up here."
        } else {
            emptyEmoji.isHidden = false
            emptySubtitle.isHidden = true
            emptyTitle.stringValue = "No \(Self.chips[Self.chipIndex(of: scope)].title.lowercased()) yet"
        }
        emptyStack.isHidden = false
    }

    /// Preview pane + footer count for the current selection.
    private func refreshDetail() {
        let rows = selectedRows()
        preview.show(rows, imagesDir: imagesDir)
        let n = results.count
        // While several rows are selected, Clear / Copy N replace the key hints.
        let multi = rows.count > 1
        hint.isHidden = multi
        actionBar.isHidden = !multi
        if multi {
            countLabel.stringValue = "\(rows.count) selected"
            countLabel.textColor = Theme.accent
            copyButton.attributedTitle = footerTitle("Copy \(rows.count)", color: Theme.accent)
        } else {
            countLabel.stringValue = searchField.stringValue.isEmpty
                ? (n == 1 ? "1 item" : "\(n) items")
                : (n == 1 ? "1 match" : "\(n) matches")
            countLabel.textColor = Theme.dimText
        }
    }

    // Search typing
    func controlTextDidChange(_ obj: Notification) { reload() }

    // Enter / arrows / tab / esc from the search field
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): chooseSelected(); return true
        case #selector(NSResponder.moveDown(_:)): moveSelection(+1); return true
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1); return true
        case #selector(NSResponder.moveDownAndModifySelection(_:)): moveSelection(+1, extending: true); return true
        case #selector(NSResponder.moveUpAndModifySelection(_:)): moveSelection(-1, extending: true); return true
        case #selector(NSResponder.insertTab(_:)): cycleScope(+1); return true
        case #selector(NSResponder.insertBacktab(_:)): cycleScope(-1); return true
        case #selector(NSResponder.cancelOperation(_:)): clearSearchOrCancel(); return true
        default: return false
        }
    }

    /// Esc clears a non-empty search first; on an empty one it closes the panel.
    private func clearSearchOrCancel() {
        if searchField.stringValue.isEmpty { onCancel() } else { clearSearch() }
    }

    /// ↑/↓ collapse to a single row; ⇧↑/⇧↓ (`extending`) grow or shrink a range from the anchor.
    private func moveSelection(_ delta: Int, extending: Bool = false) {
        guard !results.isEmpty else { return }
        cursorRow = min(max(0, cursorRow + delta), results.count - 1)
        if !extending { anchorRow = cursorRow }
        let range = IndexSet(integersIn: min(anchorRow, cursorRow)...max(anchorRow, cursorRow))
        tableView.selectRowIndexes(range, byExtendingSelection: false)
        tableView.scrollRowToVisible(cursorRow)
    }

    /// Footer "Clear": collapse a multi-selection to the cursor row, or the first selected row if the cursor isn't selected.
    @objc private func clearSelection() {
        let sel = tableView.selectedRowIndexes
        let row = sel.contains(cursorRow) ? cursorRow : (sel.first ?? cursorRow)
        guard row < results.count else { return }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        anchorRow = row; cursorRow = row
        focusSearchKeepingText()
    }

    /// Checkbox click: toggle that row like ⌘-click, but never leave zero rows selected.
    private func toggleRow(of cell: HistoryRowView) {
        let row = tableView.row(for: cell)
        guard row >= 0 else { return }
        var rows = tableView.selectedRowIndexes
        if rows.contains(row) {
            guard rows.count > 1 else { return }
            rows.remove(row)
        } else {
            rows.insert(row)
        }
        tableView.selectRowIndexes(rows, byExtendingSelection: false)
        anchorRow = row; cursorRow = row
        focusSearchKeepingText()
    }

    /// Re-focusing an already-editing field would select all its text, so the next keystroke replaces the query.
    private func focusSearchKeepingText() {
        if searchField.currentEditor() == nil { window?.makeFirstResponder(searchField) }
    }

    /// Esc's first press: empties a non-empty query and lists by recency again.
    private func clearSearch() {
        guard !searchField.stringValue.isEmpty else { return }
        searchField.stringValue = ""
        reload()
    }

    /// Hover never survives a hide: the ordered-out panel gets no mouseExited.
    func clearHover() {
        tableView.enumerateAvailableRowViews { rowView, _ in (rowView as? PillRowView)?.clearHover() }
    }

    @objc private func chooseSelected() {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        onChoose(items)
    }

    /// A single click selects the row but makes the table the first responder, which
    /// would strand ↵/Esc/↑↓ (they route through the search field's delegate). Hand
    /// first responder back to the search field so keys keep working; selection stays.
    /// ⌘-click / ⇧-click multi-select natively; sync the keyboard range ends to the click.
    @objc private func rowClicked() {
        let row = tableView.clickedRow
        if row >= 0 {
            cursorRow = row
            if NSApp.currentEvent?.modifierFlags.contains(.shift) != true { anchorRow = row }
        }
        window?.makeFirstResponder(searchField)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshDetail()
        let multi = tableView.numberOfSelectedRows > 1
        tableView.enumerateAvailableRowViews { rowView, _ in
            (rowView.view(atColumn: 0) as? HistoryRowView)?.setMultiSelect(multi)
        }
    }

    // MARK: Right-click menu

    /// Rebuilt for the clicked row each time it opens. Right-clicking outside the selection
    /// selects just that row first, so the actions always apply to what's highlighted.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clicked = tableView.clickedRow
        guard clicked >= 0, clicked < results.count else { return }
        if !tableView.selectedRowIndexes.contains(clicked) {
            tableView.selectRowIndexes([clicked], byExtendingSelection: false)
            anchorRow = clicked; cursorRow = clicked
        }
        let rows = selectedRows()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add(rows.count == 1 ? "Copy" : "Copy \(rows.count) Items", #selector(chooseSelected))
        add(rows.allSatisfy(\.item.pinned) ? "Unpin" : "Pin", #selector(pinSelected))
        if rows.count == 1, rows[0].flavor == .link { add("Open Link", #selector(openSelectedLink)) }
        if rows.count == 1, rows[0].item.kind == .file { add("Reveal in Finder", #selector(revealSelectedFiles)) }
        menu.addItem(.separator())
        add("Delete", #selector(deleteSelected))
    }

    @objc private func pinSelected() {
        let items = selectedItems()
        if !items.isEmpty { onPinToggle(items) }
    }

    @objc private func deleteSelected() {
        let items = selectedItems()
        if !items.isEmpty { onDelete(items) }
    }

    @objc private func openSelectedLink() {
        guard let item = selectedItems().first,
              let url = URL(string: (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealSelectedFiles() {
        guard let item = selectedItems().first else { return }
        NSWorkspace.shared.activateFileViewerSelecting(item.filePaths.map { URL(fileURLWithPath: $0) })
    }

    // DataSource / Delegate
    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryRowView) ?? {
            let v = HistoryRowView(); v.identifier = id
            v.onCheckboxClick = { [weak self] cell in self?.toggleRow(of: cell) }
            return v
        }()
        cell.configure(results[row], index: row, imagesDir: imagesDir, showQuickKey: quickKeys)
        cell.setMultiSelect(tableView.numberOfSelectedRows > 1)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("pill")
        return (tableView.makeView(withIdentifier: id, owner: self) as? PillRowView) ?? {
            let v = PillRowView(); v.identifier = id; return v
        }()
    }
}
