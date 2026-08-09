//
//  SyncEngine.swift
//  ArmbandIOS
//
//  Pushes unsynced batches to the Raspberry Pi.
//  Only marks records synced after Pi ACK with inserted == count.
//  Includes reading IDs for Pi-side idempotency (INSERT OR IGNORE).
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
    private let batchLimit = 300
    private let ackTimeoutNs: UInt64 = 15_000_000_000
    
    private var pendingAcks: [String: [UUID]] = [:]
    private var ackWaiters: [String: CheckedContinuation<Bool, Never>] = [:]
    private var ackTimeoutTasks: [String: Task<Void, Never>] = [:]
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
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
        
        guard let mqtt, mqtt.isConnected else {
            lastError = "Pi not reachable (MQTT disconnected)"
            isSyncing = false
            return
        }
        
        var totalInserted = 0
        while true {
            let batch = store.unsyncedBatch(limit: batchLimit)
            guard !batch.isEmpty else { break }
            
            let ok = await sendOneBatch(batch, mqtt: mqtt)
            if !ok { break }
            totalInserted += batch.count
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        
        if totalInserted > 0 {
            lastBatchCount = totalInserted
            lastSyncTime = Date()
        }
        isSyncing = false
    }
    
    private func sendOneBatch(_ batch: [Reading], mqtt: MQTTClient) async -> Bool {
        let batchId = UUID().uuidString
        let ids = batch.map(\.id)
        
        var payload: [String: Any] = [
            "source": "ios",
            "device_id": UUID().uuidString,
            "batch_id": batchId,
            "count": batch.count,
            "readings": batch.map { r -> [String: Any] in
                var dict: [String: Any] = [
                    "id": r.id.uuidString,
                    "ts": Self.isoFormatter.string(from: r.timestamp),
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
        if let sid = store.currentSessionId {
            payload["session_id"] = sid.uuidString
        }
        
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            lastError = error.localizedDescription
            return false
        }
        
        pendingAcks[batchId] = ids
        
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.ackWaiters[batchId] = cont
            
            self.ackTimeoutTasks[batchId] = Task { [weak self] in
                try? await Task.sleep(nanoseconds: self?.ackTimeoutNs ?? 15_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    if self.pendingAcks.removeValue(forKey: batchId) != nil {
                        self.ackTimeoutTasks.removeValue(forKey: batchId)
                        if let waiter = self.ackWaiters.removeValue(forKey: batchId) {
                            self.lastError = "No ACK from Pi within 15s – data kept pending"
                            waiter.resume(returning: false)
                        }
                    }
                }
            }
            
            mqtt.publish(topic: self.batchTopic, payload: data)
        }
        return ok
    }
    
    private func handleAck(batchId: String, inserted: Int) {
        guard let ids = pendingAcks[batchId] else { return }
        
        ackTimeoutTasks[batchId]?.cancel()
        ackTimeoutTasks.removeValue(forKey: batchId)
        
        guard inserted == ids.count else {
            lastError = "Partial insert: \(inserted)/\(ids.count) — kept pending"
            pendingAcks.removeValue(forKey: batchId)
            if let waiter = ackWaiters.removeValue(forKey: batchId) {
                waiter.resume(returning: false)
            }
            return
        }
        
        pendingAcks.removeValue(forKey: batchId)
        store.markSynced(ids: ids)
        lastError = nil
        print("[SyncEngine] ACK batch \(batchId.prefix(8))… inserted=\(inserted)")
        
        if let waiter = ackWaiters.removeValue(forKey: batchId) {
            waiter.resume(returning: true)
        }
    }
}
