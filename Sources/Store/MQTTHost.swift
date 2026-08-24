//
//  MQTTHost.swift
//  ArmbandIOS
//
//  Broker host is not a secret. Persist in UserDefaults (`mqtt_host`).
//  Credentials stay in Keychain via MQTTCredentials.
//

import Foundation

enum MQTTHost {
    static let defaultsKey = "mqtt_host"
    static let fallback = "192.168.1.100"

    static func load(_ defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? fallback : raw
    }

    /// Empty / whitespace falls back to `fallback`. Returns the stored value.
    @discardableResult
    static func save(_ host: String, defaults: UserDefaults = .standard) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty ? fallback : trimmed
        defaults.set(stored, forKey: defaultsKey)
        return stored
    }
}
