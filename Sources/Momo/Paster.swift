import AppKit
import MomoCore

enum Paster {
    /// Writes the items to the general pasteboard as one copy (see `CombinedClip`): joined
    /// text first, so a text paste gets every snippet, then file URLs, then images. Returns
    /// whether any content was actually written.
    @discardableResult
    static func writeToPasteboard(_ items: [ClipboardItem], imagesDir: String) -> Bool {
        let clip = CombinedClip(items)
        var objects: [NSPasteboardWriting] = []
        if let t = clip.text { objects.append(t as NSString) }
        objects += clip.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
        for rel in clip.imagePaths {
            if let img = NSImage(contentsOfFile: (imagesDir as NSString).appendingPathComponent(rel)) {
                objects.append(img)
            } else {
                NSLog("Momo: skipping missing image blob \(rel)")
            }
        }
        guard !objects.isEmpty else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.writeObjects(objects) else { return false }
        // Tag it as Momo's own so the monitor doesn't credit it to the app in front.
        pb.setString("", forType: NSPasteboard.PasteboardType(ClipboardMonitor.ownCopyType))
        return true
    }
}
