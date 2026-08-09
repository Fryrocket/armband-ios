//
//  DashboardView.swift
//  ArmbandIOS
//
//  Main live view with metrics cards + Swift Charts.
//

import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var store: ReadingStore
    @ObservedObject var syncEngine: SyncEngine
    
    private var latest: Reading? {
        store.readings.last
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Status row
                    HStack {
                        Label(store.pendingCount > 0 ? "\(store.pendingCount) pending" : "All synced",
                              systemImage: store.pendingCount > 0 ? "icloud.and.arrow.up" : "checkmark.icloud")
                            .foregroundStyle(store.pendingCount > 0 ? .orange : .green)
                        Spacer()
                        if syncEngine.isSyncing {
                            ProgressView()
                        } else {
                            Button("Dump to Pi") {
                                Task { await syncEngine.dumpToPi() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Metric cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Heart Rate", value: latest?.bpm.map { "\($0)" } ?? "--", unit: "bpm")
                        MetricCard(title: "SpO₂", value: latest?.spo2.map { "\($0)" } ?? "--", unit: "%")
                        MetricCard(title: "Temp", value: latest?.temperature.map { String(format: "%.1f", $0) } ?? "--", unit: "°C")
                        MetricCard(title: "Battery", value: latest.map { String(format: "%.2f", $0.batteryVoltage) } ?? "--", unit: "V")
                        MetricCard(title: "940 nm", value: latest.map { String(format: "%.0f", $0.filt940) } ?? "--", unit: "")
                        MetricCard(title: "Motion", value: latest.map { String(format: "%.1f", $0.motion) } ?? "--",
                                   unit: latest?.isMoving == true ? "MOV" : "still")
                    }
                    .padding(.horizontal)
                    
                    // Live chart
                    VStack(alignment: .leading) {
                        Text("Heart Rate & 940 nm")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Chart {
                            ForEach(store.readings.suffix(60)) { r in
                                if let bpm = r.bpm {
                                    LineMark(
                                        x: .value("Time", r.timestamp),
                                        y: .value("BPM", bpm)
                                    )
                                    .foregroundStyle(.red)
                                }
                                LineMark(
                                    x: .value("Time", r.timestamp),
                                    y: .value("940", r.filt940 / 20)
                                )
                                .foregroundStyle(.blue)
                            }
                        }
                        .frame(height: 220)
                        .padding()
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    
                    // Session controls
                    HStack {
                        if store.currentSessionId == nil {
                            Button("Start Session") { store.startSession() }
                                .buttonStyle(.bordered)
                        } else {
                            Button("Stop Session") { store.stopSession() }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                        }
                    }
                    .padding()
                }
                .padding(.vertical)
            }
            .navigationTitle("BGM Armband")
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
