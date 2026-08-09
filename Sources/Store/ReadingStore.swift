//
//  ReadingStore.swift
//  ArmbandIOS
//
//  Offline-first storage + sync queue.
//

import Foundation
import Combine

@MainActor
final class ReadingStore: ObservableObject {
    @Published private(set) var readings: [Reading] = []
    @Published private(set) var pendingCount: Int = 0
    @Published var currentSessionId: UUID?
    
    private let fileURL: URL
    
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
        save()
    }
    
    func startSession() {
        currentSessionId = UUID()
    }
    
    func stopSession() {
        currentSessionId = nil
    }
    
    func markSynced(ids: [UUID]) {
        for i in readings.indices {
            if ids.contains(readings[i].id) {
                readings[i].synced = true
            }
        }
        pendingCount = readings.filter { !$0.synced }.count
        save()
    }
    
    func unsyncedBatch(limit: Int = 200) -> [Reading] {
        Array(readings.filter { !$0.synced }.prefix(limit))
    }
    
    func clearSynced() {
        readings.removeAll { $0.synced }
        save()
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(readings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("ReadingStore save error: \(error)")
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
