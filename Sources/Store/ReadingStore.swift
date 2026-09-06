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
    @Published private(set) var glucoseRefs: [GlucoseRef] = []
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var pendingGlucoseCount: Int = 0
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
        readings.append(r)
        if !r.synced {
            pendingCount += 1
        }
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
        pendingGlucoseCount = max(0, pendingGlucoseCount - newly)
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
        pendingCount = max(0, pendingCount - newly)
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
