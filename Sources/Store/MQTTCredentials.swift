//
//  MQTTCredentials.swift
//  ArmbandIOS
//
//  Settings-facing load/save for MQTT username/password.
//  Keychain only — never the app plist. Empty field deletes the item
//  so a cleared password cannot linger as stale Keychain data.
//

import Foundation

enum MQTTCredentials {
    static let usernameAccount = "mqtt_username"
    static let passwordAccount = "mqtt_password"

    static func load() -> (username: String, password: String) {
        (
            KeychainStore.read(account: usernameAccount) ?? "",
            KeychainStore.read(account: passwordAccount) ?? ""
        )
    }

    /// Persist to Keychain. Empty string deletes that account.
    /// Returns false if either write/delete failed.
    @discardableResult
    static func save(username: String, password: String) -> Bool {
        persist(account: usernameAccount, value: username)
            && persist(account: passwordAccount, value: password)
    }

    private static func persist(account: String, value: String) -> Bool {
        if value.isEmpty {
            return KeychainStore.delete(account: account)
        }
        return KeychainStore.write(account: account, value: value)
    }
}
