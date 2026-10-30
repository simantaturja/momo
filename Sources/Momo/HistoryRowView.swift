import AppKit
import ImageIO
import MomoCore

/// A kind badge: a subtle rounded container holding either a monochrome SF Symbol (tinted
/// accent when its row is selected) or an image row's thumbnail.
private final class BadgeView: NSView {
    let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            iconView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill(with: Theme.badgeFill)
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor) { color.setFill(); fill() }
}

final class HistoryRowView: NSTableCellView {
    /// Called when the row's checkbox is clicked; the owner toggles this row in the table selection.
    var onCheckboxClick: ((HistoryRowView) -> Void)?
    private let checkbox = NSButton()
    private let badge = BadgeView()
    private let label = NSTextField(labelWithString: "")
    private let pinIcon = NSImageView()
    private let timeLabel = NSTextField(labelWithString: "")
    private var currentImagePath: String?
    private var showingSymbol = true
    private var selected = false
    private var hovered = false
    private var multiSelect = false

    private static let uncheckedImage = NSImage(systemSymbolName: "circle", accessibilityDescription: "Select")
    private static let checkedImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Deselect")

    // Path-keyed cache of already-decoded thumbnails, shared across reused cells.
    private static let thumbCache = NSCache<NSString, NSImage>()

    override init(frame: NSRect) {
        super.init(frame: frame)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        checkbox.isBordered = false
        checkbox.imagePosition = .imageOnly
        checkbox.imageScaling = .scaleProportionallyUpOrDown
        checkbox.target = self
        checkbox.action = #selector(checkboxClicked)
        updateCheckbox()

        pinIcon.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pinIcon.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        pinIcon.contentTintColor = Theme.dimText

        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true   // collapse embedded newlines; one row, one line
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = Theme.dimText
        timeLabel.alignment = .right
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Pin + time in a stack so a hidden pin collapses out of the layout.
        let trailing = NSStackView(views: [pinIcon, timeLabel])
        trailing.spacing = 4
        trailing.setHuggingPriority(.required, for: .horizontal)
        trailing.translatesAutoresizingMaskIntoConstraints = false

        addSubview(checkbox); addSubview(badge); addSubview(label); addSubview(trailing)
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkbox.widthAnchor.constraint(equalToConstant: 18),
            checkbox.heightAnchor.constraint(equalToConstant: 18),
            badge.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Called by `PillRowView` when the row's selection changes; tints a symbol badge accent.
    func setSelected(_ value: Bool) {
        selected = value
        if showingSymbol { badge.iconView.contentTintColor = value ? Theme.accent : Theme.badgeSymbol }
        updateCheckbox()
    }

    /// Called by `PillRowView` on hover changes; a hovered row shows its checkbox.
    func setHovered(_ value: Bool) { hovered = value; updateCheckbox() }

    /// Set by `HistoryView` while ≥2 rows are selected; every row then shows its checkbox.
    func setMultiSelect(_ value: Bool) { multiSelect = value; updateCheckbox() }

    private func updateCheckbox() {
        checkbox.isHidden = !(hovered || multiSelect)
        checkbox.image = selected ? Self.checkedImage : Self.uncheckedImage
        checkbox.contentTintColor = selected ? Theme.accent : Theme.badgeSymbol
    }

    @objc private func checkboxClicked() { onCheckboxClick?(self) }

    func configure(_ item: ClipboardItem, imagesDir: String) {
        label.stringValue = PreviewText.singleLine(item.preview)
        timeLabel.stringValue = RelativeTime.format(item.createdAt, now: Date())
        pinIcon.isHidden = !item.pinned

        guard item.kind == .image, let rel = item.imagePath else {
            showSymbol(for: item.kind)
            return
        }
        currentImagePath = rel
        if let cached = Self.thumbCache.object(forKey: rel as NSString) {
            showThumbnail(cached)
            return
        }
        // Lazy: downsample off the main queue, cache + set on main. Guard against cell reuse.
        showSymbol(for: .image)
        let token = rel
        let path = (imagesDir as NSString).appendingPathComponent(rel)
        DispatchQueue.global(qos: .userInitiated).async {
            let img = Self.downsampledThumbnail(path: path, maxPixel: 48)
            DispatchQueue.main.async {
                if let img { Self.thumbCache.setObject(img, forKey: token as NSString) }
                guard self.currentImagePath == token, let img else { return }   // row was reused
                self.showThumbnail(img)
            }
        }
    }

    private func showSymbol(for kind: ItemKind) {
        showingSymbol = true
        badge.iconView.image = NSImage(systemSymbolName: symbol(for: kind), accessibilityDescription: nil)
        badge.iconView.contentTintColor = selected ? Theme.accent : Theme.badgeSymbol
    }

    private func showThumbnail(_ image: NSImage) {
        showingSymbol = false
        badge.iconView.contentTintColor = nil
        badge.iconView.image = image
    }

    private static func downsampledThumbnail(path: String, maxPixel: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func symbol(for kind: ItemKind) -> String {
        switch kind {
        case .text: return "doc.text"
        case .richText: return "textformat"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}
