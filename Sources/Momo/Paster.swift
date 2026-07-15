import AppKit
import ApplicationServices
import MomoCore
import Carbon

enum Paster {
    /// Whether the process is trusted for Accessibility. Synthetic keystrokes
    /// (`synthesizePaste`) are silently dropped by macOS unless this is true.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt if not yet trusted; no-op once granted.
    static func promptForAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Writes the item to the general pasteboard. Returns whether any content was
    /// actually written, so the caller can skip synthesizing a paste of nothing.
    @discardableResult
    static func writeToPasteboard(_ item: ClipboardItem, imagesDir: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .richText:
            guard let t = item.text else { return false }
            return pb.setString(t, forType: .string)
        case .image:
            guard let rel = item.imagePath,
                  let img = NSImage(contentsOfFile: (imagesDir as NSString).appendingPathComponent(rel)),
                  let tiff = img.tiffRepresentation else { return false }
            return pb.setData(tiff, forType: .tiff)
        case .file:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return false }
            return pb.writeObjects(urls)
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
