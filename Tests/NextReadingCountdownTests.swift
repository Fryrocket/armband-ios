import XCTest
@testable import ArmbandIOS

final class NextReadingCountdownTests: XCTestCase {
    func testNoReadingShowsPlaceholder() {
        let d = NextReadingCountdown.display(anchor: nil, now: Date())
        XCTAssertEqual(d.value, "--")
        XCTAssertEqual(d.unit, "")
    }

    func testFreshReadingShowsThreeMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let d = NextReadingCountdown.display(anchor: now, now: now)
        XCTAssertEqual(d.value, "3:00")
        XCTAssertEqual(d.unit, "left")
    }

    func testCountsDownMinutesAndSeconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = now.addingTimeInterval(-60)
        let d = NextReadingCountdown.display(anchor: last, now: now)
        XCTAssertEqual(d.value, "2:00")
        XCTAssertEqual(d.unit, "left")
    }

    func testLastMinuteShowsSeconds() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = now.addingTimeInterval(-150)
        let d = NextReadingCountdown.display(anchor: last, now: now)
        XCTAssertEqual(d.value, "0:30")
        XCTAssertEqual(d.unit, "left")
    }

    func testOverdueShowsDueNow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = now.addingTimeInterval(-200)
        let d = NextReadingCountdown.display(anchor: last, now: now)
        XCTAssertEqual(d.value, "due")
        XCTAssertEqual(d.unit, "now")
    }

    func testIntervalIsFirmwareThreeMinutes() {
        XCTAssertEqual(NextReadingCountdown.interval, 180)
    }

    func testCadenceIgnoresPacketsInsideTheWindow() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let t1 = t0.addingTimeInterval(1.5)
        let t2 = t0.addingTimeInterval(179)
        XCTAssertEqual(NextReadingCountdown.cadenceAnchor(previous: t0, incoming: t1), t0)
        XCTAssertEqual(NextReadingCountdown.cadenceAnchor(previous: t0, incoming: t2), t0)
    }

    func testCadenceAdvancesAfterThreeMinutes() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        let tNext = t0.addingTimeInterval(180)
        XCTAssertEqual(NextReadingCountdown.cadenceAnchor(previous: t0, incoming: tNext), tNext)
    }

    func testDumpEnqueueSkipsBenchNotifySpam() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(NextReadingCountdown.shouldEnqueueDump(lastDumpAt: nil, incoming: t0))
        XCTAssertFalse(NextReadingCountdown.shouldEnqueueDump(lastDumpAt: t0, incoming: t0.addingTimeInterval(1.5)))
        XCTAssertFalse(NextReadingCountdown.shouldEnqueueDump(lastDumpAt: t0, incoming: t0.addingTimeInterval(179)))
        XCTAssertTrue(NextReadingCountdown.shouldEnqueueDump(lastDumpAt: t0, incoming: t0.addingTimeInterval(180)))
    }
}
