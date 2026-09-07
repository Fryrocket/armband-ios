//
//  MQTTClient.swift
//  ArmbandIOS
//
//  CocoaMQTT wrapper: retained delegate, single-flight connect +
//  connect timeout, batch ACK (ok and error), disconnect settles pending.
//
//  Fixes in this pass (on top of 407a071):
//  - #1 The batch ACK now forwards `duplicates` alongside `inserted`.
//  - #4 onDisconnect carries a reason; nil means we asked for the disconnect.
//
//  Fix Pack 3:
//  - cleanSession = false now that clientID is stable via DeviceIdentity.
//
//  Fix Pack 3.1:
//  - Subscribe armband/ppg at QoS 0. Persistent session + QoS 1 queued offline
//    readings and the phone stamped them at receipt (firmware has no RTC).
//    Batch ACK stays at QoS 1 so dump ACKs still survive reconnects.
//
import Foundation
import Combine
#if canImport(CocoaMQTT)
import CocoaMQTT
#endif

@MainActor
final class MQTTClient: ObservableObject {

    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var lastError: String?
    @Published var lastMessage: String?
    @Published private(set) var viaLabel = ""

    var publishesEveryMessage = false

    private var client: AnyObject?
    private var delegateProxy: AnyObject?
    private var connectTimeoutTask: Task<Void, Never>?
    private var disconnectSignalled = true
    private var targets: [MQTTTarget] = []
    private var targetIndex = 0
    private var failoverEnabled = false

    private(set) var host: String
    private(set) var port: UInt16
    private(set) var clientID: String
    private(set) var username: String?
    private(set) var password: String?

    var onReading: ((Reading) -> Void)?
    var onBatchAck: ((String, Int, Int, String?) -> Void)?
    var onDisconnect: ((String?) -> Void)?

    init(
        host: String = "192.168.1.100",
        port: UInt16 = 1883,
        clientID: String? = nil,
        username: String? = nil,
        password: String? = nil
    ) {
        self.host = host
        self.port = port
        if let clientID, !clientID.isEmpty {
            self.clientID = clientID
        } else {
            let stable = DeviceIdentity.current
            self.clientID = "ios-armband-\(stable.prefix(8))"
        }
        self.username = username
        self.password = password
    }

    func updateBroker(host: String, port: UInt16 = 1883, username: String? = nil, password: String? = nil) {
        let changed = host != self.host || port != self.port
            || username != self.username || password != self.password
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        if changed {
            disconnect()
            connect()
        }
    }

    func connect() {
        guard !isConnected && !isConnecting else { return }
        failoverEnabled = true
        let path = NetworkPath.shared
        targets = MQTTHost.targets(wifi: path.isWifi, cellular: path.isCellular)
        targetIndex = 0
        isConnecting = true
        startCurrentTarget()
    }

