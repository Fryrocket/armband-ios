import XCTest
@testable import ArmbandIOS

final class MQTTHostTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.fryrocket.armbandios.mqtthost.test")
        defaults.removePersistentDomain(forName: "com.fryrocket.armbandios.mqtthost.test")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "com.fryrocket.armbandios.mqtthost.test")
        super.tearDown()
    }

    func testLoadFallsBackWhenMissing() {
        XCTAssertEqual(MQTTHost.load(defaults), "192.168.1.100")
    }

    func testSaveRoundTrips() {
        XCTAssertEqual(MQTTHost.save("10.0.0.5", defaults: defaults), "10.0.0.5")
        XCTAssertEqual(MQTTHost.load(defaults), "10.0.0.5")
    }

    func testEmptySaveUsesFallback() {
        _ = MQTTHost.save("10.0.0.5", defaults: defaults)
        XCTAssertEqual(MQTTHost.save("   ", defaults: defaults), "192.168.1.100")
        XCTAssertEqual(MQTTHost.load(defaults), "192.168.1.100")
    }

    func testDefaultsKey() {
        XCTAssertEqual(MQTTHost.defaultsKey, "mqtt_host")
    }
}
