import XCTest
@testable import ArmbandIOS

final class NextReadingCountdownTests: XCTestCase {
    func testNoReadingShowsPlaceholder() {
        let d = NextReadingCountdown.display(lastReading: nil, now: Date())
        XCTAssertEqual(d.value, "--")
        XCTAssertEqual(d.unit, "")
    }

    func testCountsDownTowardDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = now.addingTimeInterval(-60)
        let d = NextReadingCountdown.display(lastReading: last, now: now)
        XCTAssertEqual(d.value, "2:00")
        XCTAssertEqual(d.unit, "left")
    }

    func testOverdueShowsDueNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = now.addingTimeInterval(-200)
        let d = NextReadingCountdown.display(lastReading: last, now: now)
        XCTAssertEqual(d.value, "due")
        XCTAssertEqual(d.unit, "now")
    }

    func testIntervalIsFirmwareThreeMinutes() {
        XCTAssertEqual(NextReadingCountdown.interval, 180)
    }
}
