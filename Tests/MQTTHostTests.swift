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
        XCTAssertEqual(MQTTHost.load(defaults), "192.168.4.27")
    }

    func testSaveRoundTrips() {
        XCTAssertEqual(MQTTHost.save("10.0.0.5", defaults: defaults), "10.0.0.5")
        XCTAssertEqual(MQTTHost.load(defaults), "10.0.0.5")
    }

    func testEmptySaveUsesFallback() {
        _ = MQTTHost.save("10.0.0.5", defaults: defaults)
        XCTAssertEqual(MQTTHost.save("   ", defaults: defaults), "192.168.4.27")
        XCTAssertEqual(MQTTHost.load(defaults), "192.168.4.27")
    }

    func testDefaultsKey() {
        XCTAssertEqual(MQTTHost.defaultsKey, "mqtt_host")
    }

    func testLegacyDefaultMigratesToIris() {
        defaults.set("192.168.1.100", forKey: MQTTHost.defaultsKey)
        XCTAssertEqual(MQTTHost.load(defaults), "192.168.4.27")
    }

    func testWanFallbackAndSave() {
        XCTAssertEqual(MQTTHost.loadWan(defaults), "98.23.19.210")
        XCTAssertEqual(MQTTHost.saveWan("203.0.113.9", defaults: defaults), "203.0.113.9")
        XCTAssertEqual(MQTTHost.loadWan(defaults), "203.0.113.9")
        XCTAssertEqual(MQTTHost.saveWan("  ", defaults: defaults), "98.23.19.210")
    }

    func testWifiTriesLanThenCellular() {
        let t = MQTTHost.targets(wifi: true, cellular: false, defaults: defaults)
        XCTAssertEqual(t.map(\.label), ["LAN", "cellular"])
        XCTAssertEqual(t[0].port, 1883)
        XCTAssertEqual(t[1].port, 41883)
        XCTAssertFalse(t[0].requireAuth)
        XCTAssertTrue(t[1].requireAuth)
    }

    func testCellularOnlyUsesWan() {
        let t = MQTTHost.targets(wifi: false, cellular: true, defaults: defaults)
        XCTAssertEqual(t.map(\.label), ["cellular"])
        XCTAssertEqual(t[0].port, 41883)
        XCTAssertTrue(t[0].requireAuth)
    }
}
