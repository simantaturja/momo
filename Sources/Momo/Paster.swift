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
        return pb.writeObjects(objects)
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
