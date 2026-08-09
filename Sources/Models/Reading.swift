//
//  Reading.swift
//  ArmbandIOS
//
//  Core data model matching the current armband firmware JSON.
//

import Foundation

struct Reading: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    
    var bpm: Int?
    var spo2: Int?
    var temperature: Double?
    var motion: Double
    var isMoving: Bool
    var raw940: Int
    var filt940: Double
    var batteryVoltage: Double
    var transition: String
    var connectMs: UInt32?
    var bootCount: UInt32?
    
    var sessionId: UUID?
    var synced: Bool
    var source: String
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        bpm: Int? = nil,
        spo2: Int? = nil,
        temperature: Double? = nil,
        motion: Double = 0,
        isMoving: Bool = false,
        raw940: Int = 0,
        filt940: Double = 0,
        batteryVoltage: Double = 0,
        transition: String = "none",
        connectMs: UInt32? = nil,
        bootCount: UInt32? = nil,
        sessionId: UUID? = nil,
        synced: Bool = false,
        source: String = "ble"
    ) {
        self.id = id
        self.timestamp = timestamp
        self.bpm = bpm
        self.spo2 = spo2
        self.temperature = temperature
        self.motion = motion
        self.isMoving = isMoving
        self.raw940 = raw940
        self.filt940 = filt940
        self.batteryVoltage = batteryVoltage
        self.transition = transition
        self.connectMs = connectMs
        self.bootCount = bootCount
        self.sessionId = sessionId
        self.synced = synced
        self.source = source
    }
    
    static func fromFirmwareJSON(_ data: Data) -> Reading? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        func intVal(_ key: String) -> Int? {
            let raw: Int?
            if let v = json[key] as? Int { raw = v }
            else if let n = json[key] as? NSNumber { raw = n.intValue }
            else { raw = nil }
            guard let v = raw, v > 0 else { return nil }
            return v
        }
        
        func doubleVal(_ key: String) -> Double? {
            let raw: Double?
            if let v = json[key] as? Double { raw = v }
            else if let v = json[key] as? Int { raw = Double(v) }
            else if let n = json[key] as? NSNumber { raw = n.doubleValue }
            else { raw = nil }
            guard let v = raw, v > 0 else { return nil }
            return v
        }
        
        func boolVal(_ key: String) -> Bool {
            if let b = json[key] as? Bool { return b }
            if let n = json[key] as? NSNumber { return n.boolValue }
            if let s = json[key] as? String {
                return ["true", "1", "yes"].contains(s.lowercased())
            }
            return false
        }
        
        func numberInt(_ key: String) -> Int {
            if let v = json[key] as? Int { return v }
            if let n = json[key] as? NSNumber { return n.intValue }
            return 0
        }
        
        func numberDouble(_ key: String) -> Double {
            if let v = json[key] as? Double { return v }
            if let v = json[key] as? Int { return Double(v) }
            if let n = json[key] as? NSNumber { return n.doubleValue }
            return 0
        }
        
        return Reading(
            bpm: intVal("bpm"),
            spo2: intVal("spo2"),
            temperature: doubleVal("temp"),
            motion: numberDouble("motion"),
            isMoving: boolVal("moving"),
            raw940: numberInt("raw940"),
            filt940: numberDouble("filt940"),
            batteryVoltage: numberDouble("batt"),
            transition: (json["trans"] as? String) ?? "none",
            connectMs: (json["conn_ms"] as? NSNumber)?.uint32Value,
            bootCount: (json["boot"] as? NSNumber)?.uint32Value,
            synced: false,
            source: "mqtt"
        )
    }
}
