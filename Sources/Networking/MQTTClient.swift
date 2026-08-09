//
//  MQTTClient.swift
//  ArmbandIOS
//
//  Lightweight MQTT client wrapper.
//  Uses CocoaMQTT (add via Swift Package Manager).
//  https://github.com/emqx/CocoaMQTT
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
    private let host: String
    private let port: UInt16
    private let clientID: String
    private let username: String?
    private let password: String?
    
    /// Called whenever a valid Reading is parsed from the armband topic
    var onReading: ((Reading) -> Void)?
    
    init(
        host: String = "192.168.1.100",
        port: UInt16 = 1883,
        clientID: String = "ios-armband-\(UUID().uuidString.prefix(8))",
        username: String? = "armband",
        password: String? = nil
    ) {
        self.host = host
        self.port = port
        self.clientID = clientID
        self.username = username
        self.password = password
    }
    
    func connect() {
        #if canImport(CocoaMQTT)
        let mqtt = CocoaMQTT(clientID: clientID, host: host, port: port)
        mqtt.username = username
        mqtt.password = password
        mqtt.keepAlive = 60
        mqtt.autoReconnect = true
        mqtt.delegate = MQTTDelegateProxy(owner: self)
        mqtt.connect()
        self.client = mqtt
        #else
        print("[MQTT] CocoaMQTT not linked – using stub")
        lastError = "CocoaMQTT package not added yet"
        #endif
    }
    
    func disconnect() {
        #if canImport(CocoaMQTT)
        (client as? CocoaMQTT)?.disconnect()
        #endif
        isConnected = false
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
        }
    }
    
    fileprivate func handleConnect() {
        isConnected = true
        lastError = nil
        #if canImport(CocoaMQTT)
        (client as? CocoaMQTT)?.subscribe("armband/ppg", qos: .qos1)
        #endif
    }
    
    fileprivate func handleDisconnect(error: Error?) {
        isConnected = false
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
        let data = Data(message.payload)
        Task { @MainActor in owner?.handleMessage(topic: message.topic, data: data) }
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