    private func startCurrentTarget() {
        guard failoverEnabled else { return }
        guard targetIndex < targets.count else {
            isConnecting = false
            if lastError == nil || lastError?.hasPrefix("Connecting") == true || lastError?.hasPrefix("Timeout") == true {
                lastError = "Could not reach IRIS on LAN or cellular. Off-LAN needs MQTT user/pass in Settings."
            }
            return
        }
        let t = targets[targetIndex]
        host = t.host
        port = t.port
        viaLabel = t.label
        lastError = "Connecting to \(t.host):\(t.port) (\(t.label))…"

        var creds = MQTTAuth.wireCredentials(username: username, password: password)
        if t.requireAuth, creds.username == nil || creds.password == nil {
            lastError = "Off-LAN dump needs MQTT user/pass in Settings"
            targetIndex += 1
            startCurrentTarget()
            return
        }
        if !t.requireAuth {
            // House LAN allows anonymous. Don't send a stale Keychain login.
            creds = (nil, nil)
        }

        #if canImport(CocoaMQTT)
        if let old = client as? CocoaMQTT {
            old.delegate = nil
            old.disconnect()
        }
        delegateProxy = nil

        let mqtt = CocoaMQTT(clientID: clientID, host: t.host, port: t.port)
        mqtt.username = creds.username
        mqtt.password = creds.password
        mqtt.keepAlive = 60
        mqtt.autoReconnect = false
        mqtt.cleanSession = true
        mqtt.enableSSL = false

        let proxy = MQTTDelegateProxy(owner: self)
        self.delegateProxy = proxy
        mqtt.delegate = proxy
        self.client = mqtt
        let started = mqtt.connect()
        if !started {
            lastError = "MQTT socket failed to start (\(t.host):\(t.port))"
            targetIndex += 1
            startCurrentTarget()
            return
        }

        connectTimeoutTask?.cancel()
        let ns: UInt64 = targetIndex < targets.count - 1 ? 4_000_000_000 : 12_000_000_000
        connectTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: ns)
            } catch {
                return
            }
            await MainActor.run {
                guard let self, self.failoverEnabled, self.isConnecting, !self.isConnected else { return }
                self.lastError = "Timeout \(t.host):\(t.port) (\(t.label))"
                self.targetIndex += 1
                self.startCurrentTarget()
            }
        }
        #else
        lastError = "CocoaMQTT package not added yet"
        isConnecting = false
        #endif
    }

    private func failOverAfterConnectFailure() {
        guard failoverEnabled, isConnecting, !isConnected else { return }
        connectTimeoutTask?.cancel()
        targetIndex += 1
        startCurrentTarget()
    }

    func disconnect() {
        failoverEnabled = false
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        #if canImport(CocoaMQTT)
        (client as? CocoaMQTT)?.disconnect()
        #endif
        isConnected = false
        isConnecting = false
        signalDisconnect(reason: nil)
    }

    private func signalDisconnect(reason: String?) {
        guard !disconnectSignalled else { return }
        disconnectSignalled = true
        onDisconnect?(reason)
    }

    @discardableResult
    func publish(topic: String, payload: Data) -> Bool {
        #if canImport(CocoaMQTT)
        guard let mqtt = client as? CocoaMQTT, isConnected else { return false }
        if let str = String(data: payload, encoding: .utf8) {
            mqtt.publish(topic, withString: str, qos: .qos1)
            return true
        }
        return false
        #else
        return false
        #endif
    }

    fileprivate func handleMessage(topic: String, data: Data) {
        if topic.hasSuffix("/ppg") {
            if publishesEveryMessage {
                lastMessage = String(data: data, encoding: .utf8)
            }
            if let reading = Reading.fromFirmwareJSON(data) {
                onReading?(reading)
            }
            return
        }

        lastMessage = String(data: data, encoding: .utf8)

        if topic.hasSuffix("/batch/ack") {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let batchId = json["batch_id"] as? String else { return }

            let status = (json["status"] as? String) ?? "ok"
            // JSON numbers often arrive as NSNumber; missing counts: -1 (status ok → full success).
            let inserted = Self.jsonInt(json, "inserted") ?? -1
            let duplicates = Self.jsonInt(json, "duplicates")
                ?? Self.jsonInt(json, "ignored")
                ?? 0

            if status == "ok" {
                onBatchAck?(batchId, inserted, duplicates, nil)
            } else {
                let reason = (json["error"] as? String)
                    ?? (json["message"] as? String)
                    ?? status
                onBatchAck?(batchId, max(inserted, 0), duplicates, reason)
            }
        }
    }

    private static func jsonInt(_ json: [String: Any], _ key: String) -> Int? {
        if let i = json[key] as? Int { return i }
        if let n = json[key] as? NSNumber { return n.intValue }
        if let s = json[key] as? String, let i = Int(s) { return i }
        return nil
    }

    func waitUntilConnected(timeout: TimeInterval = 20) async -> Bool {
        if isConnected { return true }
        connect()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isConnected { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return isConnected
    }

    #if canImport(CocoaMQTT)
    fileprivate func handleConnectAck(_ ack: CocoaMQTTConnAck) {
        guard ack == .accept else {
            lastError = Self.ackError(ack)
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            failOverAfterConnectFailure()
            return
        }
        handleConnect()
    }

    private static func ackError(_ ack: CocoaMQTTConnAck) -> String {
        switch ack {
        case .badUsernameOrPassword, .notAuthorized:
            return "MQTT login failed — save user/pass in Settings, or leave both blank on this LAN"
        case .serverUnavailable:
            return "MQTT broker unavailable"
        case .identifierRejected:
            return "MQTT client id rejected"
        default:
            return "MQTT connect refused (\(ack))"
        }
    }
    #endif

    fileprivate func handleConnect() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        isConnected = true
        isConnecting = false
        lastError = nil
        disconnectSignalled = false
        #if canImport(CocoaMQTT)
        guard let mqtt = client as? CocoaMQTT else { return }
        // QoS 0 on live PPG: no offline queue → no backlog stamped at reconnect time.
        // Firmware has no RTC; phone uses Date() on receipt. QoS 1 would lie about time.
        mqtt.subscribe("armband/ppg", qos: .qos0)
        // QoS 1 on batch ACK: dump settlement must survive brief reconnects.
        mqtt.subscribe("armband/ios/batch/ack", qos: .qos1)
        mqtt.autoReconnect = true
        #endif
    }

    fileprivate func handleDisconnect(error: Error?) {
        if failoverEnabled, isConnecting, !isConnected {
            failOverAfterConnectFailure()
            return
        }
        isConnected = false
        isConnecting = false

        let reason: String?
        if let error, !disconnectSignalled {
            lastError = error.localizedDescription
            reason = error.localizedDescription
        } else {
            reason = disconnectSignalled ? nil : "MQTT disconnected - data kept pending"
        }

        signalDisconnect(reason: reason)
    }
}

#if canImport(CocoaMQTT)
private final class MQTTDelegateProxy: CocoaMQTTDelegate {
    weak var owner: MQTTClient?
    init(owner: MQTTClient) { self.owner = owner }

    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        let owner = self.owner
        Task { @MainActor in owner?.handleConnectAck(ack) }
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let owner = self.owner
        let topic = message.topic
        let data = Data(message.payload)
        Task { @MainActor in owner?.handleMessage(topic: topic, data: data) }
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        let owner = self.owner
        Task { @MainActor in owner?.handleDisconnect(error: err) }
    }

    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}
#endif
