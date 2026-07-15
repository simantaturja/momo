import AppKit
import PastalCore
import Carbon

enum Paster {
    static func writeToPasteboard(_ item: ClipboardItem, imagesDir: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .richText:
            if let t = item.text { pb.setString(t, forType: .string) }
        case .image:
            if let rel = item.imagePath,
               let img = NSImage(contentsOfFile: (imagesDir as NSString).appendingPathComponent(rel)),
               let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        case .file:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        }
    }

    /// Synthesize Cmd+V into the frontmost app.
    static func synthesizePaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9   // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
