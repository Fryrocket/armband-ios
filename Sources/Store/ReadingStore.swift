//
//  ReadingStore.swift
//  ArmbandIOS
//
//  Offline-first storage + sync queue.
//  Saves are debounced and serialized so concurrent encodes cannot
//  write a stale snapshot over a newer one.
//

import Foundation
import Combine
import UIKit

@MainActor
final class ReadingStore: ObservableObject {
    @Published private(set) var readings: [Reading] = []
    @Published private(set) var pendingCount: Int = 0
    @Published var currentSessionId: UUID?
    
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private let saveDebounceNs: UInt64 = 400_000_000
    private let saveQueue = DispatchQueue(label: "com.fryrocket.armband.readings.save")
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("readings.json")
        load()
    }
    
    func add(_ reading: Reading) {
        var r = reading
        if r.sessionId == nil {
            r.sessionId = currentSessionId
        }
        readings.append(r)
        pendingCount = readings.filter { !$0.synced }.count
        scheduleSave()
    }
    
    func startSession() { currentSessionId = UUID() }
    func stopSession() { currentSessionId = nil }
    
    func markSynced(ids: [UUID]) {
        let idSet = Set(ids)
        for i in readings.indices {
            if idSet.contains(readings[i].id) {
                readings[i].synced = true
            }
        }
        pendingCount = readings.filter { !$0.synced }.count
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
            pendingCount = readings.filter { !$0.synced }.count
        } catch {
            print("ReadingStore load error: \(error)")
        }
    }
}
