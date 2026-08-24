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
    @State private var mqttUser = ""
    @State private var mqttPass = ""
    @State private var credStatus: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Subject") {
                    Picker("Subject ID", selection: Binding(
                        get: { store.currentSubjectId ?? "" },
                        set: { store.setSubject(SubjectID.parse($0.isEmpty ? nil : $0)) }
                    )) {
                        Text("Not set").tag("")
                        ForEach(SubjectID.allCases) { s in
                            Text(s.rawValue).tag(s.rawValue)
                        }
                    }
                    Text("S001 uses SUBJ_A. Re-seat is a new session, not a new subject.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

                Section("MQTT credentials") {
                    TextField("Username", text: $mqttUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $mqttPass)
                    Button("Save to Keychain") {
                        saveMQTTCredentials()
                    }
                    if let credStatus {
                        Text(credStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Stored in Keychain only. Never the app plist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .onAppear {
                let loaded = MQTTCredentials.load()
                mqttUser = loaded.username
                mqttPass = loaded.password
            }
        }
    }

    private func saveMQTTCredentials() {
        let ok = MQTTCredentials.save(username: mqttUser, password: mqttPass)
        guard ok else {
            credStatus = "Keychain write failed — not stored"
            return
        }
        mqtt.updateBroker(
            host: mqtt.host,
            port: mqtt.port,
            username: mqttUser.isEmpty ? nil : mqttUser,
            password: mqttPass.isEmpty ? nil : mqttPass
        )
        credStatus = "Saved in Keychain"
    }
}
