//
//  DashboardView.swift
//  ArmbandIOS
//
//  Main live view with metrics cards + Swift Charts.
//  BPM and 940 nm use separate charts / independent y-domains.
//

import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var store: ReadingStore
    @ObservedObject var syncEngine: SyncEngine
    
    private var latest: Reading? { store.readings.last }
    private var recent: ArraySlice<Reading> { store.readings.suffix(60) }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Label(store.pendingCount > 0 ? "\(store.pendingCount) pending" : "All synced",
                              systemImage: store.pendingCount > 0 ? "icloud.and.arrow.up" : "checkmark.icloud")
                            .foregroundStyle(store.pendingCount > 0 ? .orange : .green)
                        Spacer()
                        if syncEngine.isSyncing {
                            Button("Cancel") {
                                syncEngine.cancelDump()
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            ProgressView()
                        } else {
                            Button("Dump to Pi") {
                                syncEngine.startDump()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal)
                    
                    Filt940Card(value: latest?.filt940)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Heart Rate", value: latest?.bpm.map { "\($0)" } ?? "--", unit: "bpm")
                        MetricCard(title: "SpO2", value: latest?.spo2.map { "\($0)" } ?? "--", unit: "%")
                        MetricCard(title: "Battery", value: latest.map { String(format: "%.2f", $0.batteryVoltage) } ?? "--", unit: "V")
                    }
                    .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Motion", value: latest.map { String(format: "%.1f", $0.motion) } ?? "--",
                                   unit: latest?.isMoving == true ? "MOV" : "still")
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let tick = NextReadingCountdown.display(
                                lastReading: latest?.timestamp,
                                now: context.date
                            )
                            MetricCard(title: "Next reading", value: tick.value, unit: tick.unit)
                        }
                    }
                    .padding(.horizontal)

                    DualTempCard(
                        celsius: latest?.temperature,
                        fahrenheit: latest?.temperatureFahrenheit
                    )
                    .padding(.horizontal)

                    UploadStatusCard(syncEngine: syncEngine, pendingCount: store.pendingCount)
                        .padding(.horizontal)
                    
                    chartCard(title: "Heart Rate (bpm)") {
                        Chart {
                            ForEach(Array(recent)) { r in
                                if let bpm = r.bpm {
                                    LineMark(
                                        x: .value("Time", r.timestamp),
                                        y: .value("BPM", bpm)
                                    )
                                    .foregroundStyle(.red)
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 160)
                    }
                    
                    chartCard(title: "940 nm (filt)") {
                        Chart {
                            ForEach(Array(recent)) { r in
                                LineMark(
                                    x: .value("Time", r.timestamp),
                                    y: .value("940", r.filt940)
                                )
                                .foregroundStyle(.blue)
                                .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 160)
                    }
                    
                    HStack {
                        if store.currentSessionId == nil {
                            Button("Start Session") { store.startSession() }
                                .buttonStyle(.bordered)
                        } else {
                            Button("Stop Session") { store.stopSession() }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                        }
                        Spacer()
                        Text(store.currentSubjectId ?? "subject unset")
                            .font(.caption)
                            .foregroundStyle(store.currentSubjectId == nil ? .orange : .secondary)
                    }
                    .padding()
                }
                .padding(.vertical)
            }
            .navigationTitle("BGM Armband")
            .hunterGreenScreen()
        }
    }
    
    @ViewBuilder
    private func chartCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            content()
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct Filt940Card: View {
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("940 nm")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value.map { String(format: "%.0f", $0) } ?? "--")
                    .font(.title.bold())
                    .monospacedDigit()
                Text("filt")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DualTempCard: View {
    let celsius: Double?
    let fahrenheit: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                tempColumn(
                    value: celsius.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "°C"
                )
                Text("/")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                tempColumn(
                    value: fahrenheit.map { String(format: "%.1f", $0) } ?? "--",
                    unit: "°F"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tempColumn(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
            Text(unit)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

struct UploadStatusCard: View {
    @ObservedObject var syncEngine: SyncEngine
    let pendingCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var title: String {
        if syncEngine.isSyncing { return "Uploading…" }
        if syncEngine.lastError != nil { return "Upload failed" }
        if syncEngine.lastSyncTime != nil { return "Upload successful" }
        return "No upload yet"
    }

    private var subtitle: String {
        if syncEngine.isSyncing {
            return pendingCount > 0 ? "\(pendingCount) pending" : "Sending to Pi"
        }
        if let err = syncEngine.lastError { return err }
        if let t = syncEngine.lastSyncTime {
            let n = syncEngine.lastBatchCount
            let when = t.formatted(.relative(presentation: .named))
            if n > 0 { return "\(n) reading\(n == 1 ? "" : "s") · \(when)" }
            return when
        }
        if pendingCount > 0 { return "\(pendingCount) waiting to dump" }
        return "Dump to Pi when you have readings"
    }

    private var iconName: String {
        if syncEngine.isSyncing { return "arrow.up.circle" }
        if syncEngine.lastError != nil { return "xmark.circle.fill" }
        if syncEngine.lastSyncTime != nil { return "checkmark.circle.fill" }
        return "icloud.and.arrow.up"
    }

    private var tint: Color {
        if syncEngine.isSyncing { return .orange }
        if syncEngine.lastError != nil { return .red }
        if syncEngine.lastSyncTime != nil { return .green }
        return .secondary
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
