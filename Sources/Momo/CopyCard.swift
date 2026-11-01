import AppKit
import MomoCore

/// The hover card: when the pointer rests on a row, a small floating card near it shows the
/// item's content and copy history (`CopyDetails`). One card for the whole list; display only.
/// It never takes focus or mouse events, so it can't dismiss the panel or steal its hover.
final class CopyCard {
    static let shared = CopyCard()

    private let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: true)
    private let stack = NSStackView()
    private let contentLabel = NSTextField(wrappingLabelWithString: "")
    private let appRow = NSStackView()
    private let appIcon = NSImageView()
    private let appName = NSTextField(labelWithString: "")
    private let factsLabel = NSTextField(wrappingLabelWithString: "")
    private weak var row: HistoryRowView?
    private var timer: Timer?
    private var eventMonitor: Any?

    private static let delay: TimeInterval = 1
    private static let maxWidth: CGFloat = 380
    private static let icons = NSCache<NSString, NSImage>()
    private static let dates: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    private init() {
        window.level = .popUpMenu   // above the panel, which floats
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false

        let effect = NSVisualEffectView()
        effect.material = .toolTip
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true

        contentLabel.font = .systemFont(ofSize: 13)
        contentLabel.maximumNumberOfLines = 8
        contentLabel.cell?.truncatesLastVisibleLine = true
        contentLabel.preferredMaxLayoutWidth = Self.maxWidth
        factsLabel.font = .systemFont(ofSize: 12)
        factsLabel.preferredMaxLayoutWidth = Self.maxWidth
        let appLabel = NSTextField(labelWithString: "Application:")
        for label in [appLabel, appName] { label.font = .systemFont(ofSize: 12) }
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appRow.setViews([appLabel, appIcon, appName], in: .leading)
        appRow.spacing = 4

        let separator = NSBox()
        separator.boxType = .separator
        stack.setViews([contentLabel, separator, appRow, factsLabel], in: .top)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(10, after: contentLabel)
        stack.setCustomSpacing(10, after: separator)
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            separator.heightAnchor.constraint(equalToConstant: 1),
            appIcon.widthAnchor.constraint(equalToConstant: 14),
            appIcon.heightAnchor.constraint(equalToConstant: 14),
        ])
        window.contentView = effect
    }

    /// Shows the card for `row` once the pointer has rested on it for a moment.
    func schedule(for row: HistoryRowView) {
        hide()
        self.row = row
        timer = Timer.scheduledTimer(withTimeInterval: Self.delay, repeats: false) { [weak self] _ in self?.show() }
        // Like a tooltip, any scroll, key press or click puts it away, or stops it from showing.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown, .leftMouseDown,
                                                                   .rightMouseDown]) { [weak self] event in
            DispatchQueue.main.async { self?.hide() }
            return event
        }
    }

    /// The pointer left `row`: hide its card, or don't show it.
    func cancel(for row: HistoryRowView) {
        if self.row === row { hide() }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        row = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        window.orderOut(nil)
    }

    private func show() {
        guard let row, row.window?.isVisible == true, let item = row.item else { return }
        contentLabel.stringValue = CopyDetails.content(of: item)
        var lines: [String] = []
        appRow.isHidden = true
        for fact in CopyDetails.facts(of: item) {
            switch fact {
            case .app(let app):
                appName.stringValue = app.name
                appIcon.image = Self.icon(for: app.bundleID)
                appIcon.isHidden = appIcon.image == nil
                appRow.isHidden = false
            case .firstCopied(let date): lines.append("First copy time: " + Self.dates.string(from: date))
            case .lastCopied(let date): lines.append("Last copy time: " + Self.dates.string(from: date))
            case .copies(let count): lines.append("Number of copies: \(count)")
            }
        }
        factsLabel.stringValue = lines.joined(separator: "\n")
        window.setFrame(frame(for: stack.fittingSize), display: true)
        window.orderFront(nil)
    }

    /// Below and right of the pointer, like a tooltip; above it when there's no room below.
    private func frame(for size: NSSize) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return NSRect(origin: mouse, size: size) }
        var origin = NSPoint(x: mouse.x + 8, y: mouse.y - 24 - size.height)
        if origin.y < visible.minY { origin.y = mouse.y + 8 }
        origin.x = max(visible.minX + 4, min(origin.x, visible.maxX - size.width - 4))
        return NSRect(origin: origin, size: size)
    }

    private static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons.object(forKey: bundleID as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }
}
