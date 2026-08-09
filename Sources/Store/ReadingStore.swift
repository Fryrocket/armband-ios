//
//  ReadingStore.swift
//  ArmbandIOS
//
//  Offline-first storage + sync queue.
//  Saves are debounced so rapid MQTT bursts don't stall the UI.
//

import Foundation
import Combine

@MainActor
final class ReadingStore: ObservableObject {
    @Published private(set) var readings: [Reading] = []
    @Published private(set) var pendingCount: Int = 0
    @Published var currentSessionId: UUID?
    
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private let saveDebounceNs: UInt64 = 400_000_000  // 400 ms
    
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
    
    func startSession() {
        currentSessionId = UUID()
    }
    
    func stopSession() {
        currentSessionId = nil
    }
    
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
    
    /// Force an immediate save (e.g. on backgrounding)
    func flush() {
        saveTask?.cancel()
        saveNow()
    }
    
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: saveDebounceNs)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }
    
    private func saveNow() {
        let snapshot = readings
        let url = fileURL
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                print("ReadingStore save error: \(error)")
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
