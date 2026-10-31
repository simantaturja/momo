import AppKit
import MomoCore

/// The right-hand pane: the selected item(s) in full — text, link parts, color values, a
/// larger image or file locations — over a one-line meta bar. Display only; everything shown
/// is derived from the rows it's handed.
final class PreviewPaneView: NSView {
    private let swatch = NSView()
    private let imageView = NSImageView()
    private let textScroll: NSScrollView
    private let textView: NSTextView
    private let metaLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private var swatchHeight: NSLayoutConstraint!
    private var swatchGap: NSLayoutConstraint!
    private var shownItems: [ClipboardItem] = []
    private var imageToken: String?

    override init(frame frameRect: NSRect) {
        let textScroll = NSTextView.scrollableTextView()
        self.textScroll = textScroll
        textView = textScroll.documentView as! NSTextView
        super.init(frame: frameRect)
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 8
        imageView.imageScaling = .scaleProportionallyDown
        // A big image must shrink to fit, never push the panel to grow.
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true

        let separator = NSBox()
        separator.boxType = .separator
        for label in [metaLabel, timeLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = Theme.dimText
            label.lineBreakMode = .byTruncatingTail
        }
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)

        // Content area, top to bottom: swatch (collapsed unless a color), then the text. The
        // image fills the whole area and is only shown on its own.
        for view in [swatch, imageView, textScroll, separator, metaLabel, timeLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        swatchHeight = swatch.heightAnchor.constraint(equalToConstant: 0)
        swatchGap = textScroll.topAnchor.constraint(equalTo: swatch.bottomAnchor)
        NSLayoutConstraint.activate([
            swatch.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            swatch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            swatchHeight,
            swatchGap,
            textScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            textScroll.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -8),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            imageView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -8),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            metaLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            metaLabel.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: metaLabel.trailingAnchor, constant: 8),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            timeLabel.centerYAnchor.constraint(equalTo: metaLabel.centerYAnchor),
        ])
        show([], imagesDir: "")
    }

    func show(_ rows: [HistoryRow], imagesDir: String) {
        let items = rows.map(\.item)
        timeLabel.stringValue = items.count == 1 ? RelativeTime.format(items[0].createdAt, now: Date()) : ""
        // Reloads (e.g. a keystroke that keeps the same item selected) re-show the same items;
        // only the time can have changed, so skip rebuilding the content.
        guard items != shownItems || items.isEmpty else { return }
        shownItems = items
        imageToken = nil
        metaLabel.stringValue = ""
        imageView.image = nil
        imageView.isHidden = true
        textScroll.isHidden = false
        setSwatch(nil)
        let text = NSMutableAttributedString()

        if rows.count > 1 {
            showSeveral(rows, into: text)
        } else if let row = rows.first {
            showOne(row, imagesDir: imagesDir, into: text)
        }
        textView.textStorage?.setAttributedString(text)
        textView.scroll(.zero)
    }

    private func showOne(_ row: HistoryRow, imagesDir: String, into text: NSMutableAttributedString) {
        let item = row.item
        switch item.kind {
        case .image:
            textScroll.isHidden = true
            imageView.isHidden = false
            metaLabel.stringValue = "Image"
            guard let rel = item.imagePath else { return }
            showImage(path: (imagesDir as NSString).appendingPathComponent(rel))
        case .file:
            appendFiles(item.filePaths, to: text)
            metaLabel.stringValue = count(item.filePaths.count, "file")
        case .text, .richText:
            let full = item.text ?? item.preview
            // Exact counts walk the whole text, so only when it fits the excerpt; a bigger clip
            // gets its size instead (`utf8.count` is O(1) for a native string).
            let fits = PreviewText.fitsExcerpt(full)
            let size = ByteCountFormatter.string(fromByteCount: Int64(full.utf8.count), countStyle: .file)
            switch row.flavor {
            case .plain:
                append(PreviewText.excerpt(full), .systemFont(ofSize: 13), to: text)
                metaLabel.stringValue = "Text · " + (fits
                    ? "\(count(PreviewText.lineCount(full), "line")) · \(count(full.count, "character"))"
                    : size)
            case .code:
                append(PreviewText.excerpt(full), .monospacedSystemFont(ofSize: 12, weight: .regular), to: text)
                metaLabel.stringValue = "Code · " + (fits ? count(PreviewText.lineCount(full), "line") : size)
            case .link:
                let link = full.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = URL(string: link)
                append(url?.host ?? "", .systemFont(ofSize: 17, weight: .semibold), to: text)
                if let path = url?.path, !path.isEmpty {
                    append("\n" + path, .systemFont(ofSize: 13), .secondaryLabelColor, to: text)
                }
                append("\n\n" + PreviewText.excerpt(link), .monospacedSystemFont(ofSize: 11, weight: .regular),
                       .tertiaryLabelColor, to: text)
                metaLabel.stringValue = "Link"
            case .color:
                guard let color = HexColor(row.line) else { return }
                setSwatch(color.nsColor)
                let hsl = color.hsl
                append("Hex  \(color.hex)\nRGB  \(color.red), \(color.green), \(color.blue)\n"
                       + "HSL  \(hsl.hue)°, \(hsl.saturation)%, \(hsl.lightness)%",
                       .monospacedSystemFont(ofSize: 13, weight: .regular), to: text)
                metaLabel.stringValue = "Color"
            }
        }
    }

    private func showSeveral(_ rows: [HistoryRow], into text: NSMutableAttributedString) {
        append(count(rows.count, "item"), .systemFont(ofSize: 15, weight: .semibold), to: text)
        append("\n↵ copies them together", .systemFont(ofSize: 12), Theme.dimText, to: text)
        let clip = CombinedClip(rows.map(\.item))
        if !clip.texts.isEmpty {
            appendSection("TEXT", to: text)
            append(PreviewText.joinedExcerpt(clip.texts), .monospacedSystemFont(ofSize: 12, weight: .regular), to: text)
        }
        if !clip.filePaths.isEmpty {
            appendSection("FILES", to: text)
            appendFiles(clip.filePaths, to: text)
        }
        if !clip.imagePaths.isEmpty {
            appendSection("IMAGES", to: text)
            append(count(clip.imagePaths.count, "image"), .systemFont(ofSize: 13), to: text)
        }
        metaLabel.stringValue = count(rows.count, "item")
    }

    /// Shows the row's cached thumbnail at once, then the sharper preview when it's decoded.
    private func showImage(path: String) {
        if let preview = ImageLoader.cached(path: path, maxPixel: Self.previewPixels) {
            showLoaded(preview)
            return
        }
        imageView.image = ImageLoader.cached(path: path, maxPixel: ImageLoader.thumbnailPixels)?.image
        imageToken = path
        ImageLoader.load(path: path, maxPixel: Self.previewPixels) { [weak self] loaded in
            guard let self, self.imageToken == path, let loaded else { return }   // selection moved on
            self.showLoaded(loaded)
        }
    }

    private func showLoaded(_ loaded: LoadedImage) {
        imageView.image = loaded.image
        var meta = "Image · \(loaded.pixelWidth) × \(loaded.pixelHeight)"
        if let bytes = loaded.byteSize {
            meta += " · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        metaLabel.stringValue = meta
    }

    private func setSwatch(_ color: NSColor?) {
        swatch.isHidden = color == nil
        swatch.layer?.backgroundColor = color?.cgColor
        swatchHeight.constant = color == nil ? 0 : 120
        swatchGap.constant = color == nil ? 0 : 12
    }

    /// Name and folder per file, capped so a huge selection stays cheap to lay out.
    private func appendFiles(_ paths: [String], to text: NSMutableAttributedString) {
        for (i, path) in paths.prefix(Self.maxFiles).enumerated() {
            let name = (path as NSString).lastPathComponent
            let folder = ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
            append((i == 0 ? "" : "\n") + name, .systemFont(ofSize: 13, weight: .semibold), to: text)
            append("\n" + folder, .systemFont(ofSize: 11), Theme.dimText, to: text)
        }
        if paths.count > Self.maxFiles {
            append("\nand \(paths.count - Self.maxFiles) more", .systemFont(ofSize: 11), Theme.dimText, to: text)
        }
    }

    private func appendSection(_ title: String, to text: NSMutableAttributedString) {
        append("\n\n" + title + "\n", .systemFont(ofSize: 11, weight: .semibold), Theme.dimText, to: text)
    }

    private func append(_ string: String, _ font: NSFont, _ color: NSColor = .labelColor,
                        to text: NSMutableAttributedString) {
        text.append(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]))
    }

    /// "1 line", "2 lines".
    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    private static let previewPixels = 600
    private static let maxFiles = 50
}
