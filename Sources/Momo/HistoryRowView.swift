import AppKit
import ImageIO
import MomoCore

/// A kind badge: a subtle rounded container holding either a monochrome SF Symbol (tinted
/// accent when its row is selected) or an image row's thumbnail. A pinned item gets an accent
/// dot in the corner — the pin is shown here, never baked into the label string.
private final class BadgeView: NSView {
    let iconView = NSImageView()
    var pinned = false { didSet { needsDisplay = true } }

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
        guard pinned else { return }
        let d: CGFloat = 7
        let dot = NSRect(x: bounds.maxX - d - 1, y: bounds.maxY - d - 1, width: d, height: d)
        Theme.accent.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }
}

private extension NSBezierPath {
    func fill(with color: NSColor) { color.setFill(); fill() }
}

final class HistoryRowView: NSTableCellView {
    private let badge = BadgeView()
    private let label = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private var currentImagePath: String?
    private var showingSymbol = true
    private var selected = false

    // Path-keyed cache of already-decoded thumbnails, shared across reused cells.
    private static let thumbCache = NSCache<NSString, NSImage>()

    override init(frame: NSRect) {
        super.init(frame: frame)
        badge.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

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

        addSubview(badge); addSubview(label); addSubview(timeLabel)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Called by `PillRowView` when the row's selection changes; tints a symbol badge accent.
    func setSelected(_ value: Bool) {
        selected = value
        if showingSymbol { badge.iconView.contentTintColor = value ? Theme.accent : Theme.badgeSymbol }
    }

    func configure(_ item: ClipboardItem, imagesDir: String) {
        label.stringValue = PreviewText.singleLine(item.preview)
        timeLabel.stringValue = RelativeTime.format(item.createdAt, now: Date())
        badge.pinned = item.pinned

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
