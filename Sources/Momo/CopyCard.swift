import AppKit
import MomoCore

/// The hover card: when the pointer rests on a row, a small floating card near it shows the
/// item's content and copy history (`CopyDetails`). One card for the whole list; display only.
/// It never takes focus or mouse events, so it can't dismiss the panel or steal its hover.
final class CopyCard {
    static let shared = CopyCard()

    private let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: true)
    private let cardView = CardView()
    private weak var row: HistoryRowView?
    private var timer: Timer?
    private var eventMonitor: Any?

    private static let delay: TimeInterval = 1
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
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        cardView.autoresizingMask = [.width, .height]
        effect.addSubview(cardView)
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
        let lines = CopyDetails.facts(of: item).map { fact -> CardView.Line in
            switch fact {
            case .app(let app):
                return CardView.Line(label: "Application:", value: app.name, icon: Self.icon(for: app.bundleID))
            case .firstCopied(let date):
                return CardView.Line(label: "First copy time:", value: Self.dates.string(from: date), icon: nil)
            case .lastCopied(let date):
                return CardView.Line(label: "Last copy time:", value: Self.dates.string(from: date), icon: nil)
            case .copies(let count):
                return CardView.Line(label: "Number of copies:", value: "\(count)", icon: nil)
            }
        }
        let size = cardView.show(content: CopyDetails.content(of: item), lines: lines)
        window.setFrame(frame(for: size), display: false)
        cardView.frame = NSRect(origin: .zero, size: size)
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

/// Draws the card: the content (wrapping), a separator, then one line per fact, a dimmed label
/// and its value. It measures and draws its text with the same NSAttributedString calls, so the
/// size it asks for is exactly what it draws.
private final class CardView: NSView {
    struct Line {
        let label: String
        let value: String
        let icon: NSImage?
    }

    private var content = NSAttributedString()
    private var lines: [Line] = []
    private var textWidth: CGFloat = 0
    private var contentHeight: CGFloat = 0

    private static let inset = NSSize(width: 16, height: 14)
    private static let minTextWidth: CGFloat = 200
    private static let maxTextWidth: CGFloat = 480
    private static let separatorGap: CGFloat = 10   // above and below the separator
    private static let lineSpacing: CGFloat = 4
    private static let space: CGFloat = 5           // between a label, the icon and the value
    private static let iconSize: CGFloat = 14
    private static let drawing: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

    private static let contentAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor,
    ]
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
    ]
    private static let valueAttributes: [NSAttributedString.Key: Any] = {
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        return [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: truncating]
    }()
    private static let lineHeight = ceil(NSAttributedString(string: "Ag", attributes: valueAttributes).size().height)

    override var isFlipped: Bool { true }   // lay out top down

    /// Takes what to draw and returns the size it needs.
    func show(content text: String, lines: [Line]) -> NSSize {
        content = NSAttributedString(string: text, attributes: Self.contentAttributes)
        self.lines = lines
        // As wide as the widest line, between the limits; longer content wraps.
        let widest = max(Self.textBounds(content, width: Self.maxTextWidth).width,
                         lines.map(Self.width(of:)).max() ?? 0)
        textWidth = ceil(min(Self.maxTextWidth, max(Self.minTextWidth, widest)))
        contentHeight = ceil(Self.textBounds(content, width: textWidth).height)
        needsDisplay = true

        let factsHeight = CGFloat(lines.count) * Self.lineHeight + CGFloat(max(lines.count - 1, 0)) * Self.lineSpacing
        let height = Self.inset.height + contentHeight + 2 * Self.separatorGap + 1 + factsHeight + Self.inset.height
        return NSSize(width: textWidth + 2 * Self.inset.width, height: ceil(height))
    }

    override func draw(_ dirtyRect: NSRect) {
        let x = Self.inset.width
        var y = Self.inset.height
        content.draw(with: NSRect(x: x, y: y, width: textWidth, height: contentHeight), options: Self.drawing,
                     context: nil)
        y += contentHeight + Self.separatorGap

        NSColor.separatorColor.setFill()
        NSRect(x: x, y: y, width: textWidth, height: 1).fill()
        y += 1 + Self.separatorGap

        for line in lines {
            let label = NSAttributedString(string: line.label, attributes: Self.labelAttributes)
            label.draw(at: NSPoint(x: x, y: y))
            var valueX = x + ceil(label.size().width) + Self.space
            if let icon = line.icon {
                let iconY = y + ((Self.lineHeight - Self.iconSize) / 2).rounded()
                icon.draw(in: NSRect(x: valueX, y: iconY, width: Self.iconSize, height: Self.iconSize),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                valueX += Self.iconSize + Self.space
            }
            // Only a value wider than the card's limit is cut, with "…".
            NSAttributedString(string: line.value, attributes: Self.valueAttributes)
                .draw(with: NSRect(x: valueX, y: y, width: max(0, x + textWidth - valueX), height: Self.lineHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            y += Self.lineHeight + Self.lineSpacing
        }
    }

    private static func textBounds(_ text: NSAttributedString, width: CGFloat) -> NSRect {
        text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: drawing, context: nil)
    }

    /// One fact line on a single line: label, icon, value.
    private static func width(of line: Line) -> CGFloat {
        let label = NSAttributedString(string: line.label, attributes: labelAttributes).size().width
        let value = NSAttributedString(string: line.value, attributes: valueAttributes).size().width
        return ceil(label) + space + (line.icon == nil ? 0 : iconSize + space) + ceil(value)
    }
}
