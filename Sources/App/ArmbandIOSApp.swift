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
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        let defaults = UserDefaults.standard
        let host = MQTTHost.load(defaults)

        // One-time migration: any credential previously saved to plaintext
        // UserDefaults moves into the Keychain and is removed from the
        // .plist. Safe to run every launch — no-op once migrated.
        KeychainStore.migrateLegacyUserDefaults(defaults)
        let user = KeychainStore.read(account: "mqtt_username")
        let pass = KeychainStore.read(account: "mqtt_password")
        
        let store = ReadingStore()
        let mqtt = MQTTClient(host: host, username: user, password: pass)
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
                    if mqtt.onReading == nil {
                        mqtt.onReading = { [weak store] reading in
                            store?.add(reading)
                        }
                    }
                    mqtt.connect()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background || phase == .inactive {
                        store.flush()
                    }
                }
        }
    }
}
