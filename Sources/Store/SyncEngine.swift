//
//  SyncEngine.swift
//  ArmbandIOS
//
//  Pushes unsynced batches to the Raspberry Pi.
//  Only marks records synced after Pi publishes ACK on armband/ios/batch/ack.
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
    
    /// batch_id → reading IDs waiting for ACK
    private var pendingAcks: [String: [UUID]] = [:]
    private var ackTimeoutTasks: [String: Task<Void, Never>] = [:]
    
    init(store: ReadingStore, mqtt: MQTTClient? = nil) {
        self.store = store
        self.mqtt = mqtt
        
        mqtt?.onBatchAck = { [weak self] batchId, inserted in
            Task { @MainActor in
                self?.handleAck(batchId: batchId, inserted: inserted)
            }
        }
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
        
        guard let mqtt, mqtt.isConnected else {
            lastError = "Pi not reachable (MQTT disconnected)"
            isSyncing = false
            return
        }
        
        lastBatchCount = batch.count
        let batchId = UUID().uuidString
        let ids = batch.map { $0.id }
        
        let payload: [String: Any] = [
            "source": "ios",
            "device_id": UUID().uuidString,
            "session_id": store.currentSessionId?.uuidString as Any,
            "batch_id": batchId,
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
            pendingAcks[batchId] = ids
            mqtt.publish(topic: batchTopic, payload: data)
            
            // Timeout: if no ACK in 15s, leave records unsynced and report error
            ackTimeoutTasks[batchId] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if pendingAcks[batchId] != nil {
                    pendingAcks.removeValue(forKey: batchId)
                    lastError = "No ACK from Pi within 15s – data kept pending"
                    isSyncing = false
                }
            }
        } catch {
            lastError = error.localizedDescription
            isSyncing = false
        }
    }
    
    private func handleAck(batchId: String, inserted: Int) {
        guard let ids = pendingAcks.removeValue(forKey: batchId) else { return }
        ackTimeoutTasks[batchId]?.cancel()
        ackTimeoutTasks.removeValue(forKey: batchId)
        
        store.markSynced(ids: ids)
        lastSyncTime = Date()
        lastBatchCount = inserted
        lastError = nil
        isSyncing = false
        print("[SyncEngine] ACK batch \(batchId.prefix(8))… inserted=\(inserted)")
    }
}
