//
//  SyncEngine.swift
//  ArmbandIOS
//
//  Pushes unsynced batches to the Raspberry Pi.
//  Only marks synced after an ACK that accounts for every id in the batch.
//  Fails fast on disconnect or non-ok ACK (no 15s stall).
//  Cancellation-aware end to end.
//
//  Fixes in this pass (on top of 407a071):
//  - #1 Partial-insert poison batch.
//  - #2 Cancel window before registration.
//  - #3 Cancel after a successful batch no longer discards the sync stamp.
//  - #4 (MQTTClient) onDisconnect carries a reason.
//
//  Fix Pack 3 (2026-08-09 evening):
//  - #5 Cancel affordance. dumpTask retained; startDump() / cancelDump().
//  - #6 Per-reading session_id on the wire.
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

    /// Active dump task. Retained so cancelDump() can reach the internal
    /// cancellation machinery. Cleared when the dump finishes or is cancelled.
    private var dumpTask: Task<Void, Never>?

    private var lastPartialHeadId: UUID?
    private var partialRepeatCount = 0

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(store: ReadingStore, mqtt: MQTTClient? = nil) {
        self.store = store
        self.mqtt = mqtt

        mqtt?.onBatchAck = { [weak self] batchId, inserted, duplicates, errorMessage in
            Task { @MainActor in
                self?.handleAck(
                    batchId: batchId,
                    inserted: inserted,
                    duplicates: duplicates,
                    errorMessage: errorMessage
                )
            }
        }

        mqtt?.onDisconnect = { [weak self] reason in
            Task { @MainActor in
                self?.failAllPending(reason: reason)
            }
        }
    }

    // MARK: - Public dump control

    func startDump() {
        guard !isSyncing, dumpTask == nil else { return }
        dumpTask = Task { [weak self] in
            await self?.dumpToPi()
            await MainActor.run { self?.dumpTask = nil }
        }
    }

    func cancelDump() {
        dumpTask?.cancel()
    }

    // MARK: - Dump loop

    func dumpToPi() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        guard let mqtt, mqtt.isConnected else {
            lastError = "Pi not reachable (MQTT disconnected)"
            return
        }

        var totalSynced = 0
        var previousHeadId: UUID?

        while true {
            if Task.isCancelled {
                failAllPending(reason: nil)
                break
            }

            let batch = store.unsyncedBatch(limit: batchLimit)
            guard !batch.isEmpty else { break }

            if let head = batch.first?.id, head == previousHeadId {
                lastError = "Sync stalled: same batch returned after ACK - store did not mark synced"
                break
            }
            previousHeadId = batch.first?.id

            let ok = await withTaskCancellationHandler {
                await sendOneBatch(batch, mqtt: mqtt)
            } onCancel: { [weak self] in
                Task { @MainActor in
                    self?.failAllPending(reason: nil)
                }
            }

            if ok { totalSynced += batch.count }
            if !ok || Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if totalSynced > 0 {
            lastBatchCount = totalSynced
            lastSyncTime = Date()
        }
    }

    // MARK: - One batch

    private func sendOneBatch(_ batch: [Reading], mqtt: MQTTClient) async -> Bool {
        let batchId = UUID().uuidString
        let ids = batch.map(\.id)

        var payload: [String: Any] = [
            "source": "ios",
            "device_id": DeviceIdentity.current,
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
                if let sid = r.sessionId { dict["session_id"] = sid.uuidString }
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

        guard mqtt.isConnected else {
            lastError = "MQTT disconnected before publish - data kept pending"
            return false
        }

        if Task.isCancelled { return false }

        pendingAcks[batchId] = ids

        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.ackWaiters[batchId] = cont

            if Task.isCancelled {
                self.finishBatch(batchId: batchId, success: false, error: nil)
                return
            }

            self.ackTimeoutTasks[batchId] = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: self?.ackTimeoutNs ?? 15_000_000_000)
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self else { return }
                    self.finishBatch(
                        batchId: batchId,
                        success: false,
                        error: "No ACK from Pi within 15s - data kept pending"
                    )
                }
            }

            let published = mqtt.publish(topic: self.batchTopic, payload: data)
            if !published {
                self.finishBatch(
                    batchId: batchId,
                    success: false,
                    error: "Publish failed (disconnected) - data kept pending"
                )
            }
        }

        return ok
    }

    // MARK: - ACK handling

    private func handleAck(batchId: String, inserted: Int, duplicates: Int, errorMessage: String?) {
        guard isPending(batchId) else { return }

        if let errorMessage {
            finishBatch(batchId: batchId, success: false, error: "Pi error: \(errorMessage)")
            return
        }

        guard let ids = pendingAcks[batchId] else { return }

        let accounted = inserted + duplicates
        guard accounted >= ids.count else {
            noteFailedInsert(head: ids.first)
            let detail = duplicates > 0
                ? "\(inserted) new + \(duplicates) dup / \(ids.count)"
                : "\(inserted)/\(ids.count)"

            if partialRepeatCount >= 2 {
                finishBatch(
                    batchId: batchId,
                    success: false,
                    error: "Sync wedged: same batch partially inserted \(partialRepeatCount)x (\(detail)). The Pi is not reporting ignored duplicates - add `duplicates` to the ACK."
                )
            } else {
                finishBatch(
                    batchId: batchId,
                    success: false,
                    error: "Partial insert: \(detail) - kept pending"
                )
            }
            return
        }

        clearPartialTracking()
        print("[SyncEngine] ACK batch \(batchId.prefix(8))... inserted=\(inserted) dup=\(duplicates)")
        finishBatch(batchId: batchId, success: true, error: nil, markSyncedIds: ids)
    }

    private func noteFailedInsert(head: UUID?) {
        if let head, head == lastPartialHeadId {
            partialRepeatCount += 1
        } else {
            lastPartialHeadId = head
            partialRepeatCount = 1
        }
    }

    private func clearPartialTracking() {
        lastPartialHeadId = nil
        partialRepeatCount = 0
    }

    private func failAllPending(reason: String?) {
        let ids = Array(pendingAcks.keys)
        for batchId in ids {
            finishBatch(batchId: batchId, success: false, error: reason)
        }
    }

    private func isPending(_ batchId: String) -> Bool {
        pendingAcks[batchId] != nil || ackWaiters[batchId] != nil
    }

    private func finishBatch(
        batchId: String,
        success: Bool,
        error: String?,
        markSyncedIds: [UUID]? = nil
    ) {
        guard isPending(batchId) else { return }

        cancelTimeout(batchId)
        pendingAcks.removeValue(forKey: batchId)

        if success, let ids = markSyncedIds {
            store.markSynced(ids: ids)
            lastError = nil
        } else if let error {
            lastError = error
        }

        if let waiter = ackWaiters.removeValue(forKey: batchId) {
            waiter.resume(returning: success)
        }
    }

    private func cancelTimeout(_ batchId: String) {
        ackTimeoutTasks[batchId]?.cancel()
        ackTimeoutTasks.removeValue(forKey: batchId)
    }
}
