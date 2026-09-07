import Foundation

/// Firmware `PERIODIC_WAKE_US` is 180s. Bench-mode BLE can notify ~1.5s; those
/// packets must not restart this countdown. Display is m:ss over that 3-min window.
enum NextReadingCountdown {
    static let interval: TimeInterval = 180

    /// Keep the current 3-min window until it has fully elapsed.
    static func cadenceAnchor(previous: Date?, incoming: Date) -> Date {
        guard let previous else { return incoming }
        if incoming.timeIntervalSince(previous) >= interval { return incoming }
        return previous
    }

    /// BLE/MQTT can notify ~1.5s in bench mode. Only queue a Pi dump sample
    /// when the 3-min wake interval has elapsed (or this is the first sample).
    static func shouldEnqueueDump(lastDumpAt: Date?, incoming: Date) -> Bool {
        guard let lastDumpAt else { return true }
        return incoming.timeIntervalSince(lastDumpAt) >= interval
    }

    static func remaining(anchor: Date?, now: Date = Date()) -> TimeInterval? {
        guard let anchor else { return nil }
        return anchor.addingTimeInterval(interval).timeIntervalSince(now)
    }

    /// Display value + unit for the dashboard card.
    static func display(anchor: Date?, now: Date = Date()) -> (value: String, unit: String) {
        guard let remaining = remaining(anchor: anchor, now: now) else {
            return ("--", "")
        }
        if remaining <= 0 {
            return ("due", "now")
        }
        let total = Int(ceil(remaining))
        let minutes = total / 60
        let seconds = total % 60
        return (String(format: "%d:%02d", minutes, seconds), "left")
    }
}
