import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @StateObject private var settings = AppSettings()
    @StateObject private var aiReader = AIReader()
    @StateObject private var store = ReadingStore()
    @State private var showLog = false
    @State private var showSettings = false
    @State private var showAIRead = false
    @State private var showAIDisclosure = false
    @State private var showTrends = false
    @State private var selectedKey: String?       // identityKey of the displayed stored reading
    @State private var editTemp = ""
    @State private var editDate = Date()
    @FocusState private var tempFocused: Bool

    private static let lastViewedKeyDefault = "lastViewedKey"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    if let reading = displayReading {
                        if isStored { historyNavBar }
                        if !reading.endSignatureValid { unverifiedBanner }
                        if let lsi = displayLSI(reading) { lsiCard(lsi) }
                        resultsSection(reading)
                        if isStored { conditionsCard }
                        recommendationsCard(reading)
                        if isStored { aiReadPlaceholder }
                        metadataCard(reading)
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { restoreSelection() }
            .onChange(of: ble.reading?.receivedAt) { _, _ in handleScan() }
            .onChange(of: editTemp) { _, _ in pushConditions() }
            .onChange(of: editDate) { _, _ in pushConditions() }
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { tempFocused = false }
                }
            }
            .sheet(isPresented: $showLog) { logSheet }
            .sheet(isPresented: $showTrends) { TrendsView(store: store) }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings, onClearAICache: { aiReader.clearCache() })
            }
            .sheet(isPresented: $showAIRead) {
                if let s = selectedStored {
                    AIReadView(reading: s.reconstructedReading(), collectionDate: s.date,
                               tempF: s.tempF, settings: settings, reader: aiReader)
                }
            }
            .alert("AI Read", isPresented: $showAIDisclosure) {
                Button("Continue") { settings.aiDisclosureAccepted = true; startAIRead() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("AI Read sends this reading and your pool settings/notes to Anthropic using your API key. Offline recommendations stay on-device.")
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
    }

    // MARK: - Displayed reading (browsed history or an unverified live scan)

    /// An unverified live scan is shown transiently but never persisted.
    private var liveUnverified: SpinTouchReading? {
        if let r = ble.reading, !r.endSignatureValid { return r }
        return nil
    }

    private var selectedStored: StoredReading? {
        if let k = selectedKey, let e = store.readings.first(where: { $0.identityKey == k }) { return e }
        return store.readings.last
    }

    private var isStored: Bool { liveUnverified == nil && selectedStored != nil }

    private var displayReading: SpinTouchReading? {
        if let live = liveUnverified { return live }
        return selectedStored?.reconstructedReading()
    }

    private func displayLSI(_ reading: SpinTouchReading) -> LSIResult? {
        if isStored, let lsi = selectedStored?.lsi { return LSIResult(value: lsi) }
        if liveUnverified != nil { return currentLSI(reading) }
        return nil
    }

    // MARK: - Selection + navigation

    private var currentIndex: Int? {
        guard let key = selectedStored?.identityKey else { return nil }
        return store.readings.firstIndex { $0.identityKey == key }
    }

    private var atLatest: Bool { (currentIndex ?? 0) >= store.readings.count - 1 }
    private var canStepOlder: Bool { isStored && (currentIndex ?? 0) > 0 }
    private var canStepNewer: Bool { isStored && !atLatest }

    private func select(_ key: String?) {
        selectedKey = key
        UserDefaults.standard.set(key, forKey: Self.lastViewedKeyDefault)
        syncEditFields()
    }

    private func restoreSelection() {
        let saved = UserDefaults.standard.string(forKey: Self.lastViewedKeyDefault)
        if let saved, store.readings.contains(where: { $0.identityKey == saved }) {
            selectedKey = saved
        } else {
            selectedKey = store.readings.last?.identityKey
        }
        syncEditFields()
    }

    private func stepOlder() {
        guard let i = currentIndex, i > 0 else { return }
        select(store.readings[i - 1].identityKey)
    }

    private func stepNewer() {
        guard let i = currentIndex, i < store.readings.count - 1 else { return }
        select(store.readings[i + 1].identityKey)
    }

    private func jumpLatest() { select(store.readings.last?.identityKey) }

    @ViewBuilder
    private var historyNavBar: some View {
        if store.readings.count > 1 || !atLatest {
            HStack(spacing: 12) {
                Button { stepOlder() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .disabled(!canStepOlder)

                Spacer()
                VStack(spacing: 1) {
                    if let s = selectedStored {
                        Text(s.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.primary)
                    }
                    if let i = currentIndex {
                        Text("\(i + 1) of \(store.readings.count)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()

                Button { stepNewer() } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                }
                .disabled(!canStepNewer)

                Button { jumpLatest() } label: {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(atLatest)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Scan + conditions persistence

    private func handleScan() {
        guard let r = ble.reading else { return }
        guard r.endSignatureValid else { return }   // unverified: shown via liveUnverified, not saved
        let date = r.reportTime ?? Date()
        let lsi = LSI.compute(
            ph: r.value("ph"), calcium: r.value("calcium"), alkalinity: r.value("alkalinity"),
            cya: r.value("cyanuric_acid"), tempF: settings.waterTempValue, salt: r.value("salt"))?.value
        store.upsert(reading: r, tempF: settings.waterTempValue, date: date, lsi: lsi)
        select(r.rawHex)
    }

    private func syncEditFields() {
        if let s = selectedStored {
            editTemp = s.tempF.map(Self.formatTemp) ?? settings.waterTempF
            editDate = s.date
        } else {
            editTemp = settings.waterTempF
            editDate = Date()
        }
    }

    private func pushConditions() {
        guard let s = selectedStored else { return }
        let t = Self.parseTemp(editTemp)
        if t == s.tempF && editDate == s.date { return }   // no real change (e.g. from syncEditFields)
        settings.waterTempF = editTemp                       // seed for the next scan
        store.updateConditions(identityKey: s.identityKey, tempF: t, date: editDate)
    }

    private static func formatTemp(_ t: Double) -> String {
        t == t.rounded() ? String(Int(t)) : String(format: "%.1f", t)
    }

    private static func parseTemp(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? Double(cleaned.filter { $0.isNumber || $0 == "." })
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
                if let reading = displayReading {
                    if let summary = reading.qualitySummary {
                        Text("Out of range: \(summary)")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("All measured parameters in range")
                            .font(.caption).foregroundStyle(.green)
                    }
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
            requestAIRead()
        } label: {
            HStack {
                Image(systemName: "sparkles")
                Text("Get AI Read").bold()
                Spacer()
                if aiReader.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(aiReader.isLoading)
    }

    private func requestAIRead() {
        guard selectedStored != nil else { return }
        if !settings.aiDisclosureAccepted {
            showAIDisclosure = true
            return
        }
        startAIRead()
    }

    private func startAIRead() {
        guard let s = selectedStored else { return }
        showAIRead = true
        aiReader.start(reading: s.reconstructedReading(), settings: settings,
                       collectionDate: s.date, tempF: s.tempF)
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

    // MARK: - Recommendations (offline)

    @ViewBuilder
    private func recommendationsCard(_ reading: SpinTouchReading) -> some View {
        let advice = Recommendations.evaluate(reading)
        VStack(alignment: .leading, spacing: 10) {
            Label("Recommendations", systemImage: "checklist")
                .font(.headline)
            if advice.isEmpty {
                Label("All measured parameters look in range.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(.green)
            } else {
                ForEach(advice) { a in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: a.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            .foregroundStyle(a.severity == .critical ? .red : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).font(.subheadline).bold()
                            Text(a.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Conditions (temperature + collection date)

    private var conditionsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Water Temp", systemImage: "thermometer.medium")
                Spacer()
                TextField("—", text: $editTemp)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($tempFocused)
                Text("°F").foregroundStyle(.secondary)
            }
            Divider()
            DatePicker("Collection time", selection: $editDate)
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
            if isStored, let t = selectedStored?.tempF {
                metaRow("Water temp", "\(Int(t.rounded())) °F")
            }
            let effective = reading.reportTime ?? reading.receivedAt
            let age = Date().timeIntervalSince(effective)
            HStack {
                Text("Test age").foregroundStyle(.secondary)
                Spacer()
                Text(effective.formatted(.relative(presentation: .named))).bold()
                if age > 3 * 24 * 3600 {
                    Text("STALE")
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
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

    private var unverifiedBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Unverified reading — the payload signature didn't match. Values may be incomplete and won't be saved to history.")
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "drop.degreesign")
                .font(.system(size: 44))
                .foregroundStyle(.blue.gradient)
            Text("No results yet").font(.headline)
            Text("Power on the SpinTouch, run a test, and keep it on the results screen. Close the LaMotte app if it's open, then tap Scan.")
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
                Label(store.readings.isEmpty && ble.reading == nil ? "Scan" : "Scan New",
                      systemImage: "antenna.radiowaves.left.and.right")
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
                        if ble.reading?.endSignatureValid == false {
                            Text("⚠︎ End signature mismatch (payload may be truncated)")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("BLE Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: logExportText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(ble.log.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showLog = false }
                }
            }
        }
    }

    private var logExportText: String {
        var s = "SpinTouch BLE Log\n"
        s += ble.log.joined(separator: "\n")
        if let hex = ble.reading?.rawHex {
            s += "\n\nRaw payload (\(hex.count / 2) bytes):\n\(hex)"
            if ble.reading?.endSignatureValid == false {
                s += "\n⚠︎ End signature mismatch (payload may be truncated)"
            }
        }
        return s
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
            Text(value.formattedValue)
                .font(.title3).monospacedDigit().bold()
                .frame(minWidth: 70, alignment: .trailing)
            Text(value.displayUnit)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
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
