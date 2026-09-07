import Foundation

struct MQTTTarget: Equatable {
    var host: String
    var port: UInt16
    var requireAuth: Bool
    var label: String
}

enum MQTTHost {
    static let defaultsKey = "mqtt_host"
    static let wanDefaultsKey = "mqtt_wan_host"
    /// IRIS (Pi 5) on this LAN. Mosquitto + armband-logger live here.
    static let fallback = "192.168.4.27"
    static let legacyFallback = "192.168.1.100"
    /// House WAN. Update in Settings if the ISP IP changes.
    static let wanFallback = "98.23.19.210"
    static let lanPort: UInt16 = 1883
    /// Off-LAN listener on IRIS (password required). UPnP maps this inbound.
    static let wanPort: UInt16 = 41883

    static func load(_ defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty || raw == legacyFallback { return fallback }
        return raw
    }

    static func loadWan(_ defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: wanDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? wanFallback : raw
    }

    /// Empty / whitespace falls back to `fallback`. Returns the stored value.
    @discardableResult
    static func save(_ host: String, defaults: UserDefaults = .standard) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty ? fallback : trimmed
        defaults.set(stored, forKey: defaultsKey)
        return stored
    }

    @discardableResult
    static func saveWan(_ host: String, defaults: UserDefaults = .standard) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = trimmed.isEmpty ? wanFallback : trimmed
        defaults.set(stored, forKey: wanDefaultsKey)
        return stored
    }

    /// Wi-Fi: LAN first (anonymous ok), then cellular host. Cellular-only: WAN.
    /// Unknown path (both false at launch): LAN then WAN.
    static func targets(wifi: Bool, cellular: Bool = false, defaults: UserDefaults = .standard) -> [MQTTTarget] {
        let lan = MQTTTarget(host: load(defaults), port: lanPort, requireAuth: false, label: "LAN")
        let wan = MQTTTarget(host: loadWan(defaults), port: wanPort, requireAuth: true, label: "cellular")
        if cellular && !wifi { return [wan] }
        return [lan, wan]
    }
}
