//
//  SyncEngine.swift
//  ArmbandIOS
//
//  Pushes unsynced batches to the Raspberry Pi.
//

import Foundation
import Combine

@MainActor
final class SyncEngine: ObservableObject {
    @Published var lastSyncTime: Date?
    @Published var isSyncing = false
    @Published var lastError: String?
    @Published var lastBatchCount: Int = 0
    
    private let store: ReadingStore
    private let mqtt: MQTTClient?
    private let batchTopic = "armband/ios/batch"
    
    init(store: ReadingStore, mqtt: MQTTClient? = nil) {
        self.store = store
        self.mqtt = mqtt
    }
    
    func dumpToPi() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        
        let batch = store.unsyncedBatch(limit: 300)
        guard !batch.isEmpty else {
            isSyncing = false
            return
        }
        
        lastBatchCount = batch.count
        
        let payload: [String: Any] = [
            "source": "ios",
            "device_id": UUID().uuidString,
            "session_id": store.currentSessionId?.uuidString as Any,
            "batch_id": UUID().uuidString,
            "count": batch.count,
            "readings": batch.map { r -> [String: Any] in
                var dict: [String: Any] = [
                    "ts": ISO8601DateFormatter().string(from: r.timestamp),
                    "motion": r.motion,
                    "moving": r.isMoving,
                    "raw940": r.raw940,
                    "filt940": r.filt940,
                    "batt": r.batteryVoltage,
                    "trans": r.transition
                ]
                if let bpm = r.bpm { dict["bpm"] = bpm }
                if let spo2 = r.spo2 { dict["spo2"] = spo2 }
                if let temp = r.temperature { dict["temp"] = temp }
                return dict
            }
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            
            if let mqtt, mqtt.isConnected {
                mqtt.publish(topic: batchTopic, payload: data)
                try await Task.sleep(nanoseconds: 400_000_000)
                store.markSynced(ids: batch.map { $0.id })
                lastSyncTime = Date()
            } else {
                if let str = String(data: data, encoding: .utf8) {
                    print("[SyncEngine] Pi not reachable via MQTT. Batch ready:\n\(str.prefix(400))...")
                }
                lastError = "Pi not reachable (MQTT disconnected)"
            }
        } catch {
            lastError = error.localizedDescription
        }
        
        isSyncing = false
    }
}
