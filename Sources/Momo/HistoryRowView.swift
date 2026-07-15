import AppKit
import ImageIO
import MomoCore

final class HistoryRowView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let thumb = NSImageView()
    private var currentImagePath: String?

    // Path-keyed cache of already-decoded thumbnails, shared across reused cells.
    private static let thumbCache = NSCache<NSString, NSImage>()

    override init(frame: NSRect) {
        super.init(frame: frame)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        addSubview(thumb); addSubview(label)
        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 24),
            thumb.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ item: ClipboardItem, imagesDir: String) {
        label.stringValue = (item.pinned ? "📌 " : "") + item.preview
        guard item.kind == .image, let rel = item.imagePath else {
            currentImagePath = nil
            thumb.image = NSImage(systemSymbolName: symbol(for: item.kind), accessibilityDescription: nil)
            return
        }
        currentImagePath = rel
        if let cached = Self.thumbCache.object(forKey: rel as NSString) {
            thumb.image = cached
            return
        }
        // Lazy: downsample off the main queue, cache + set on main. Guard against cell reuse.
        thumb.image = nil
        let token = rel
        let path = (imagesDir as NSString).appendingPathComponent(rel)
        DispatchQueue.global(qos: .userInitiated).async {
            let img = Self.downsampledThumbnail(path: path, maxPixel: 48)
            DispatchQueue.main.async {
                if let img { Self.thumbCache.setObject(img, forKey: token as NSString) }
                guard self.currentImagePath == token else { return }   // row was reused
                self.thumb.image = img
            }
        }
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
