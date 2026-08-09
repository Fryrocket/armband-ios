//
//  MQTTClient.swift
//  ArmbandIOS
//
//  CocoaMQTT wrapper: retained delegate, single-flight connect +
//  connect timeout, batch ACK (ok and error), disconnect fails pending.
//
//  Fixes in this pass:
//   - onDisconnect fires exactly once per connection loss. A manual disconnect()
//     used to fire it, then CocoaMQTT's didDisconnectWithError fired it again.
//   - lastMessage is no longer published for the PPG stream, which was one
//     @Published mutation (and one SwiftUI invalidation) per reading.
//   - connect timeout task returns on cancellation instead of relying solely on
//     the isConnecting guard.
//   - the delegate proxy is cleared alongside the old client on reconnect.
//   - Delegate callbacks hoist the weak owner outside Task { @MainActor in ... }
//     so Swift 6 does not treat the non-Sendable proxy as captured.
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

    /// Set to true only while debugging the firmware stream. When false, the
    /// high-rate armband/ppg topic does not touch @Published state.
    var publishesEveryMessage = false

    private var client: AnyObject?
    private var delegateProxy: AnyObject?
    private var isConnecting = false
    private var connectTimeoutTask: Task<Void, Never>?

    /// True when a disconnect has already been reported for the current
    /// connection, so onDisconnect cannot fire twice for one loss.
    private var disconnectSignalled = true

    private(set) var host: String
    private(set) var port: UInt16
    private(set) var clientID: String
    private(set) var username: String?
    private(set) var password: String?

    var onReading: ((Reading) -> Void)?
    /// batchId, inserted count, errorMessage (nil = success)
    var onBatchAck: ((String, Int, String?) -> Void)?
    /// Fired on disconnect so SyncEngine can fail waiting ACKs immediately
    var onDisconnect: (() -> Void)?

    init(
        host: String = "192.168.1.100",
        port: UInt16 = 1883,
        clientID: String = "ios-armband-\(UUID().uuidString.prefix(8))",
        username: String? = nil,
        password: String? = nil
    ) {
        self.host = host
        self.port = port
        self.clientID = clientID
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

    // MARK: - Connection

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
        mqtt.cleanSession = true

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
                return   // cancelled by handleConnect / disconnect
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
        signalDisconnect()
    }

    /// Fires onDisconnect at most once per established connection. CocoaMQTT
    /// will also deliver didDisconnectWithError after a manual disconnect();
    /// without this guard SyncEngine.failAllPending ran twice.
    private func signalDisconnect() {
        guard !disconnectSignalled else { return }
        disconnectSignalled = true
        onDisconnect?()
    }

    /// Returns false if not connected (caller should fail fast, not wait for ACK timeout)
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

    // MARK: - Delegate callbacks

    fileprivate func handleMessage(topic: String, data: Data) {
        // hasSuffix covers both "armband/ppg" and any future ".../ppg"
        if topic.hasSuffix("/ppg") {
            // Hot path: one message per reading. Only touch @Published state
            // when explicitly debugging, otherwise every reading invalidates
            // every view observing this object.
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
            if status == "ok" {
                onBatchAck?(batchId, inserted, nil)
            } else {
                let reason = (json["error"] as? String)
                    ?? (json["message"] as? String)
                    ?? status
                onBatchAck?(batchId, inserted, reason)
            }
        }
    }

    fileprivate func handleConnect() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        isConnected = true
        isConnecting = false
        lastError = nil
        disconnectSignalled = false   // arm the one-shot disconnect notification

        #if canImport(CocoaMQTT)
        guard let mqtt = client as? CocoaMQTT else { return }
        mqtt.subscribe("armband/ppg", qos: .qos1)
        mqtt.subscribe("armband/ios/batch/ack", qos: .qos1)
        #endif
    }

    fileprivate func handleDisconnect(error: Error?) {
        isConnected = false
        isConnecting = false
        if let error { lastError = error.localizedDescription }
        signalDisconnect()
    }
}

#if canImport(CocoaMQTT)
private final class MQTTDelegateProxy: CocoaMQTTDelegate {
    weak var owner: MQTTClient?
    init(owner: MQTTClient) { self.owner = owner }

    // Hoist the weak owner outside the Task so we do not capture the
    // non-Sendable proxy (self) into a @MainActor-isolated closure.
    // MQTTClient is @MainActor and therefore Sendable.
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
