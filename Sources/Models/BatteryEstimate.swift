import Foundation

/// 1S LiPo gauge from firmware `batt` volts. Display-only; dump JSON stays volts.
/// Pack is the Liter 3.7 V 500 mAh (502535) in firmware README. Time-left uses a
/// conservative average draw until INA219 exists — not a measured current.
enum BatteryEstimate {
    static let capacityMah: Double = 500
    /// ~3 min wake, BLE, PPG burst, deep sleep. Replace when current is measured.
    static let averageDrawMa: Double = 3.0
    static let fullVolts: Double = 4.20
    static let emptyVolts: Double = 3.30

    /// Resting 1S LiPo OCV → SOC. Interpolated between points.
    static let curve: [(volts: Double, percent: Double)] = [
        (4.20, 100),
        (4.06, 90),
        (3.98, 80),
        (3.92, 70),
        (3.87, 60),
        (3.82, 50),
        (3.79, 40),
        (3.75, 30),
        (3.70, 20),
        (3.64, 10),
        (3.45, 5),
        (3.30, 0),
    ]

    struct Display: Equatable {
        var volts: String
        var unit: String
        var detail: String
    }

    static func percent(volts: Double?) -> Double? {
        guard let volts, volts > 0, volts.isFinite else { return nil }
        if volts >= fullVolts { return 100 }
        if volts <= emptyVolts { return 0 }
        for i in 0..<(curve.count - 1) {
            let hi = curve[i]
            let lo = curve[i + 1]
            if volts <= hi.volts && volts >= lo.volts {
                let span = hi.volts - lo.volts
                guard span > 0 else { return lo.percent }
                let t = (volts - lo.volts) / span
                return lo.percent + t * (hi.percent - lo.percent)
            }
        }
        return nil
    }

    static func remaining(volts: Double?) -> TimeInterval? {
        guard let percent = percent(volts: volts), averageDrawMa > 0 else { return nil }
        let hours = (capacityMah * (percent / 100.0)) / averageDrawMa
        return max(0, hours * 3600)
    }

    static func display(volts: Double?) -> Display {
        guard let volts, volts > 0, volts.isFinite else {
            return Display(volts: "--", unit: "V", detail: "level · time later")
        }
        let voltText = String(format: "%.2f", volts)
        guard let percent = percent(volts: volts), let seconds = remaining(volts: volts) else {
            return Display(volts: voltText, unit: "V", detail: "--")
        }
        let pct = Int(percent.rounded())
        return Display(volts: voltText, unit: "V", detail: "\(pct)% · \(formatTime(seconds)) left")
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "empty" }
        let totalMin = Int((seconds / 60.0).rounded())
        let days = totalMin / (60 * 24)
        let hours = (totalMin % (60 * 24)) / 60
        let mins = totalMin % 60
        if days >= 1 { return "\(days)d \(hours)h" }
        if hours >= 1 { return "\(hours)h" }
        if mins >= 1 { return "\(mins)m" }
        return "low"
    }
}
