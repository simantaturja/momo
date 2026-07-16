import Foundation

/// Compact relative-time labels for the history list (e.g. "just now", "2m", "3h", "Jul 16").
/// `now` is injected so callers can render deterministically and tests need no wall clock.
public enum RelativeTime {
    public static func format(_ date: Date, now: Date) -> String {
        let elapsed = now.timeIntervalSince(date)
        let minute: TimeInterval = 60
        let hour = 60 * minute
        let day = 24 * hour
        let week = 7 * day

        switch elapsed {
        case ..<minute:   return "just now"
        case ..<hour:     return "\(Int(elapsed / minute))m"
        case ..<day:      return "\(Int(elapsed / hour))h"
        case ..<week:     return "\(Int(elapsed / day))d"
        case ..<(4 * week): return "\(Int(elapsed / week))w"
        default:          return absoluteFormatter.string(from: date)
        }
    }

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()
}
