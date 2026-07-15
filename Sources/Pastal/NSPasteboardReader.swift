import AppKit
import PastalCore

final class NSPasteboardReader: PasteboardReading {
    private let pb = NSPasteboard.general
    var changeCount: Int { pb.changeCount }
    var types: Set<String> { Set((pb.types ?? []).map(\.rawValue)) }
    func string() -> String? { pb.string(forType: .string) }
    func imageData() -> Data? {
        pb.data(forType: .tiff) ?? pb.data(forType: .png)
    }
    func fileURLs() -> [String] {
        (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?
            .filter(\.isFileURL).map(\.path) ?? []
    }
}
