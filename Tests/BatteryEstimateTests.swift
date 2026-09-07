import XCTest
@testable import ArmbandIOS

final class BatteryEstimateTests: XCTestCase {
    func testFullAndEmptyPercents() {
        XCTAssertEqual(BatteryEstimate.percent(volts: 4.20) ?? -1, 100, accuracy: 0.01)
        XCTAssertEqual(BatteryEstimate.percent(volts: 4.35) ?? -1, 100, accuracy: 0.01)
        XCTAssertEqual(BatteryEstimate.percent(volts: 3.30) ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(BatteryEstimate.percent(volts: 3.10) ?? -1, 0, accuracy: 0.01)
    }

    func testMidCurveIsAboutHalf() {
        XCTAssertEqual(BatteryEstimate.percent(volts: 3.82) ?? -1, 50, accuracy: 0.5)
    }

    func testMissingVoltage() {
        XCTAssertNil(BatteryEstimate.percent(volts: nil))
        XCTAssertNil(BatteryEstimate.percent(volts: 0))
        XCTAssertNil(BatteryEstimate.percent(volts: -1))
        XCTAssertNil(BatteryEstimate.remaining(volts: nil))
    }

    func testFullChargeTimeMatchesPackAndDraw() {
        let seconds = BatteryEstimate.remaining(volts: 4.20) ?? -1
        let expected = (500.0 / 3.0) * 3600
        XCTAssertEqual(seconds, expected, accuracy: 1)
        XCTAssertEqual(BatteryEstimate.formatTime(expected), "6d 22h")
    }

    func testEmptyHasNoTimeLeft() {
        XCTAssertEqual(BatteryEstimate.remaining(volts: 3.30) ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(BatteryEstimate.formatTime(0), "empty")
    }

    func testDisplayKeepsVoltsAndAddsLevelAndTime() {
        let tick = BatteryEstimate.display(volts: 4.20)
        XCTAssertEqual(tick.volts, "4.20")
        XCTAssertEqual(tick.unit, "V")
        XCTAssertEqual(tick.detail, "100% · 6d 22h left")
    }

    func testDisplayPlaceholderWithoutReading() {
        let tick = BatteryEstimate.display(volts: nil)
        XCTAssertEqual(tick.volts, "--")
        XCTAssertEqual(tick.unit, "V")
        XCTAssertEqual(tick.detail, "level · time later")
    }

    func testFirmwareJSONBattIsVoltsNotPercent() {
        let data = #"{"temp":33.4,"motion":0,"moving":false,"raw940":0,"filt940":0,"batt":3.70}"#.data(using: .utf8)!
        let reading = Reading.fromFirmwareJSON(data)
        XCTAssertEqual(reading?.batteryVoltage ?? -1, 3.70, accuracy: 0.01)
        XCTAssertEqual(BatteryEstimate.percent(volts: reading?.batteryVoltage) ?? -1, 20, accuracy: 0.5)
    }
}
