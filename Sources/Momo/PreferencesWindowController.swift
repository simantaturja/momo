import AppKit
import MomoCore
import UniformTypeIdentifiers

/// The Settings window: one tab per pane, built in code. Every control reads and writes
/// `Settings` directly; `Settings.didChange` brings the app (and the open panes) up to date.
final class PreferencesWindowController: NSWindowController {
    private static var shared: PreferencesWindowController?

    /// Momo is an accessory app, so it has to bring itself forward for the window to take focus.
    static func show(coordinator: AppCoordinator) {
        let controller = shared ?? PreferencesWindowController(coordinator: coordinator)
        shared = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(coordinator: AppCoordinator) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        let panes: [(NSViewController, String, String)] = [
            (GeneralPane(), "General", "gearshape"),
            (StoragePane(), "Storage", "internaldrive"),
            (AppearancePane(), "Appearance", "paintpalette"),
            (PinsPane(coordinator: coordinator), "Pins", "pin"),
            (IgnorePane(), "Ignore", "nosign"),
            (AdvancedPane(), "Advanced", "gearshape.2"),
        ]
        for (pane, label, symbol) in panes {
            let item = NSTabViewItem(viewController: pane)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }
        let window = SettingsWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setContentSize(Pane.size)
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Momo has no main menu (it's a menu-bar accessory), so the standard editing keys that menu
/// would provide are mapped here, for the editable lists.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let actions: [String: Selector] = [
            "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
            "a": #selector(NSText.selectAll(_:)), "w": #selector(NSWindow.performClose(_:)),
        ]
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let action = event.charactersIgnoringModifiers.flatMap({ actions[$0] }),
           NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Runs a closure as a control's target-action.
private final class Action: NSObject {
    let run: (NSControl) -> Void
    init(_ run: @escaping (NSControl) -> Void) { self.run = run }
    @objc func fire(_ sender: NSControl) { run(sender) }
}

/// A pane: a fixed-size view with its content pinned to the top. Controls made with the helpers
/// below re-read their setting whenever the pane appears or a setting changes.
private class Pane: NSViewController {
    static let size = NSSize(width: 560, height: 400)
    private var actions: [Action] = []
    private var refreshers: [() -> Void] = []
    private var observer: NSObjectProtocol?

    /// The pane's content; subclasses build it.
    func makeContent() -> NSView { NSView() }
    /// Whether the content stretches to the bottom (lists) or sits at the top (forms).
    var fillsHeight: Bool { false }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.size))
        let content = makeContent()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        let bottom = fillsHeight
            ? content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
            : content.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            bottom,
        ])
        view = root
        preferredContentSize = Self.size
        observer = NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) {
            [weak self] _ in self?.refresh()
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    func refresh() { refreshers.forEach { $0() } }

    func onRefresh(_ refresher: @escaping () -> Void) { refreshers.append(refresher) }

    @discardableResult
    func bind<C: NSControl>(_ control: C, _ run: @escaping (C) -> Void) -> C {
        let action = Action { run($0 as! C) }
        actions.append(action)
        control.target = action
        control.action = #selector(Action.fire(_:))
        return control
    }

    func checkbox(_ title: String, get read: @escaping () -> Bool, set write: @escaping (Bool) -> Void) -> NSButton {
        let box = bind(NSButton(checkboxWithTitle: title, target: nil, action: nil)) { write($0.state == .on) }
        onRefresh { box.state = read() ? .on : .off }
        return box
    }

    func popup<T: Equatable>(_ options: [(String, T)], get read: @escaping () -> T,
                             set write: @escaping (T) -> Void) -> NSPopUpButton {
        let popup = bind(NSPopUpButton()) { write(options[max(0, $0.indexOfSelectedItem)].1) }
        popup.addItems(withTitles: options.map { $0.0 })
        onRefresh { popup.selectItem(at: options.firstIndex { $0.1 == read() } ?? 0) }
        return popup
    }

    /// Labels on the left, controls on the right.
    func form(_ rows: [(String, NSView)]) -> NSGridView {
        var views: [[NSView]] = []
        for (title, view) in rows {
            let label: NSView = title.isEmpty ? NSGridCell.emptyContentView : NSTextField(labelWithString: title)
            views.append([label, view])
        }
        let grid = NSGridView(views: views)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 8
        grid.rowSpacing = 14
        return grid
    }

    func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 380
        return label
    }

    func column(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    /// A bordered, scrolling list that takes the pane's spare height.
    func listColumn(_ table: NSTableView, _ views: [NSView]) -> NSStackView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.init(1), for: .vertical)
        let stack = column(views.map { $0 === table ? scroll as NSView : $0 }, spacing: 8)
        stack.distribution = .fill
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }
}

