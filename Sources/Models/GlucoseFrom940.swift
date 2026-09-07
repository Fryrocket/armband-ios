import Foundation

/// 940 nm (`filt940`) → glucose mg/dL.
/// Uncalibrated on purpose: Live shows `--` until the model lands. Do not invent a formula here.
enum GlucoseFrom940 {
    struct Display: Equatable {
        var value: String
        var unit: String
        var caption: String
    }

    static func mgdl(filt940: Double?) -> Double? {
        guard let filt940, filt940 > 0, filt940.isFinite else { return nil }
        guard let mgdl = estimate(filt940: filt940), mgdl.isFinite, mgdl > 0, mgdl < 1000 else {
            return nil
        }
        return mgdl
    }

    /// Plug the calibrated 940 → glucose model in here.
    /// Must return nil or a finite (0, 1000) mg/dL. Returning a guess is a bug.
    static func estimate(filt940: Double) -> Double? {
        _ = filt940
        return nil
    }

    static func display(filt940: Double?, lastRef: GlucoseRef? = nil) -> Display {
        if let mgdl = mgdl(filt940: filt940) {
            return Display(value: String(format: "%.0f", mgdl), unit: "mg/dL", caption: "from 940")
        }
        if let lastRef {
            let label = lastRef.kind == .libre ? "Libre" : "Finger"
            return Display(value: "--", unit: "mg/dL", caption: "\(label) \(formatRef(lastRef.mgdl)) · 940 later")
        }
        return Display(value: "--", unit: "mg/dL", caption: "from 940 later")
    }

    private static func formatRef(_ mgdl: Double) -> String {
        if mgdl.rounded() == mgdl {
            return String(format: "%.0f", mgdl)
        }
        return String(format: "%.1f", mgdl)
    }
}
