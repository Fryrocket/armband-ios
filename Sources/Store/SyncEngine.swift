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
//  - #1 Partial-insert poison batch. `inserted == count` was the success
//       test, but the Pi uses INSERT OR IGNORE, so a batch that partially
//       landed reports FEWER inserts on every re-send and can never settle.
//       The ACK now carries `duplicates` (rows already present) and success
//       is `inserted + duplicates >= count`. A head id that comes back
//       partial twice raises a distinct "wedged" error instead of silently
//       retrying forever.
//  - #2 Cancel window before registration. withTaskCancellationHandler fires
//       onCancel exactly once, at the instant of cancellation. A cancel that
//       landed after the handler was installed but before pendingAcks was
//       written found nothing to settle, and the batch then registered and
//       stalled for the full 15s. Now checked before and after registration.
//  - #3 Cancel after a successful batch no longer discards the sync stamp.
//       totalSynced is credited before the cancellation break.
//  - #4 (MQTTClient) onDisconnect now carries a reason; nil means we asked
//       for the disconnect, so pending batches settle without painting red.
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

    /// Poison-batch detection (fix #1). Survives across dumps on purpose:
    /// the wedge only becomes visible on the second attempt at the same head.
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

        // reason == nil -> we initiated the disconnect, settle silently.
        mqtt?.onDisconnect = { [weak self] reason in
            Task { @MainActor in
                self?.failAllPending(reason: reason)
            }
        }
    }

    // MARK: - Dump loop

    func dumpToPi() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil

        // Guarantees isSyncing is cleared on every exit path.
        defer { isSyncing = false }

        guard let mqtt, mqtt.isConnected else {
            lastError = "Pi not reachable (MQTT disconnected)"
            return
        }

        var totalSynced = 0

        // Guard against an unsynced set that never shrinks (markSynced no-op,
        // store write failure, ...). Without this the loop spins at 20 Hz.
        var previousHeadId: UUID?

        while true {
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
            // onCancel fires once, at the moment of cancellation - sendOneBatch
            // re-checks Task.isCancelled itself to cover the registration window.
            let ok = await withTaskCancellationHandler {
                await sendOneBatch(batch, mqtt: mqtt)
            } onCancel: { [weak self] in
                Task { @MainActor in
                    self?.failAllPending(reason: nil)
                }
            }

            // FIX #3: credit the batch before the cancellation break. These
            // readings are already marked synced in the store; dropping them
            // from totalSynced meant a cancel right after the first ACK left
            // lastSyncTime / lastBatchCount stale even though data had landed.
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

        // FIX #2 (part 1): cancellation may have landed while we were building
        // the payload, i.e. after the enclosing withTaskCancellationHandler
        // installed onCancel but before this batch exists in pendingAcks.
        // onCancel has already run and found nothing to settle, so bail out
        // here rather than registering a batch nothing can cancel.
        if Task.isCancelled { return false }

        pendingAcks[batchId] = ids

        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            self.ackWaiters[batchId] = cont

            // FIX #2 (part 2): now that the batch is registered, re-check.
            // This closes the gap between the guard above and this line -
            // if a cancel slipped through, settle it ourselves instead of
            // publishing and waiting the full 15s for a timeout.
            if Task.isCancelled {
                self.finishBatch(batchId: batchId, success: false, error: nil)
                return
            }

            self.ackTimeoutTasks[batchId] = Task { [weak self] in
                // Do NOT use `try?` here: it swallows the CancellationError and
                // lets the timeout body run immediately after cancelTimeout().
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

    /// - Parameters:
    ///   - inserted:   rows the Pi actually wrote
    ///   - duplicates: rows the Pi already had and ignored (0 if the Pi does
    ///                 not send the field, which preserves the old behaviour)
    private func handleAck(batchId: String, inserted: Int, duplicates: Int, errorMessage: String?) {
        // Ignore ACKs for batches we are no longer waiting on (late ACK after a
        // timeout, duplicate ACK, ACK for a previous app run).
        guard isPending(batchId) else { return }

        if let errorMessage {
            finishBatch(batchId: batchId, success: false, error: "Pi error: \(errorMessage)")
            return
        }

        guard let ids = pendingAcks[batchId] else { return }

        // FIX #1: a row the Pi already holds is accounted for, not lost. With
        // INSERT OR IGNORE, `inserted` alone shrinks on every re-send of a
        // batch that partially landed, so the old `inserted == ids.count` test
        // could never be satisfied again and sync wedged permanently.
        let accounted = inserted + duplicates
        guard accounted >= ids.count else {
            noteFailedInsert(head: ids.first)
            let detail = duplicates > 0
                ? "\(inserted) new + \(duplicates) dup / \(ids.count)"
                : "\(inserted)/\(ids.count)"

            if partialRepeatCount >= 2 {
                // Same head id, second time round: the readings are almost
                // certainly on the Pi already and are being re-ignored.
                finishBatch(
                    batchId: batchId,
                    success: false,
                    error: """
                    Sync wedged: same batch partially inserted \(partialRepeatCount)x (\(detail)). \
                    The Pi is not reporting ignored duplicates - add `duplicates` to the ACK.
                    """
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

        // Success - single settlement path
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

    /// Fail every in-flight batch.
    /// - reason == nil -> settle silently (user cancel, or a disconnect we
    ///   initiated ourselves); lastError is left alone.
    /// - reason != nil -> write the error string (unexpected connection loss).
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
    /// continuation.
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
            lastError = nil
        } else if let error {
            lastError = error
        }
        // else: success == false && error == nil -> silent settle

        if let waiter = ackWaiters.removeValue(forKey: batchId) {
            waiter.resume(returning: success)
        }
    }

    private func cancelTimeout(_ batchId: String) {
        ackTimeoutTasks[batchId]?.cancel()
        ackTimeoutTasks.removeValue(forKey: batchId)
    }
}
