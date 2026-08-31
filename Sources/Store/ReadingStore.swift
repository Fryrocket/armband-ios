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
    @Published private(set) var pendingCount: Int = 0
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
    private var saveTask: Task<Void, Never>?
    private let saveDebounceNs: UInt64 = 400_000_000
    private let saveQueue = DispatchQueue(label: "com.fryrocket.armband.readings.save")
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("readings.json")
        load()
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
}
