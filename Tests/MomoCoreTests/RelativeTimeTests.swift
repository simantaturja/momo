import XCTest
@testable import MomoCore

final class RelativeTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_752_624_000)   // 2025-07-16 00:00:00 UTC

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    func testJustNow() {
        XCTAssertEqual(RelativeTime.format(now, now: now), "just now")           // 0s
        XCTAssertEqual(RelativeTime.format(ago(59), now: now), "just now")       // 59s, still < 60s
    }

    func testMinutes() {
        XCTAssertEqual(RelativeTime.format(ago(60), now: now), "1m")             // exactly 60s -> 1m
        XCTAssertEqual(RelativeTime.format(ago(2 * 60), now: now), "2m")
        XCTAssertEqual(RelativeTime.format(ago(59 * 60), now: now), "59m")       // last minute bucket
    }

    func testHours() {
        XCTAssertEqual(RelativeTime.format(ago(60 * 60), now: now), "1h")        // 60m -> 1h
        XCTAssertEqual(RelativeTime.format(ago(23 * 3600), now: now), "23h")     // last hour bucket
    }

    func testDays() {
        XCTAssertEqual(RelativeTime.format(ago(24 * 3600), now: now), "1d")      // 24h -> 1d
        XCTAssertEqual(RelativeTime.format(ago(6 * 86400), now: now), "6d")      // last day bucket
    }

    func testWeeks() {
        XCTAssertEqual(RelativeTime.format(ago(7 * 86400), now: now), "1w")      // 7d -> 1w
        XCTAssertEqual(RelativeTime.format(ago(27 * 86400), now: now), "3w")     // last week bucket (< 4w)
    }

    func testAbsoluteDate() {
        // Expected short-date string in the machine's own locale-neutral formatter, so the
        // assertion is deterministic regardless of the test host's time zone.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMM d"

        // 28d = 4w exactly -> falls through to short absolute date (NOT "4w").
        let boundary = ago(28 * 86400)
        XCTAssertEqual(RelativeTime.format(boundary, now: now), fmt.string(from: boundary))
        XCTAssertNotEqual(RelativeTime.format(boundary, now: now), "4w")

        // A clearly old date also takes the absolute branch.
        let old = ago(200 * 86400)
        XCTAssertEqual(RelativeTime.format(old, now: now), fmt.string(from: old))
    }
}
