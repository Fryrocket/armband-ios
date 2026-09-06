import XCTest
@testable import ArmbandIOS

final class TemperatureTests: XCTestCase {
    func testFahrenheitFromCelsius() {
        XCTAssertEqual(Reading(temperature: 0).temperatureFahrenheit ?? -1, 32, accuracy: 0.01)
        XCTAssertEqual(Reading(temperature: 100).temperatureFahrenheit ?? -1, 212, accuracy: 0.01)
        XCTAssertEqual(Reading(temperature: 36.5).temperatureFahrenheit ?? -1, 97.7, accuracy: 0.05)
        XCTAssertEqual(Reading(temperature: 33.4).temperatureFahrenheit ?? -1, 92.12, accuracy: 0.05)
    }

    func testMissingCelsiusHasNoFahrenheit() {
        XCTAssertNil(Reading(temperature: nil).temperatureFahrenheit)
    }

    func testFirmwareJSONTempStaysCelsiusOnTheModel() {
        let data = #"{"temp":33.4,"motion":0,"moving":false,"raw940":0,"filt940":0,"batt":3.7}"#.data(using: .utf8)!
        let reading = Reading.fromFirmwareJSON(data)
        XCTAssertEqual(reading?.temperature ?? -1, 33.4, accuracy: 0.01)
        XCTAssertEqual(reading?.temperatureFahrenheit ?? -1, 92.12, accuracy: 0.05)
    }
}
