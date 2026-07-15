import AppKit
import PastalCore

final class HistoryRowView: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    private let thumb = NSImageView()

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
        if item.kind == .image, let rel = item.imagePath {
            // Lazy: load thumbnail off main queue, set on main.
            let path = (imagesDir as NSString).appendingPathComponent(rel)
            DispatchQueue.global(qos: .userInitiated).async {
                let img = NSImage(contentsOfFile: path)
                DispatchQueue.main.async { self.thumb.image = img }
            }
        } else {
            thumb.image = NSImage(systemSymbolName: symbol(for: item.kind), accessibilityDescription: nil)
        }
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
