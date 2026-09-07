//
//  ArmbandIOSApp.swift
//  ArmbandIOS
//

import SwiftUI

@main
struct ArmbandIOSApp: App {
    @StateObject private var store: ReadingStore
    @StateObject private var mqtt: MQTTClient
    @StateObject private var bluetooth: BluetoothManager
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
        let bluetooth = BluetoothManager()
        _store = StateObject(wrappedValue: store)
        _mqtt = StateObject(wrappedValue: mqtt)
        _bluetooth = StateObject(wrappedValue: bluetooth)
        _syncEngine = StateObject(wrappedValue: SyncEngine(store: store, mqtt: mqtt))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(mqtt)
                .environmentObject(bluetooth)
                .environmentObject(syncEngine)
                .onAppear {
                    if bluetooth.onReading == nil {
                        bluetooth.onReading = { [weak store] reading in
                            store?.add(reading)
                        }
                    }
                    if mqtt.onReading == nil {
                        mqtt.onReading = { [weak store, weak bluetooth] reading in
                            if bluetooth?.isConnected == true { return }
                            store?.add(reading)
                        }
                    }
                    LocalNetworkGate.shared.nudge()
                    _ = NetworkPath.shared
                    bluetooth.start()
                    mqtt.connect()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        LocalNetworkGate.shared.nudge()
                        if !mqtt.isConnected {
                            mqtt.connect()
                        }
                    }
                    if phase == .background || phase == .inactive {
                        store.flush()
                    }
                }
        }
    }
}
