//
//  ContentView.swift
//  ArmbandIOS
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ReadingStore
    @EnvironmentObject var mqtt: MQTTClient
    @EnvironmentObject var syncEngine: SyncEngine
    
    var body: some View {
        TabView {
            DashboardView(store: store, syncEngine: syncEngine)
                .tabItem {
                    Label("Live", systemImage: "heart.text.square")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var mqtt: MQTTClient
    @EnvironmentObject var store: ReadingStore
    @EnvironmentObject var syncEngine: SyncEngine
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    HStack {
                        Text("MQTT")
                        Spacer()
                        Circle()
                            .fill(mqtt.isConnected ? .green : .red)
                            .frame(width: 12, height: 12)
                        Text(mqtt.isConnected ? "Connected" : "Disconnected")
                            .foregroundStyle(.secondary)
                    }
                    
                    if let err = mqtt.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    Button(mqtt.isConnected ? "Disconnect" : "Connect") {
                        if mqtt.isConnected {
                            mqtt.disconnect()
                        } else {
                            mqtt.connect()
                        }
                    }
                }
                
                Section("Sync") {
                    HStack {
                        Text("Pending readings")
                        Spacer()
                        Text("\(store.pendingCount)")
                            .foregroundStyle(.secondary)
                    }
                    
                    if let last = syncEngine.lastSyncTime {
                        HStack {
                            Text("Last sync")
                            Spacer()
                            Text(last, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if syncEngine.isSyncing {
                        Button("Cancel dump", role: .destructive) {
                            syncEngine.cancelDump()
                        }
                    } else {
                        Button("Dump to Pi now") {
                            syncEngine.startDump()
                        }
                        .disabled(store.pendingCount == 0)
                    }
                }
                
                Section("Data") {
                    Button("Clear synced readings", role: .destructive) {
                        store.clearSynced()
                    }
                }
                
                Section("About") {
                    Text("BGM Armband iOS")
                    Text("Experimental – not a medical device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
