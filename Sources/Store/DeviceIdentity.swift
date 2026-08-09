//
//  DeviceIdentity.swift
//  ArmbandIOS
//
//  Stable per-install identifier for the phone, stored in UserDefaults next to
//  mqtt_host. Previously SyncEngine sent `UUID().uuidString` as device_id on
//  every batch, so the Pi saw a brand-new device on each publish.
//
//  Note: this resets if the app is deleted and reinstalled. That is the correct
//  trade-off here - it is a logging tag, not an identity claim. If you ever want
//  it to survive reinstall, move it to the Keychain with
//  kSecAttrAccessibleAfterFirstUnlock.
//

import Foundation

enum DeviceIdentity {
    private static let defaultsKey = "device_id"

    /// Created once on first access, then reused for the life of the install.
    static let current: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: defaultsKey)
        return fresh
    }()

    /// Test / support hook - forces a new id on the next access of `current`
    /// in a fresh process. Not needed in normal operation.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
