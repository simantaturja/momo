import Foundation

/// What the user chose to keep out of their history, checked at capture after `PrivacyFilter`.
public struct CaptureRules: Equatable, Sendable {
    public var saveText: Bool
    public var saveImages: Bool
    public var saveFiles: Bool
    /// Apps whose copies are dropped, or, with `onlyListedApps`, the only apps whose copies are kept.
    public var ignoredBundleIDs: Set<String>
    public var onlyListedApps: Bool
    /// Pasteboard type identifiers; a copy carrying any of them is dropped.
    public var ignoredTypes: Set<String>
    /// Regular expressions; text matching any of them anywhere is dropped. Invalid ones are skipped.
    public var ignoredPatterns: [String]

    public init(saveText: Bool = true, saveImages: Bool = true, saveFiles: Bool = true,
                ignoredBundleIDs: Set<String> = [], onlyListedApps: Bool = false,
                ignoredTypes: Set<String> = [], ignoredPatterns: [String] = []) {
        self.saveText = saveText
        self.saveImages = saveImages
        self.saveFiles = saveFiles
        self.ignoredBundleIDs = ignoredBundleIDs
        self.onlyListedApps = onlyListedApps
        self.ignoredTypes = ignoredTypes
        self.ignoredPatterns = ignoredPatterns
    }

    public func allows(types: Set<String>) -> Bool {
        types.isDisjoint(with: ignoredTypes)
    }

    /// `bundleID` is the source app's, nil when unknown: unknown is kept unless only listed apps are.
    public func allows(sourceBundleID bundleID: String?) -> Bool {
        guard let bundleID else { return !onlyListedApps }
        let listed = ignoredBundleIDs.contains(bundleID)
        return onlyListedApps ? listed : !listed
    }

    public func allows(text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return !ignoredPatterns.contains { pattern in
            guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: text, range: range) != nil
        }
    }
}
