import XCTest
@testable import ViewCore

final class SmokeTest: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(ViewCore.version, "0.1.0")
    }
}
