//
//  MQTTClient.swift
//  ArmbandIOS
//
//  CocoaMQTT wrapper: retained delegate, single-flight connect +
//  connect timeout, batch ACK subscription, live broker update.
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
    
    private var client: AnyObject?
    private var delegateProxy: AnyObject?
    private var isConnecting = false
    private var connectTimeoutTask: Task<Void, Never>?
    
    private(set) var host: String
    private(set) var port: UInt16
    private(set) var clientID: String
    private(set) var username: String?
    private(set) var password: String?
    
    var onReading: ((Reading) -> Void)?
    var onBatchAck: ((String, Int) -> Void)?
    
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
        let changed = host != self.host || port != self.port || username != self.username || password != self.password
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
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            await MainActor.run {
                guard let self, self.isConnecting, !self.isConnected else { return }
                self.isConnecting = false
                self.lastError = "Connect timeout – check Pi IP / network"
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
    }
    
    func publish(topic: String, payload: Data) {
        #if canImport(CocoaMQTT)
        guard let mqtt = client as? CocoaMQTT, isConnected else { return }
        if let str = String(data: payload, encoding: .utf8) {
            mqtt.publish(topic, withString: str, qos: .qos1)
        }
        #endif
    }
    
    fileprivate func handleMessage(topic: String, data: Data) {
        lastMessage = String(data: data, encoding: .utf8)
        if topic == "armband/ppg" || topic.hasSuffix("/ppg") {
            if let reading = Reading.fromFirmwareJSON(data) {
                onReading?(reading)
            }
            return
        }
        if topic == "armband/ios/batch/ack" || topic.hasSuffix("/batch/ack") {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let batchId = json["batch_id"] as? String,
                  (json["status"] as? String) == "ok" else { return }
            let inserted = (json["inserted"] as? Int) ?? 0
            onBatchAck?(batchId, inserted)
        }
    }
    
    fileprivate func handleConnect() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = nil
        isConnected = true
        isConnecting = false
        lastError = nil
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
    }
}

#if canImport(CocoaMQTT)
private final class MQTTDelegateProxy: CocoaMQTTDelegate {
    weak var owner: MQTTClient?
    init(owner: MQTTClient) { self.owner = owner }
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        Task { @MainActor in owner?.handleConnect() }
    }
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        Task { @MainActor in owner?.handleMessage(topic: message.topic, data: Data(message.payload)) }
    }
    func mqtt(_ mqtt: CocoaMQTT, didDisconnectWithError err: Error?) {
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
