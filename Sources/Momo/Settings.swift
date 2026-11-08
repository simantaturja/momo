import Foundation
import MomoCore
import ServiceManagement

/// Where the history panel opens.
enum PopupPosition: String {
    case menuIcon, cursor, screenCenter
}

/// How matched letters are marked in search results.
enum MatchHighlight: String {
    case accent, bold, underline
}

struct Settings {
    private static let d = UserDefaults.standard

    /// Posted on main after a setting is changed in-app, so the change applies live.
    static let didChange = Notification.Name("MomoSettingsDidChange")

    private static func write(_ value: Any?, _ key: String) {
        d.set(value, forKey: key)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// `bool(forKey:)` also reads a `defaults write … true` typed as a string.
    private static func flag(_ key: String, default fallback: Bool = false) -> Bool {
        d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }

    static var maxItems: Int {
        get { d.object(forKey: "maxItems") as? Int ?? 1000 }
        set { write(newValue, "maxItems") }
    }
    static var maxImageBytes: Int64 { Int64((d.object(forKey: "maxImageMB") as? Int ?? 500)) * 1_048_576 }
    static var imageMaxAge: TimeInterval { TimeInterval((d.object(forKey: "imageMaxAgeDays") as? Int ?? 30) * 86_400) }
    /// Opt-in: keep passwords copied from a password manager. Off by default.
    static var savePasswords: Bool {
        get { d.bool(forKey: "savePasswords") }
        set { write(newValue, "savePasswords") }
    }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("launchAtLogin toggle failed: \(error)") }
        }
    }

    // MARK: Storage

    static var saveText: Bool { get { flag("saveText", default: true) } set { write(newValue, "saveText") } }
    static var saveImages: Bool { get { flag("saveImages", default: true) } set { write(newValue, "saveImages") } }
    static var saveFiles: Bool { get { flag("saveFiles", default: true) } set { write(newValue, "saveFiles") } }
    static var sortBy: HistorySort {
        get { d.string(forKey: "sortBy").flatMap(HistorySort.init(rawValue:)) ?? .lastCopy }
        set { write(newValue.rawValue, "sortBy") }
    }

    // MARK: Appearance

    static var pinsAt: PinPlacement {
        get { d.string(forKey: "pinsAt").flatMap(PinPlacement.init(rawValue:)) ?? .top }
        set { write(newValue.rawValue, "pinsAt") }
    }
    static var popupAt: PopupPosition {
        get { d.string(forKey: "popupAt").flatMap(PopupPosition.init(rawValue:)) ?? .menuIcon }
        set { write(newValue.rawValue, "popupAt") }
    }
    static var highlightMatches: MatchHighlight {
        get { d.string(forKey: "highlightMatches").flatMap(MatchHighlight.init(rawValue:)) ?? .accent }
        set { write(newValue.rawValue, "highlightMatches") }
    }
    static var showRecentCopyInMenuBar: Bool {
        get { flag("showRecentCopyInMenuBar") }
        set { write(newValue, "showRecentCopyInMenuBar") }
    }
    static var showKeyboardHints: Bool {
        get { flag("showKeyboardHints", default: true) }
        set { write(newValue, "showKeyboardHints") }
    }

    // MARK: Ignore

    /// Bundle identifiers.
    static var ignoredApps: [String] {
        get { d.stringArray(forKey: "ignoredApps") ?? [] }
        set { write(newValue, "ignoredApps") }
    }
    static var ignoreAllExceptListed: Bool {
        get { flag("ignoreAllExceptListed") }
        set { write(newValue, "ignoreAllExceptListed") }
    }
    static var ignoredPasteboardTypes: [String] {
        get { d.stringArray(forKey: "ignoredPasteboardTypes") ?? [] }
        set { write(newValue, "ignoredPasteboardTypes") }
    }
    static var ignoredPatterns: [String] {
        get { d.stringArray(forKey: "ignoredPatterns") ?? [] }
        set { write(newValue, "ignoredPatterns") }
    }

    /// Read on every capture.
    static var captureRules: CaptureRules {
        CaptureRules(saveText: saveText, saveImages: saveImages, saveFiles: saveFiles,
                     ignoredBundleIDs: Set(ignoredApps), onlyListedApps: ignoreAllExceptListed,
                     ignoredTypes: Set(ignoredPasteboardTypes), ignoredPatterns: ignoredPatterns)
    }

    // MARK: Advanced

    /// Pause: also settable from Terminal (`defaults write me.momo.app ignoreEvents true`), so it's
    /// read on every check rather than cached. AppDelegate's KVO observer posts `didChange` for
    /// every change to it, in-app or not, so the setter doesn't.
    static var ignoreEvents: Bool {
        get { flag("ignoreEvents") }
        set { d.set(newValue, forKey: "ignoreEvents") }
    }
    static var ignoreOnlyNextEvent: Bool {
        get { flag("ignoreOnlyNextEvent") }
        set { write(newValue, "ignoreOnlyNextEvent") }
    }
    /// Whether to skip this copy; clears the request. Called on the poll queue.
    static func consumeIgnoreNext() -> Bool {
        guard flag("ignoreOnlyNextEvent") else { return false }
        d.set(false, forKey: "ignoreOnlyNextEvent")
        return true
    }
    /// Clears unpinned history and the system clipboard on quit.
    static var clearHistoryOnQuit: Bool {
        get { flag("clearHistoryOnQuit") }
        set { write(newValue, "clearHistoryOnQuit") }
    }
}
