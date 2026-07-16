import AppKit

/// Row background that draws selection as a floating, inset rounded pill (soft accent fill)
/// instead of a full-width bar. Redraws only visible rows, via the standard `drawSelection`.
final class PillRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let pill = bounds.insetBy(dx: 8, dy: 4)
        let path = NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8)
        Theme.selectionFill.setFill()
        path.fill()
    }

    // Forward selection to the cell so its kind-badge symbol can tint accent when active.
    override var isSelected: Bool {
        didSet {
            for sub in subviews { (sub as? HistoryRowView)?.setSelected(isSelected) }
        }
    }

    // A recycled cell re-attached on reloadData may carry a stale tint while isSelected
    // did not change (so didSet never fires); sync it the moment the cell is inserted.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        (subview as? HistoryRowView)?.setSelected(isSelected)
    }
}
