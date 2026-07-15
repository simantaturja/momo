import Foundation
import ServiceManagement

struct Settings {
    private static let d = UserDefaults.standard
    static var maxItems: Int { d.object(forKey: "maxItems") as? Int ?? 1000 }
    static var maxImageBytes: Int64 { Int64((d.object(forKey: "maxImageMB") as? Int ?? 500)) * 1_048_576 }
    static var imageMaxAge: TimeInterval { TimeInterval((d.object(forKey: "imageMaxAgeDays") as? Int ?? 30) * 86_400) }

    static var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("launchAtLogin toggle failed: \(error)") }
        }
    }
}