// MARK: General

private final class GeneralPane: Pane {
    override func makeContent() -> NSView {
        let passwords = checkbox("Save passwords copied from password managers",
                                 get: { Settings.savePasswords }, set: { Settings.savePasswords = $0 })
        return form([
            ("Startup:", checkbox("Launch Momo at login",
                                  get: { Settings.launchAtLogin }, set: { Settings.launchAtLogin = $0 })),
            ("Privacy:", column([passwords, caption("Passwords are stored unencrypted on this Mac. Applies from the next copy.")])),
            ("Shortcut:", NSTextField(labelWithString: "⌘⇧V opens your history")),
        ])
    }
}

// MARK: Storage

private final class StoragePane: Pane {
    private let diskUsage = NSTextField(labelWithString: "")

    override func makeContent() -> NSView {
        let save = column([
            checkbox("Files", get: { Settings.saveFiles }, set: { Settings.saveFiles = $0 }),
            checkbox("Images", get: { Settings.saveImages }, set: { Settings.saveImages = $0 }),
            checkbox("Text", get: { Settings.saveText }, set: { Settings.saveText = $0 }),
            caption("Copies of an unchecked kind aren't saved."),
        ])

        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 10
        formatter.maximum = 100_000
        let field = NSTextField()
        field.formatter = formatter
        field.cell?.sendsActionOnEndEditing = true   // tabbing or clicking away commits too
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let stepper = NSStepper()
        stepper.minValue = 10
        stepper.maxValue = 100_000
        stepper.increment = 100
        bind(field) { Settings.maxItems = $0.integerValue }
        bind(stepper) { Settings.maxItems = $0.integerValue }
        onRefresh {
            field.integerValue = Settings.maxItems
            stepper.integerValue = Settings.maxItems
        }
        let items = NSStackView(views: [field, stepper, NSTextField(labelWithString: "items, not counting pins")])
        items.spacing = 6
        diskUsage.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        diskUsage.textColor = .secondaryLabelColor

        let sort = popup([("Time of last copy", HistorySort.lastCopy), ("Time of first copy", HistorySort.firstCopy),
                          ("Number of copies", HistorySort.copyCount)],
                         get: { Settings.sortBy }, set: { Settings.sortBy = $0 })
        return form([("Save:", save), ("Size:", column([items, diskUsage])), ("Sort by:", sort)])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let dir = AppCoordinator.appSupportDir()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let bytes = Self.size(of: dir)
            DispatchQueue.main.async {
                self?.diskUsage.stringValue = "Using \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) on disk"
            }
        }
    }

    /// The database and image blobs together.
    private static func size(of dir: URL) -> Int64 {
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let url = files?.nextObject() as? URL {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

// MARK: Appearance

private final class AppearancePane: Pane {
    override func makeContent() -> NSView {
        form([
            ("Popup at:", popup([("Menu bar icon", PopupPosition.menuIcon), ("Mouse pointer", PopupPosition.cursor),
                                 ("Center of the screen", PopupPosition.screenCenter)],
                                get: { Settings.popupAt }, set: { Settings.popupAt = $0 })),
            ("Pins at:", popup([("Top", PinPlacement.top), ("Bottom", PinPlacement.bottom)],
                               get: { Settings.pinsAt }, set: { Settings.pinsAt = $0 })),
            ("Highlight matches:", popup([("Color", MatchHighlight.accent), ("Bold", MatchHighlight.bold),
                                          ("Underline", MatchHighlight.underline)],
                                         get: { Settings.highlightMatches }, set: { Settings.highlightMatches = $0 })),
            ("", checkbox("Show the latest copy next to the menu bar icon",
                          get: { Settings.showRecentCopyInMenuBar }, set: { Settings.showRecentCopyInMenuBar = $0 })),
            ("", checkbox("Show the footer (key hints and actions)",
                          get: { Settings.showFooter }, set: { Settings.showFooter = $0 })),
        ])
    }
}

// MARK: Pins

/// A cell-based table: double-click edits a cell, and `setObjectValue` gets the result.
private final class PinsPane: Pane, NSTableViewDataSource, NSTableViewDelegate {
    private let coordinator: AppCoordinator
    private let table = NSTableView()
    private var pins: [ClipboardItem] = []
    private var historyObserver: NSObjectProtocol?
    private static let titleColumn = NSUserInterfaceItemIdentifier("title")

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var fillsHeight: Bool { true }

    override func makeContent() -> NSView {
        for (id, title, width) in [(Self.titleColumn, "Title", 160.0), (NSUserInterfaceItemIdentifier("content"), "Content", 320.0)] {
            let column = NSTableColumn(identifier: id)
            column.title = title
            column.width = width
            column.isEditable = true
            (column.dataCell as? NSTextFieldCell)?.lineBreakMode = .byTruncatingTail
            table.addTableColumn(column)
        }
        (table.tableColumns[0].dataCell as? NSTextFieldCell)?.placeholderString = "Untitled"
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        historyObserver = NotificationCenter.default.addObserver(forName: AppCoordinator.historyDidChange,
                                                                 object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
        return listColumn(table, [table, caption("Double-click a title or text to edit it. A title is shown and "
                                                 + "searched in place of the content. Only text content can be edited.")])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
    }

    private func reload() {
        guard table.editedRow < 0 else { return }   // a capture mid-edit mustn't cancel the edit
        pins = coordinator.index.search("", scope: .pinned).map(\.item)
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { pins.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let item = pins[row]
        return tableColumn?.identifier == Self.titleColumn ? (item.title ?? "") : (item.text ?? item.preview)
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        tableColumn?.identifier == Self.titleColumn || pins[row].kind == .text
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard row < pins.count, let value = object as? String else { return }
        let item = pins[row]
        if tableColumn?.identifier == Self.titleColumn {
            guard value != (item.title ?? "") else { return }
            coordinator.edit({ try $0.setTitle(id: item.id, title: value); return true }) { _ in }
        } else if value != item.text {
            coordinator.edit({ try $0.updateText(id: item.id, text: value) }) { ok in
                if !ok { NSSound.beep() }   // blank, or what another item already holds: left as it was
            }
        }
    }
}

// MARK: Ignore

private final class IgnorePane: Pane, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let kinds = NSSegmentedControl()
    private var onlyListed: NSButton!
    private var appsCaption: NSTextField!
    private var listCaption: NSTextField!

    override var fillsHeight: Bool { true }

    private var editingApps: Bool { kinds.selectedSegment == 0 }

    private var values: [String] {
        get {
            switch kinds.selectedSegment {
            case 0: return Settings.ignoredApps
            case 1: return Settings.ignoredPasteboardTypes
            default: return Settings.ignoredPatterns
            }
        }
        set {
            switch kinds.selectedSegment {
            case 0: Settings.ignoredApps = newValue
            case 1: Settings.ignoredPasteboardTypes = newValue
            default: Settings.ignoredPatterns = newValue
            }
        }
    }

    override func makeContent() -> NSView {
        kinds.segmentCount = 3
        for (i, label) in ["Applications", "Pasteboard Types", "Regular Expressions"].enumerated() {
            kinds.setLabel(label, forSegment: i)
        }
        kinds.selectedSegment = 0
        bind(kinds) { [weak self] _ in self?.refresh() }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        column.isEditable = true
        table.addTableColumn(column)
        table.headerView = nil
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self

        let buttons = NSSegmentedControl(images: [NSImage(named: NSImage.addTemplateName)!,
                                                  NSImage(named: NSImage.removeTemplateName)!],
                                         trackingMode: .momentary, target: nil, action: nil)
        bind(buttons) { [weak self] control in
            if control.selectedSegment == 0 { self?.add() } else { self?.removeSelected() }
        }

        onlyListed = checkbox("Ignore all applications except the listed ones",
                              get: { Settings.ignoreAllExceptListed }, set: { Settings.ignoreAllExceptListed = $0 })
        appsCaption = caption("The app a copy came from is the one in front when it's copied, so detection is best effort.")
        listCaption = caption("")
        onRefresh { [weak self] in self?.update() }

        return listColumn(table, [kinds, table, buttons, onlyListed, appsCaption, listCaption])
    }

    private func update() {
        onlyListed.isHidden = !editingApps
        appsCaption.isHidden = !editingApps
        listCaption.isHidden = editingApps
        listCaption.stringValue = kinds.selectedSegment == 1
            ? "Copies carrying any of these pasteboard types aren't saved."
            : "Text matching any of these regular expressions anywhere isn't saved. Invalid ones are skipped."
        table.reloadData()
    }

    private func add() {
        guard editingApps else {
            values.append("")
            let row = values.count - 1
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.editColumn(0, row: row, with: nil, select: true)
            return
        }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let current = values
        let added = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !current.contains($0) }
        values = current + Array(Set(added))
    }

    private func removeSelected() {
        let selected = table.selectedRowIndexes
        values = values.enumerated().filter { !selected.contains($0.offset) }.map { $0.element }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { values.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let value = values[row]
        guard editingApps else { return value }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value)
            .map { FileManager.default.displayName(atPath: $0.path) }
        return name.map { "\($0)  (\(value))" } ?? value
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        !editingApps
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let value = object as? String, row < values.count else { return }
        if value.trimmingCharacters(in: .whitespaces).isEmpty { values.remove(at: row) } else { values[row] = value }
    }
}

// MARK: Advanced

private final class AdvancedPane: Pane {
    override func makeContent() -> NSView {
        let pause = checkbox("Pause Momo", get: { Settings.ignoreEvents }, set: { Settings.ignoreEvents = $0 })
        let help = caption("""
            While paused, nothing you copy is saved. From Terminal:
              defaults write me.momo.app ignoreEvents true
              defaults write me.momo.app ignoreEvents false
              defaults write me.momo.app ignoreOnlyNextEvent true   (skip just the next copy)
            ⌥-click the menu bar icon to pause or resume; ⌥⇧-click to ignore only the next copy.
            """)
        help.preferredMaxLayoutWidth = 500
        let separator = NSBox()
        separator.boxType = .separator
        let clearHistory = checkbox("Clear history when Momo quits",
                                    get: { Settings.clearHistoryOnQuit }, set: { Settings.clearHistoryOnQuit = $0 })
        let clearClipboard = checkbox("Clear the system clipboard too",
                                      get: { Settings.clearSystemClipboardOnQuit },
                                      set: { Settings.clearSystemClipboardOnQuit = $0 })
        onRefresh { clearClipboard.isEnabled = Settings.clearHistoryOnQuit }
        let stack = column([pause, help, separator, clearHistory, caption("Pinned items are kept."), clearClipboard],
                           spacing: 8)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }
}
