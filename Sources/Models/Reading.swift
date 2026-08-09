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
    
    // Sensor values (nil means invalid)
    var bpm: Int?           // -1 in firmware → nil
    var spo2: Int?          // -1 → nil
    var temperature: Double? // -1.0 → nil
    var motion: Double
    var isMoving: Bool
    var raw940: Int
    var filt940: Double
    var batteryVoltage: Double
    var transition: String  // "none", "still_to_moving", "moving_to_still"
    var connectMs: UInt32?
    var bootCount: UInt32?
    
    // Local management
    var sessionId: UUID?
    var synced: Bool
    var source: String      // "ble" | "mqtt" | "manual"
    
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
    
    /// Parse the exact JSON published by Armband_Full.ino
    static func fromFirmwareJSON(_ data: Data) -> Reading? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        func intVal(_ key: String) -> Int? {
            guard let v = json[key] as? Int, v != -1 else { return nil }
            return v
        }
        
        func doubleVal(_ key: String) -> Double? {
            if let v = json[key] as? Double, v != -1.0 { return v }
            if let v = json[key] as? Int, v != -1 { return Double(v) }
            return nil
        }
        
        return Reading(
            bpm: intVal("bpm"),
            spo2: intVal("spo2"),
            temperature: doubleVal("temp"),
            motion: (json["motion"] as? Double) ?? 0,
            isMoving: (json["moving"] as? Bool) ?? false,
            raw940: (json["raw940"] as? Int) ?? 0,
            filt940: (json["filt940"] as? Double) ?? 0,
            batteryVoltage: (json["batt"] as? Double) ?? 0,
            transition: (json["trans"] as? String) ?? "none",
            connectMs: json["conn_ms"] as? UInt32,
            bootCount: json["boot"] as? UInt32,
            synced: false,
            source: "mqtt"
        )
    }
}
