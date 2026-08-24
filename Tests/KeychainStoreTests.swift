import XCTest
@testable import ArmbandIOS

final class KeychainStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeychainStore.service = "com.fryrocket.armbandios.mqtt.test"
        _ = KeychainStore.delete(account: "mqtt_username")
        _ = KeychainStore.delete(account: "mqtt_password")
    }

    override func tearDown() {
        _ = KeychainStore.delete(account: "mqtt_username")
        _ = KeychainStore.delete(account: "mqtt_password")
        super.tearDown()
    }

    func testWriteThenReadRoundTrips() {
        XCTAssertNil(KeychainStore.read(account: "mqtt_username"))
        XCTAssertTrue(KeychainStore.write(account: "mqtt_username", value: "pi_user"))
        XCTAssertEqual(KeychainStore.read(account: "mqtt_username"), "pi_user")
    }

    func testWriteTwiceUpdatesInPlace() {
        XCTAssertTrue(KeychainStore.write(account: "mqtt_password", value: "first"))
        XCTAssertTrue(KeychainStore.write(account: "mqtt_password", value: "second"))
        XCTAssertEqual(KeychainStore.read(account: "mqtt_password"), "second")
    }

    func testDeleteRemovesValue() {
        XCTAssertTrue(KeychainStore.write(account: "mqtt_username", value: "pi_user"))
        XCTAssertTrue(KeychainStore.delete(account: "mqtt_username"))
        XCTAssertNil(KeychainStore.read(account: "mqtt_username"))
    }

    func testDeleteOfMissingKeyIsNotAnError() {
        XCTAssertTrue(KeychainStore.delete(account: "does_not_exist"))
    }
}
