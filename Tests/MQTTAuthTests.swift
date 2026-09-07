import XCTest
@testable import ArmbandIOS

final class MQTTAuthTests: XCTestCase {
    func testBothPresentPassThrough() {
        let c = MQTTAuth.wireCredentials(username: "armband", password: "secret")
        XCTAssertEqual(c.username, "armband")
        XCTAssertEqual(c.password, "secret")
    }

    func testPartialUserBecomesAnonymous() {
        let c = MQTTAuth.wireCredentials(username: "armband", password: "")
        XCTAssertNil(c.username)
        XCTAssertNil(c.password)
    }

    func testMissingBecomesAnonymous() {
        let c = MQTTAuth.wireCredentials(username: nil, password: nil)
        XCTAssertNil(c.username)
        XCTAssertNil(c.password)
    }

    func testWhitespaceOnlyBecomesAnonymous() {
        let c = MQTTAuth.wireCredentials(username: "  ", password: " x ")
        XCTAssertNil(c.username)
        XCTAssertNil(c.password)
    }
}
