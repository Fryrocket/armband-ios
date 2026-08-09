//
//  SyncEngine.swift
//  ArmbandIOS
//
//  Pushes unsynced batches to the Raspberry Pi.
//  Only marks synced after ACK with inserted == count.
//  Fails fast on disconnect or non-ok ACK (no 15s stall).
//  Cancellation-aware: withTaskCancellationHandler settles in-flight batches
//  immediately so isSyncing cannot stick true for up to 15 s.
//
//  Fixes in this pass:
//   - ACK timeout task no longer fires after cancellation (try? swallowed the
//     CancellationError and ran the timeout body anyway, clobbering lastError
//     with "No ACK ... within 15s" after every *successful* batch).
//   - finishBatch is idempotent: a stale or duplicate resolution for a batch
//     that is already settled is ignored instead of overwriting lastError.
//   - device_id is stable per install (was a fresh UUID on every batch).
//   - dumpToPi cannot spin forever if markSynced ever fails to shrink the
//     unsynced set.
//   - Success path goes through finishBatch (single settlement path).
//   - dumpToPi is cancellation-aware via withTaskCancellationHandler +
//     Task.isCancelled at the top of the loop; defer guarantees isSyncing
//     is cleared on every exit path.
//   - failAllPending(reason: nil) settles without writing a red error
//     (user-initiated cancel).
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

        mqtt?.onBatchAck = { [weak self] batchId, inserted, errorMessage in
            Task { @MainActor in
                self?.handleAck(batchId: batchId, inserted: inserted, errorMessage: errorMessage)
            }
        }
        mqtt?.onDisconnect = { [weak self] in
            Task { @MainActor in
                self?.failAllPending(reason: "MQTT disconnected - data kept pending")
            }
        }
    }

    // MARK: - Dump loop

    func dumpToPi() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        // Guarantees isSyncing is cleared on every exit path (early return,
        // cancel, or normal completion). Without this a cancel that races
        // with an early return can leave the flag stuck true.
        defer { isSyncing = false }

        guard let mqtt, mqtt.isConnected else {
            lastError = "Pi not reachable (MQTT disconnected)"
            return
        }

        var totalSynced = 0
        // Guard against an unsynced set that never shrinks (markSynced no-op,
        // store write failure, ...). Without this the loop spins at 20 Hz forever.
        var previousHeadId: UUID?

        while true {
            // Check at the top of the loop so a cancel that arrives between
            // batches (or between unsyncedBatch and sendOneBatch) exits
            // immediately instead of starting another full batch.
            if Task.isCancelled {
                failAllPending(reason: nil)   // settle without writing a red error
                break
            }

            let batch = store.unsyncedBatch(limit: batchLimit)
            guard !batch.isEmpty else { break }

            if let head = batch.first?.id, head == previousHeadId {
                lastError = "Sync stalled: same batch returned after ACK - store did not mark synced"
                break
            }
            previousHeadId = batch.first?.id

            // Make the suspension point inside sendOneBatch cancellation-aware.
            // If the parent task is cancelled while we are waiting on the
            // CheckedContinuation, onCancel fires and we settle every pending
            // batch immediately instead of waiting up to 15 s for the timeout.
            let ok = await withTaskCancellationHandler {
                await sendOneBatch(batch, mqtt: mqtt)
            } onCancel: { [weak self] in
                Task { @MainActor in
                    self?.failAllPending(reason: nil)
                }
            }
            if !ok || Task.isCancelled { break }

            totalSynced += batch.count
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
            "device_id": DeviceIdentity.current,   // stable per install
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

        // Fail immediately if publish cannot go out - do not wait 15s for ACK
        guard mqtt.isConnected else {
            lastError = "MQTT disconnected before publish - data kept pending"
            return false
        }

        pendingAcks[batchId] = ids

        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.ackWaiters[batchId] = cont

            self.ackTimeoutTasks[batchId] = Task { [weak self] in
                // Do NOT use `try?` here: it swallows the CancellationError and
                // lets the timeout body run immediately after cancelTimeout(),
                // which then overwrites lastError on the success path.
                do {
                    try await Task.sleep(nanoseconds: self?.ackTimeoutNs ?? 15_000_000_000)
                } catch {
                    return   // cancelled - batch already settled
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
                // Resume immediately - no ACK will arrive
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

    private func handleAck(batchId: String, inserted: Int, errorMessage: String?) {
        // Ignore ACKs for batches we are no longer waiting on (late ACK after a
        // timeout, duplicate ACK, ACK for a previous app run).
        guard isPending(batchId) else { return }

        if let errorMessage {
            finishBatch(batchId: batchId, success: false, error: "Pi error: \(errorMessage)")
            return
        }

        guard let ids = pendingAcks[batchId] else { return }

        guard inserted == ids.count else {
            finishBatch(
                batchId: batchId,
                success: false,
                error: "Partial insert: \(inserted)/\(ids.count) - kept pending"
            )
            return
        }

        // Success — single settlement path
        print("[SyncEngine] ACK batch \(batchId.prefix(8))... inserted=\(inserted)")
        finishBatch(batchId: batchId, success: true, error: nil, markSyncedIds: ids)
    }

    /// Fail every in-flight batch.
    /// - reason == nil  → settle silently (user cancel); lastError is left alone.
    /// - reason != nil  → write the error string (disconnect / forced teardown).
    private func failAllPending(reason: String?) {
        let ids = Array(pendingAcks.keys)
        for batchId in ids {
            finishBatch(batchId: batchId, success: false, error: reason)
        }
    }

    private func isPending(_ batchId: String) -> Bool {
        pendingAcks[batchId] != nil || ackWaiters[batchId] != nil
    }

    /// Idempotent single settlement path for both success and failure.
    /// A batch that has already been settled is left alone, so a stale timeout
    /// or a duplicate error ACK cannot overwrite lastError or double-resume a
    /// continuation. On success, markSynced is applied here so there is only
    /// one place that mutates pending state + store + waiter.
    ///
    /// When error is nil and success is false (user cancel), lastError is
    /// deliberately left untouched so a clean cancel does not paint the UI red.
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
            // Clear only on an actual successful settlement. dumpToPi already
            // zeros lastError at start; this keeps the UI clean across a
            // multi-batch dump without resurrecting a prior-run error.
            lastError = nil
        } else if let error {
            lastError = error
        }
        // else: success == false && error == nil → silent settle (user cancel)

        if let waiter = ackWaiters.removeValue(forKey: batchId) {
            waiter.resume(returning: success)
        }
    }

    private func cancelTimeout(_ batchId: String) {
        ackTimeoutTasks[batchId]?.cancel()
        ackTimeoutTasks.removeValue(forKey: batchId)
    }
}
