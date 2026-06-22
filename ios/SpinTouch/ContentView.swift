import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @StateObject private var settings = AppSettings()
    @StateObject private var aiReader = AIReader()
    @StateObject private var store = ReadingStore()
    @State private var showLog = false
    @State private var showSettings = false
    @State private var showAIRead = false
    @State private var showTrends = false
    @State private var effectiveDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    if let reading = ble.reading {
                        if let lsi = currentLSI(reading) { lsiCard(lsi) }
                        resultsSection(reading)
                        conditionsCard
                        aiReadPlaceholder
                        metadataCard(reading)
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .onChange(of: ble.reading?.receivedAt) { _, _ in
                if let r = ble.reading { effectiveDate = r.reportTime ?? r.receivedAt }
                persistCurrent()
            }
            .onChange(of: settings.waterTempF) { _, _ in persistCurrent() }
            .onChange(of: effectiveDate) { _, _ in persistCurrent() }
            .navigationTitle("SpinTouch")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTrends = true } label: { Image(systemName: "chart.xyaxis.line") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showLog.toggle() } label: { Image(systemName: "doc.text.magnifyingglass") }
                }
            }
            .sheet(isPresented: $showLog) { logSheet }
            .sheet(isPresented: $showTrends) { TrendsView(store: store) }
            .sheet(isPresented: $showSettings) { SettingsView(settings: settings) }
            .sheet(isPresented: $showAIRead) {
                if let reading = ble.reading {
                    AIReadView(reading: reading, settings: settings, reader: aiReader)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        HStack(spacing: 12) {
            if ble.phase.isBusy {
                ProgressView()
            } else {
                Image(systemName: phaseIcon)
                    .font(.title2)
                    .foregroundStyle(phaseColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(ble.phase.label).font(.subheadline).bold()
                if let name = ble.deviceName {
                    Text(name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var phaseIcon: String {
        switch ble.phase {
        case .gotReading: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .bluetoothOff: return "wave.3.right.circle"
        default: return "drop.circle"
        }
    }

    private var phaseColor: Color {
        switch ble.phase {
        case .gotReading: return .green
        case .failed, .bluetoothOff: return .orange
        default: return .blue
        }
    }

    // MARK: - Results

    private func resultsSection(_ reading: SpinTouchReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Results").font(.headline)
            ForEach(reading.allValues) { value in
                ReadingRow(value: value)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var aiReadPlaceholder: some View {
        Button {
            guard let reading = ble.reading else { return }
            showAIRead = true
            Task { await aiReader.run(reading: reading, settings: settings) }
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Get AI Read").bold()
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Persistence

    private func persistCurrent() {
        guard let r = ble.reading else { return }
        store.upsert(reading: r, tempF: settings.waterTempValue,
                     date: effectiveDate, lsi: currentLSI(r)?.value)
    }

    // MARK: - LSI

    private func currentLSI(_ reading: SpinTouchReading) -> LSIResult? {
        LSI.compute(
            ph: reading.value("ph"),
            calcium: reading.value("calcium"),
            alkalinity: reading.value("alkalinity"),
            cya: reading.value("cyanuric_acid"),
            tempF: settings.waterTempValue,
            salt: reading.value("salt"))
    }

    private func lsiCard(_ lsi: LSIResult) -> some View {
        let color: Color = lsi.status == .balanced ? .green
            : (lsi.status == .corrosive ? .blue : .red)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Water Balance (LSI)", systemImage: "scalemass")
                    .font(.subheadline).bold()
                Spacer()
                Text(lsi.statusLabel)
                    .font(.caption2).bold()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.18), in: Capsule())
                    .foregroundStyle(color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%+.2f", lsi.value))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text("ideal −0.3 to +0.3").font(.caption).foregroundStyle(.secondary)
            }
            LSIScale(value: lsi.value)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Conditions (temperature + date)

    private var conditionsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Water Temp", systemImage: "thermometer.medium")
                Spacer()
                TextField("—", text: $settings.waterTempF)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("°F").foregroundStyle(.secondary)
            }
            Divider()
            DatePicker("Date", selection: $effectiveDate)
                .font(.subheadline)
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func metadataCard(_ reading: SpinTouchReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow("Disk series", reading.diskSeries ?? "—")
            metaRow("Sanitizer", reading.sanitizer ?? "—")
            if let report = reading.reportTime {
                metaRow("Report time", report.formatted(date: .abbreviated, time: .shortened))
            }
            metaRow("Received", reading.receivedAt.formatted(date: .omitted, time: .standard))
        }
        .font(.caption)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func metaRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).bold()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "drop.degreesign")
                .font(.system(size: 44))
                .foregroundStyle(.blue.gradient)
            Text("No results yet").font(.headline)
            Text("Power on the SpinTouch, run a test, and keep it on the results screen. Then tap Scan.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            Button {
                ble.startScan()
            } label: {
                Label(ble.reading == nil ? "Scan" : "Scan Again", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(ble.phase.isBusy)

            if ble.phase.isBusy || ble.deviceName != nil {
                Button(role: .cancel) {
                    ble.disconnect()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Log

    private var logSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(ble.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let hex = ble.reading?.rawHex {
                        Divider().padding(.vertical, 6)
                        Text("Raw payload").font(.caption).bold()
                        Text(hex).font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle("BLE Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showLog = false }
                }
            }
        }
    }
}

/// Horizontal scale showing where the LSI value sits across the corrosive →
/// balanced → scaling range (clamped to ±1.0 for display).
private struct LSIScale: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let clamped = min(1.0, max(-1.0, value))
            let x = (clamped + 1.0) / 2.0 * w
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [.blue, .green, .green, .red],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(height: 6)
                    .clipShape(Capsule())
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.gray.opacity(0.4)))
                    .shadow(radius: 1)
                    .offset(x: min(max(0, x - 7), w - 14))
            }
        }
        .frame(height: 16)
    }
}

private struct ReadingRow: View {
    let value: ParameterValue

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value.spec.name).font(.subheadline).bold()
                if let ideal = value.idealText {
                    Text(ideal).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.formattedValue).font(.title3).monospacedDigit().bold()
                if !value.displayUnit.isEmpty {
                    Text(value.displayUnit).font(.caption).foregroundStyle(.secondary)
                }
            }
            statusChip
        }
        .padding(.vertical, 4)
    }

    private var statusChip: some View {
        Text(value.status.label)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(chipColor.opacity(0.18), in: Capsule())
            .foregroundStyle(chipColor)
            .frame(width: 52)
    }

    private var chipColor: Color {
        switch value.status {
        case .ok: return .green
        case .low: return .orange
        case .high: return .red
        case .unknown: return .secondary
        }
    }
}
