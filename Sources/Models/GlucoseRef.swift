import Foundation

enum GlucoseKind: String, Codable, CaseIterable {
    case libre
    case fingerstick
}

struct GlucoseRef: Identifiable, Codable, Equatable {
    var id: UUID
    var timestamp: Date
    var kind: GlucoseKind
    var mgdl: Double
    var synced: Bool
    var sessionId: UUID?
    var subjectId: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: GlucoseKind,
        mgdl: Double,
        synced: Bool = false,
        sessionId: UUID? = nil,
        subjectId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.mgdl = mgdl
        self.synced = synced
        self.sessionId = sessionId
        self.subjectId = subjectId
    }

    /// Accepts `102`, `102.4`, `102,4`. Rejects empty, non-numeric, and non-positive.
    static func parseMgdl(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value.isFinite, value > 0, value < 1000 else {
            return nil
        }
        return value
    }
}
