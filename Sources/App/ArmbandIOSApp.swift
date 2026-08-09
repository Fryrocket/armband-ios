//
//  ArmbandIOSApp.swift
//  ArmbandIOS
//

import SwiftUI

@main
struct ArmbandIOSApp: App {
    @StateObject private var store: ReadingStore
    @StateObject private var mqtt: MQTTClient
    @StateObject private var syncEngine: SyncEngine
    
    init() {
        let store = ReadingStore()
        let mqtt = MQTTClient(
            host: "192.168.1.100",   // ← change to your Pi IP
            username: "armband",
            password: nil
        )
        _store = StateObject(wrappedValue: store)
        _mqtt = StateObject(wrappedValue: mqtt)
        _syncEngine = StateObject(wrappedValue: SyncEngine(store: store, mqtt: mqtt))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(mqtt)
                .environmentObject(syncEngine)
                .onAppear {
                    mqtt.onReading = { [weak store] reading in
                        store?.add(reading)
                    }
                    mqtt.connect()
                }
        }
    }
}
