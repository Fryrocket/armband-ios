import XCTest
@testable import ArmbandIOS

final class GlucoseFrom940Tests: XCTestCase {
    func testUncalibratedEstimateIsNil() {
        XCTAssertNil(GlucoseFrom940.estimate(filt940: 1839.2))
        XCTAssertNil(GlucoseFrom940.mgdl(filt940: 1839.2))
        XCTAssertNil(Reading(filt940: 1839.2).estimatedGlucoseMgdl)
    }

    func testMissingOrNonPositive940IsNil() {
        XCTAssertNil(GlucoseFrom940.mgdl(filt940: nil))
        XCTAssertNil(GlucoseFrom940.mgdl(filt940: 0))
        XCTAssertNil(GlucoseFrom940.mgdl(filt940: -1))
        XCTAssertNil(GlucoseFrom940.mgdl(filt940: .nan))
        XCTAssertNil(GlucoseFrom940.mgdl(filt940: .infinity))
    }

    func testDisplayPlaceholderUntilCalibrated() {
        let tick = GlucoseFrom940.display(filt940: 1842)
        XCTAssertEqual(tick.value, "--")
        XCTAssertEqual(tick.unit, "mg/dL")
        XCTAssertEqual(tick.caption, "from 940 later")
    }

    func testDisplayKeepsLiveSlotEmptyWhenOnlyAReferenceExists() {
        let ref = GlucoseRef(kind: .libre, mgdl: 102)
        let tick = GlucoseFrom940.display(filt940: 1842, lastRef: ref)
        XCTAssertEqual(tick.value, "--")
        XCTAssertEqual(tick.unit, "mg/dL")
        XCTAssertEqual(tick.caption, "Libre 102 · 940 later")
    }

    func testFingerRefCaption() {
        let ref = GlucoseRef(kind: .fingerstick, mgdl: 88.5)
        let tick = GlucoseFrom940.display(filt940: nil, lastRef: ref)
        XCTAssertEqual(tick.value, "--")
        XCTAssertEqual(tick.caption, "Finger 88.5 · 940 later")
    }

    func testFirmwareJSONDoesNotInventGlucose() {
        let data = #"{"temp":33.4,"motion":0,"moving":false,"raw940":1842,"filt940":1839.2,"batt":3.7}"#.data(using: .utf8)!
        let reading = Reading.fromFirmwareJSON(data)
        XCTAssertEqual(reading?.filt940 ?? -1, 1839.2, accuracy: 0.01)
        XCTAssertNil(reading?.estimatedGlucoseMgdl)
    }
}
