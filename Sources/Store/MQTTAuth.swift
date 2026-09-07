import Foundation

/// Wire credentials for Mosquitto. Partial Keychain (user without pass) is treated
/// as anonymous so a half-saved Settings form cannot loop "not authorised".
enum MQTTAuth {
    static func wireCredentials(username: String?, password: String?) -> (username: String?, password: String?) {
        let user = username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pass = password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if user.isEmpty || pass.isEmpty { return (nil, nil) }
        return (user, pass)
    }
}
