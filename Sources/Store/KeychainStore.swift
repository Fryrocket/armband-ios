//
//  KeychainStore.swift
//  ArmbandIOS
//
//  Minimal generic-password Keychain wrapper for MQTT broker credentials.
//  Free functions (not an ObservableObject) — needed before any SwiftUI
//  environment exists, in ArmbandIOSApp.init().
//
//  kSecAttrAccessibleAfterFirstUnlock (not WhenUnlocked) so SyncEngine /
//  MQTTClient can reconnect from a background task after the device is locked
//  (matches autoReconnect = true / persistent-session in MQTTClient.connect()).
//

import Foundation
import Security

enum KeychainStore {
    static var service = "com.fryrocket.armbandios.mqtt"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return updateStatus == errSecSuccess
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// One-time migration: plaintext UserDefaults credentials move into the
    /// Keychain and are removed from the .plist only after a successful write.
    /// Safe to run every launch — no-op once migrated.
    static func migrateLegacyUserDefaults(_ defaults: UserDefaults = .standard) {
        for account in ["mqtt_username", "mqtt_password"] {
            guard let legacy = defaults.string(forKey: account) else { continue }
            if write(account: account, value: legacy) {
                defaults.removeObject(forKey: account)
            }
        }
    }
}
