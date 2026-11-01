import AppKit
import MomoCore

/// The hover card: when the pointer rests on a row, a small floating card near it shows the
/// item's content and copy history (`CopyDetails`). One card for the whole list; display only.
/// It never takes focus or mouse events, so it can't dismiss the panel or steal its hover.
final class CopyCard {
    static let shared = CopyCard()

    private let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: true)
    private let contentLabel = NSTextField(wrappingLabelWithString: "")
    private let separator = NSBox()
    private let appLabel = NSTextField(labelWithString: "Application:")
    private let appIcon = NSImageView()
    private let appName = NSTextField(labelWithString: "")
    private let factsLabel = NSTextField(wrappingLabelWithString: "")
    private var showsApp = false
    private weak var row: HistoryRowView?
    private var timer: Timer?
    private var eventMonitor: Any?

    private static let delay: TimeInterval = 1
    private static let maxTextWidth: CGFloat = 380
    private static let inset = NSSize(width: 12, height: 10)
    private static let iconSize: CGFloat = 14
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
        separator.boxType = .separator
        for label in [appLabel, appName, factsLabel] { label.font = .systemFont(ofSize: 12) }
        appName.lineBreakMode = .byTruncatingTail
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        // Laid out by hand in `layOut()`: a wrapping label has no natural width for Auto Layout
        // to size the card by.
        for view in [contentLabel, separator, appLabel, appIcon, appName, factsLabel] as [NSView] {
            effect.addSubview(view)
        }
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
        showsApp = false
        for fact in CopyDetails.facts(of: item) {
            switch fact {
            case .app(let app):
                appName.stringValue = app.name
                appIcon.image = Self.icon(for: app.bundleID)
                showsApp = true
            case .firstCopied(let date): lines.append("First copy time: " + Self.dates.string(from: date))
            case .lastCopied(let date): lines.append("Last copy time: " + Self.dates.string(from: date))
            case .copies(let count): lines.append("Number of copies: \(count)")
            }
        }
        factsLabel.stringValue = lines.joined(separator: "\n")
        window.setFrame(frame(for: layOut()), display: true)
        window.orderFront(nil)
    }

    /// Sizes and places every view, bottom up (AppKit's y grows upward), and returns the card's size.
    private func layOut() -> NSSize {
        let hasIcon = showsApp && appIcon.image != nil
        let labelSize = appLabel.intrinsicContentSize
        let nameSize = appName.intrinsicContentSize
        let iconSpace = hasIcon ? Self.iconSize + 4 : 0
        let appRowWidth = showsApp ? labelSize.width + 4 + iconSpace + nameSize.width : 0

        // As wide as the widest line, up to the cap; long text wraps at the cap.
        let width = ceil(min(Self.maxTextWidth, max(textSize(contentLabel, width: Self.maxTextWidth).width,
                                                    textSize(factsLabel, width: Self.maxTextWidth).width,
                                                    appRowWidth)))
        let x = Self.inset.width
        var y = Self.inset.height

        let factsHeight = ceil(textSize(factsLabel, width: width).height)
        factsLabel.frame = NSRect(x: x, y: y, width: width, height: factsHeight)
        y += factsHeight

        appLabel.isHidden = !showsApp
        appName.isHidden = !showsApp
        appIcon.isHidden = !hasIcon
        if showsApp {
            let rowHeight = ceil(max(labelSize.height, nameSize.height, hasIcon ? Self.iconSize : 0))
            y += 2
            appLabel.frame = NSRect(x: x, y: y + (rowHeight - labelSize.height) / 2,
                                    width: labelSize.width, height: labelSize.height)
            let iconX = x + labelSize.width + 4
            appIcon.frame = NSRect(x: iconX, y: y + (rowHeight - Self.iconSize) / 2,
                                   width: Self.iconSize, height: Self.iconSize)
            let nameX = iconX + iconSpace
            appName.frame = NSRect(x: nameX, y: y + (rowHeight - nameSize.height) / 2,
                                   width: max(0, min(nameSize.width, x + width - nameX)), height: nameSize.height)
            y += rowHeight
        }

        y += 8
        separator.frame = NSRect(x: x, y: y, width: width, height: 1)
        y += 1 + 8

        let contentHeight = ceil(textSize(contentLabel, width: width).height)
        contentLabel.frame = NSRect(x: x, y: y, width: width, height: contentHeight)
        y += contentHeight + Self.inset.height

        return NSSize(width: width + 2 * Self.inset.width, height: y)
    }

    /// What `label`'s text needs when wrapped at `width`.
    private func textSize(_ label: NSTextField, width: CGFloat) -> NSSize {
        label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)) ?? .zero
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
