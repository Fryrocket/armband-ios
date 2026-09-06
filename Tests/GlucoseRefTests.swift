import XCTest
@testable import ArmbandIOS

final class GlucoseRefTests: XCTestCase {
    func testParsesWholeAndDecimal() {
        XCTAssertEqual(GlucoseRef.parseMgdl("102"), 102)
        XCTAssertEqual(GlucoseRef.parseMgdl("102.4") ?? 0, 102.4, accuracy: 0.001)
        XCTAssertEqual(GlucoseRef.parseMgdl("  88,5 ") ?? 0, 88.5, accuracy: 0.001)
    }

    func testRejectsJunk() {
        XCTAssertNil(GlucoseRef.parseMgdl(""))
        XCTAssertNil(GlucoseRef.parseMgdl("abc"))
        XCTAssertNil(GlucoseRef.parseMgdl("0"))
        XCTAssertNil(GlucoseRef.parseMgdl("-12"))
        XCTAssertNil(GlucoseRef.parseMgdl("5000"))
    }
}
