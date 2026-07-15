import XCTest
@testable import PastalCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(PastalCore.version, "0.1.0")
    }
}
