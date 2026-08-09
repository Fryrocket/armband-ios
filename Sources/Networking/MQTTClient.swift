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
import Foundation
import Combine
#if canImport(CocoaMQTT)
import CocoaMQTT
#endif

@MainActor
final class MQTTClient: ObservableObject {

    @Published var isConnected = false
    @Published var lastError: String?
    @Published var lastMessage: String?

    var publishesEveryMessage = false

    private var client: AnyObject?
    private var delegateProxy: AnyObject?
    private var isConnecting = false
    private var connectTimeoutTask: Task<Void, Never>?
    private var disconnectSignalled = true

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
        isConnecting = true
        lastError = nil

        #if canImport(CocoaMQTT)
        if let old = client as? CocoaMQTT {
            old.delegate = nil
            old.disconnect()
        }
        delegateProxy = nil

        let mqtt = CocoaMQTT(clientID: clientID, host: host, port: port)
        mqtt.username = username
        mqtt.password = password
        mqtt.keepAlive = 60
        mqtt.autoReconnect = true
        mqtt.cleanSession = false

        let proxy = MQTTDelegateProxy(owner: self)
        self.delegateProxy = proxy
        mqtt.delegate = proxy
        mqtt.connect()
        self.client = mqtt

        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 12_000_000_000)
            } catch {
                return
            }
            await MainActor.run {
                guard let self, self.isConnecting, !self.isConnected else { return }
                self.isConnecting = false
                self.lastError = "Connect timeout - check Pi IP / network"
            }
        }
        #else
        lastError = "CocoaMQTT package not added yet"
        isConnecting = false
        #endif
    }

    func disconnect() {
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
            let inserted = (json["inserted"] as? Int) ?? 0
            let duplicates = (json["duplicates"] as? Int)
                ?? (json["ignored"] as? Int)
                ?? 0

            if status == "ok" {
                onBatchAck?(batchId, inserted, duplicates, nil)
            } else {
                let reason = (json["error"] as? String)
                    ?? (json["message"] as? String)
                    ?? status
                onBatchAck?(batchId, inserted, duplicates, reason)
            }
        }
    }

    fileprivate func handleConnect() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        isConnected = true
        isConnecting = false
        lastError = nil
        disconnectSignalled = false
        #if canImport(CocoaMQTT)
        guard let mqtt = client as? CocoaMQTT else { return }
        mqtt.subscribe("armband/ppg", qos: .qos1)
        mqtt.subscribe("armband/ios/batch/ack", qos: .qos1)
        #endif
    }

    fileprivate func handleDisconnect(error: Error?) {
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
        Task { @MainActor in owner?.handleConnect() }
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let owner = self.owner
        let topic = message.topic
        let data = Data(message.payload)
        Task { @MainActor in owner?.handleMessage(topic: topic, data: data) }
    }

    func mqtt(_ mqtt: CocoaMQTT, didDisconnectWithError err: Error?) {
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
