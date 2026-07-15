import Foundation

public protocol PasteboardReading: AnyObject {
    var changeCount: Int { get }
    var types: Set<String> { get }
    func string() -> String?
    func imageData() -> Data?
    func fileURLs() -> [String]
}
