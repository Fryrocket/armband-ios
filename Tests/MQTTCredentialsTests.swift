import XCTest
@testable import ArmbandIOS

final class MQTTCredentialsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeychainStore.service = "com.fryrocket.armbandios.mqtt.test"
        _ = KeychainStore.delete(account: MQTTCredentials.usernameAccount)
        _ = KeychainStore.delete(account: MQTTCredentials.passwordAccount)
    }

    override func tearDown() {
        _ = KeychainStore.delete(account: MQTTCredentials.usernameAccount)
        _ = KeychainStore.delete(account: MQTTCredentials.passwordAccount)
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() {
        XCTAssertTrue(MQTTCredentials.save(username: "pi_user", password: "s3cret"))
        let loaded = MQTTCredentials.load()
        XCTAssertEqual(loaded.username, "pi_user")
        XCTAssertEqual(loaded.password, "s3cret")
    }

    func testEmptyPasswordDeletesKeychainItem() {
        XCTAssertTrue(MQTTCredentials.save(username: "pi_user", password: "s3cret"))
        XCTAssertTrue(MQTTCredentials.save(username: "pi_user", password: ""))
        let loaded = MQTTCredentials.load()
        XCTAssertEqual(loaded.username, "pi_user")
        XCTAssertEqual(loaded.password, "")
        XCTAssertNil(KeychainStore.read(account: MQTTCredentials.passwordAccount))
    }

    func testAccountsAreMqttKeys() {
        XCTAssertEqual(MQTTCredentials.usernameAccount, "mqtt_username")
        XCTAssertEqual(MQTTCredentials.passwordAccount, "mqtt_password")
    }
}
