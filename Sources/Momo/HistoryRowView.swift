import AppKit
import MomoCore
import UniformTypeIdentifiers

/// A kind badge: a subtle rounded container holding a monochrome SF Symbol (tinted accent when
/// its row is selected), an untinted image (an image row's thumbnail or a file's type icon) or
/// a color clip's swatch.
private final class BadgeView: NSView {
    let iconView = NSImageView()
    /// Drawn as a 16×16 swatch in place of the icon.
    var swatch: NSColor? { didSet { needsDisplay = true } }

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
        guard let swatch else { return }
        let square = NSRect(x: bounds.midX - 8, y: bounds.midY - 8, width: 16, height: 16)
        NSBezierPath(roundedRect: square, xRadius: 4, yRadius: 4).fill(with: swatch)
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
    private var current: HistoryRow?
    private var rowIndex = 0
    private var relativeTime = ""
    private var currentImagePath: String?
    private var showingSymbol = true
    private var selected = false
    private var hovered = false
    private var multiSelect = false

    private static let uncheckedImage = NSImage(systemSymbolName: "circle", accessibilityDescription: "Select")
    private static let checkedImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Deselect")

    // File-type icons by lowercase extension, shared across reused cells.
    private static let fileIcons = NSCache<NSString, NSImage>()

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

    func configure(_ row: HistoryRow, index: Int, imagesDir: String, showQuickKey: Bool) {
        current = row
        rowIndex = index
        relativeTime = RelativeTime.format(row.item.createdAt, now: Date())
        setQuickKey(showQuickKey)
        pinIcon.isHidden = !row.item.pinned
        badge.swatch = nil
        currentImagePath = nil
        setLabel(imageSize: nil)

        switch row.item.kind {
        case .text:
            switch row.flavor {
            case .link: showSymbol("link")
            case .code: showSymbol("curlybraces")
            case .plain: showSymbol("doc.text")
            case .color:
                if let color = HexColor(row.line) { showSwatch(color.nsColor) } else { showSymbol("doc.text") }
            }
        case .richText: showSymbol("textformat")
        case .file: showImage(Self.fileIcon(for: row.item.filePaths.first ?? ""))
        case .image: showThumbnail(row.item.imagePath, imagesDir: imagesDir)
        }
    }

    /// While ⌘ is held the first nine rows show their ⌘1…⌘9 quick key instead of the time.
    func setQuickKey(_ on: Bool) {
        timeLabel.stringValue = on && rowIndex < 9 ? "⌘\(rowIndex + 1)" : relativeTime
    }

    /// Plain `stringValue` when there's nothing to style; otherwise an attributed label with
    /// matched letters, a dim link scheme, and a dim file folder or image size after the text.
    private func setLabel(imageSize: (width: Int, height: Int)?) {
        guard let row = current else { return }
        let code = row.flavor == .code
        let font: NSFont = code ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
        var suffix = ""
        if let imageSize {
            suffix = " · \(imageSize.width) × \(imageSize.height)"
        } else if row.item.kind == .file, let first = row.item.filePaths.first {
            suffix = "  " + ((first as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        }
        let line = row.line as NSString
        let scheme = row.flavor == .link ? line.range(of: "://") : NSRange(location: NSNotFound, length: 0)
        label.font = font
        label.textColor = .labelColor
        guard !row.matchedPositions.isEmpty || !suffix.isEmpty || scheme.location != NSNotFound else {
            label.stringValue = row.line   // fast path: nothing to style
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail   // attributed text ignores the field's own mode
        let text = NSMutableAttributedString(string: row.line + suffix, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        if scheme.location != NSNotFound {
            text.addAttribute(.foregroundColor, value: Theme.dimText, range: NSRange(location: 0, length: NSMaxRange(scheme)))
        }
        if !suffix.isEmpty {
            text.addAttribute(.foregroundColor, value: Theme.dimText,
                              range: NSRange(location: line.length, length: (suffix as NSString).length))
        }
        let bold: NSFont = code ? .monospacedSystemFont(ofSize: 12, weight: .bold) : .boldSystemFont(ofSize: 13)
        for range in PreviewText.highlightRanges(in: row.line, positions: row.matchedPositions) {
            text.addAttributes([.foregroundColor: Theme.matchText, .font: bold], range: range)
        }
        label.attributedStringValue = text
    }

    private func showThumbnail(_ rel: String?, imagesDir: String) {
        guard let rel else { showSymbol("photo"); return }
        let path = (imagesDir as NSString).appendingPathComponent(rel)
        currentImagePath = path
        if let cached = ImageLoader.cached(path: path, maxPixel: ImageLoader.thumbnailPixels) {
            showLoaded(cached)
            return
        }
        // Lazy: decoded off the main queue. Guard against cell reuse before showing it.
        showSymbol("photo")
        ImageLoader.load(path: path, maxPixel: ImageLoader.thumbnailPixels) { [weak self] loaded in
            guard let self, self.currentImagePath == path, let loaded else { return }
            self.showLoaded(loaded)
        }
    }

    private func showLoaded(_ loaded: LoadedImage) {
        showImage(loaded.image)
        setLabel(imageSize: (width: loaded.pixelWidth, height: loaded.pixelHeight))
    }

    private func showSymbol(_ name: String) {
        showingSymbol = true
        badge.iconView.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        badge.iconView.contentTintColor = selected ? Theme.accent : Theme.badgeSymbol
    }

    /// Thumbnails and file icons keep their own colors.
    private func showImage(_ image: NSImage) {
        showingSymbol = false
        badge.iconView.contentTintColor = nil
        badge.iconView.image = image
    }

    private func showSwatch(_ color: NSColor) {
        showingSymbol = false
        badge.iconView.image = nil
        badge.swatch = color
    }

    private static func fileIcon(for path: String) -> NSImage {
        let ext = (path as NSString).pathExtension.lowercased()
        if let cached = fileIcons.object(forKey: ext as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        fileIcons.setObject(icon, forKey: ext as NSString)
        return icon
    }
}
