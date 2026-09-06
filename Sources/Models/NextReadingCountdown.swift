import Foundation

/// Firmware `PERIODIC_WAKE_US` is 180s. Quiet-skip can delay MQTT, so
/// "due now" is honest until the next packet arrives.
enum NextReadingCountdown {
    static let interval: TimeInterval = 180

    static func remaining(lastReading: Date?, now: Date = Date()) -> TimeInterval? {
        guard let lastReading else { return nil }
        return lastReading.addingTimeInterval(interval).timeIntervalSince(now)
    }

    /// Display value + unit for the dashboard card.
    static func display(lastReading: Date?, now: Date = Date()) -> (value: String, unit: String) {
        guard let remaining = remaining(lastReading: lastReading, now: now) else {
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
