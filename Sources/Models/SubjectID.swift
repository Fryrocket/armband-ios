//
//  SubjectID.swift
//  ArmbandIOS
//
//  Closed Subject_ID enum (schema freeze 2026-08-12). Two-person pilot:
//  SUBJ_A (S001 default) and SUBJ_B. Free-text is refused so dump cannot
//  invent a third subject. Persistence is UserDefaults, not Keychain —
//  this is a label, not a credential.
//

import Foundation

enum SubjectID: String, CaseIterable, Identifiable, Equatable {
    case subjA = "SUBJ_A"
    case subjB = "SUBJ_B"

    var id: String { rawValue }

    static let defaultsKey = "subject_id"

    static func parse(_ raw: String?) -> SubjectID? {
        guard let raw, !raw.isEmpty else { return nil }
        return SubjectID(rawValue: raw)
    }
}
