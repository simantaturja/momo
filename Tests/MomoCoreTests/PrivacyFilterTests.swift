import XCTest
@testable import MomoCore

final class PrivacyFilterTests: XCTestCase {
    func testConcealedDropped() {
        XCTAssertFalse(PrivacyFilter.shouldStore(pasteboardTypes: ["org.nspasteboard.ConcealedType"]))
    }
    func testTransientDropped() {
        XCTAssertFalse(PrivacyFilter.shouldStore(pasteboardTypes: ["org.nspasteboard.TransientType"]))
    }
    func testNormalKept() {
        XCTAssertTrue(PrivacyFilter.shouldStore(pasteboardTypes: ["public.utf8-plain-text"]))
    }
    func testMixedWithConcealedDropped() {
        XCTAssertFalse(PrivacyFilter.shouldStore(pasteboardTypes: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
    }
}
