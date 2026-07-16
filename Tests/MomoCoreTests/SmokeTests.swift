import XCTest
@testable import MomoCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(MomoCore.version, "0.2.0")
    }
}
