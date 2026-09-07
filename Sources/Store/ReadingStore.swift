//
//  ReadingStore.swift
//  ArmbandIOS
//
//  Offline-first storage + sync queue.
//  Hard cap keeps memory bounded; oldest synced rows are pruned first.
//

import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ReadingStore: ObservableObject {
    @Published private(set) var readings: [Reading] = []
    /// Last BLE/MQTT packet for Live tiles. Not every packet is dumped to the Pi.
    @Published private(set) var latestLive: Reading?
    /// Last ~60 live packets for charts. In-memory only.
    @Published private(set) var liveRecent: [Reading] = []
    @Published private(set) var glucoseRefs: [GlucoseRef] = []
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var pendingGlucoseCount: Int = 0
    /// Start of the current 3-min sample window. Not every BLE packet.
    @Published private(set) var nextReadingAnchor: Date?
    @Published var currentSessionId: UUID?
    /// Closed Subject_ID from Settings. Nil until the operator picks one.
    /// Persisted in UserDefaults (`SubjectID.defaultsKey`). Re-seat does not
    /// clear this — re-seat is a new session, not a new subject.
    @Published var currentSubjectId: String? {
        didSet {
            persistSubjectId()
        }
    }
    
    private let maxReadings = 5_000
    private let liveRecentCap = 60
    private let fileURL: URL
    private let glucoseFileURL: URL
    private var saveTask: Task<Void, Never>?
    private let saveDebounceNs: UInt64 = 400_000_000
    private let saveQueue = DispatchQueue(label: "com.fryrocket.armband.readings.save")
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("readings.json")
        glucoseFileURL = docs.appendingPathComponent("glucose_refs.json")
        load()
        loadGlucoseRefs()
        loadSubjectId()
    }

    func setSubject(_ id: SubjectID?) {
        currentSubjectId = id?.rawValue
    }
    
    func add(_ reading: Reading) {
        var r = reading
        if r.sessionId == nil {
            r.sessionId = currentSessionId
        }
        if r.subjectId == nil {
            r.subjectId = currentSubjectId
        }
        latestLive = r
        liveRecent.append(r)
        if liveRecent.count > liveRecentCap {
            liveRecent.removeFirst(liveRecent.count - liveRecentCap)
        }
        // Bench BLE notifies ~1.5s. Pi dump is the 3-min sample, not every packet.
        guard NextReadingCountdown.shouldEnqueueDump(
            lastDumpAt: readings.last?.timestamp,
            incoming: r.timestamp
        ) else { return }
        readings.append(r)
        if !r.synced {
            pendingCount += 1
        }
        nextReadingAnchor = NextReadingCountdown.cadenceAnchor(
            previous: nextReadingAnchor,
            incoming: r.timestamp
        )
        enforceCap()
        scheduleSave()
    }
    
    func startSession() { currentSessionId = UUID() }
    func stopSession() { currentSessionId = nil }

    @discardableResult
    func addGlucose(kind: GlucoseKind, mgdl: Double) -> GlucoseRef {
        let ref = GlucoseRef(
            kind: kind,
            mgdl: mgdl,
            sessionId: currentSessionId,
            subjectId: currentSubjectId
        )
        glucoseRefs.append(ref)
        pendingGlucoseCount += 1
        saveGlucoseNow()
        return ref
    }

    func unsyncedGlucoseRefs() -> [GlucoseRef] {
        glucoseRefs.filter { !$0.synced }
    }

    func markGlucoseSynced(ids: [UUID]) {
        let idSet = Set(ids)
        var newly = 0
        for i in glucoseRefs.indices {
            if idSet.contains(glucoseRefs[i].id), !glucoseRefs[i].synced {
                glucoseRefs[i].synced = true
                newly += 1
            }
        }
        pendingGlucoseCount = glucoseRefs.reduce(0) { $0 + ($1.synced ? 0 : 1) }
        saveGlucoseNow()
    }

    private func loadSubjectId() {
        let stored = UserDefaults.standard.string(forKey: SubjectID.defaultsKey)
        currentSubjectId = SubjectID.parse(stored)?.rawValue
    }

    private func persistSubjectId() {
        let defaults = UserDefaults.standard
        if let v = currentSubjectId, SubjectID.parse(v) != nil {
            defaults.set(v, forKey: SubjectID.defaultsKey)
        } else {
            defaults.removeObject(forKey: SubjectID.defaultsKey)
        }
    }
    
    func markSynced(ids: [UUID]) {
        let idSet = Set(ids)
        var newly = 0
        for i in readings.indices {
            if idSet.contains(readings[i].id), !readings[i].synced {
                readings[i].synced = true
                newly += 1
            }
        }
        pendingCount = readings.reduce(0) { $0 + ($1.synced ? 0 : 1) }
        enforceCap()
        scheduleSave()
    }
    
    func unsyncedBatch(limit: Int = 200) -> [Reading] {
        Array(readings.filter { !$0.synced }.prefix(limit))
    }
    
    func clearSynced() {
        readings.removeAll { $0.synced }
        scheduleSave()
    }
    
    func flush() {
        saveTask?.cancel()
        #if canImport(UIKit)
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        saveNow {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
        #else
        saveNow(completion: nil)
        #endif
    }
    
    private func enforceCap() {
        guard readings.count > maxReadings else { return }
        var overflow = readings.count - maxReadings
        var kept: [Reading] = []
        kept.reserveCapacity(readings.count)
        for r in readings {
            if overflow > 0, r.synced {
                overflow -= 1
                continue
            }
            kept.append(r)
        }
        if kept.count > maxReadings {
            kept = Array(kept.suffix(maxReadings))
        }
        readings = kept
        pendingCount = readings.reduce(0) { $0 + ($1.synced ? 0 : 1) }
    }
    
    private func rebuildCadenceAnchor() {
        var anchor: Date?
        for r in readings {
            anchor = NextReadingCountdown.cadenceAnchor(previous: anchor, incoming: r.timestamp)
        }
        nextReadingAnchor = anchor
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: saveDebounceNs)
            guard !Task.isCancelled else { return }
            saveNow(completion: nil)
        }
    }
    
    private func saveNow(completion: (() -> Void)?) {
        let snapshot = readings
        let url = fileURL
        saveQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("ReadingStore save error: \(error)")
            }
            if let completion {
                DispatchQueue.main.async { completion() }
            }
        }
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            readings = try JSONDecoder().decode([Reading].self, from: data)
            pendingCount = readings.reduce(0) { $0 + ($1.synced ? 0 : 1) }
            enforceCap()
            rebuildCadenceAnchor()
        } catch {
            print("ReadingStore load error: \(error)")
        }
    }

    private func saveGlucoseNow() {
        let snapshot = glucoseRefs
        let url = glucoseFileURL
        saveQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("ReadingStore glucose save error: \(error)")
            }
        }
    }

    private func loadGlucoseRefs() {
        guard FileManager.default.fileExists(atPath: glucoseFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: glucoseFileURL)
            glucoseRefs = try JSONDecoder().decode([GlucoseRef].self, from: data)
            pendingGlucoseCount = glucoseRefs.reduce(0) { $0 + ($1.synced ? 0 : 1) }
        } catch {
            print("ReadingStore glucose load error: \(error)")
        }
    }
}
