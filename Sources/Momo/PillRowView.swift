import AppKit

/// Row background that draws selection as a floating, inset rounded pill (soft accent fill)
/// instead of a full-width bar, and a neutral pill while hovered. Redraws only visible rows.
final class PillRowView: NSTableRowView {
    private var hovered = false {
        didSet {
            guard hovered != oldValue else { return }
            needsDisplay = true
            for sub in subviews { (sub as? HistoryRowView)?.setHovered(hovered) }
        }
    }

    private var pill: NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 4), xRadius: 8, yRadius: 8)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        Theme.selectionFill.setFill()
        pill.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard hovered, !isSelected else { return }
        Theme.hoverFill.setFill()
        pill.fill()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // .inVisibleRect tracks the row's visible bounds automatically; one area for life.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    /// Drops hover on reuse, and when the panel hides (no mouseExited arrives once it's ordered out).
    func clearHover() { hovered = false }

    override func prepareForReuse() {
        super.prepareForReuse()
        clearHover()
    }

    // Forward selection to the cell so its kind-badge symbol can tint accent when active.
    override var isSelected: Bool {
        didSet {
            for sub in subviews { (sub as? HistoryRowView)?.setSelected(isSelected) }
        }
    }

    // A recycled cell re-attached on reloadData may carry a stale tint/hover while the row's
    // state did not change (so didSet never fires); sync it the moment the cell is inserted.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        (subview as? HistoryRowView)?.setSelected(isSelected)
        (subview as? HistoryRowView)?.setHovered(hovered)
    }
}
