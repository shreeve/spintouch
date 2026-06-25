import SwiftUI

struct ContentView: View {
    @StateObject private var ble = BLEManager()
    @StateObject private var settings = AppSettings()
    @StateObject private var aiReader = AIReader()
    @StateObject private var store = ReadingStore()
    @State private var showLog = false
    @State private var showSettings = false
    @State private var showAIDisclosure = false
    @State private var showTrends = false
    @State private var showConditionsEditor = false
    @State private var showDeleteConfirm = false
    @State private var aiExpanded = false
    @State private var aiContentHeight: CGFloat = 1
    @State private var selectedKey: String?       // identityKey of the displayed stored reading
    @State private var editTemp = ""
    @State private var editDate = Date()
    @FocusState private var tempFocused: Bool

    private static let lastViewedKeyDefault = "lastViewedKey"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Layout.cardGap) {
                    if shouldShowStatusCard {
                        statusCard
                            .padding(.horizontal, Layout.pagePadding)
                    }
                    if let reading = displayReading {
                        if isStored {
                            historyNavBar
                                .padding(.horizontal, Layout.pagePadding)
                        }
                        if !reading.endSignatureValid {
                            unverifiedBanner
                                .padding(.horizontal, Layout.pagePadding)
                        }
                        if let lsi = displayLSI(reading) {
                            lsiCard(lsi)
                                .padding(.horizontal, Layout.pagePadding)
                        }
                        resultsSection(reading)
                            .padding(.horizontal, Layout.pagePadding)
                        recommendationsCard(reading)
                            .padding(.horizontal, Layout.pagePadding)
                        metadataCard(reading)
                            .padding(.horizontal, Layout.pagePadding)
                    } else {
                        emptyState
                            .padding(.horizontal, Layout.pagePadding)
                    }
                }
                .padding(.vertical, Layout.pageVerticalPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { restoreSelection() }
            .onChange(of: ble.reading?.receivedAt) { _, _ in handleScan() }
            .onChange(of: editTemp) { _, _ in pushConditions() }
            .onChange(of: editDate) { _, _ in pushConditions() }
            .onChange(of: aiExpanded) { _, expanded in if expanded { onAIExpand() } }
            .onChange(of: selectedKey) { _, _ in refreshAIIfExpanded() }
            .onChange(of: settings.poolType) { _, _ in refreshAIIfExpanded() }
            .onChange(of: settings.poolVolumeGallons) { _, _ in refreshAIIfExpanded() }
            .onChange(of: settings.poolNotes) { _, _ in refreshAIIfExpanded() }
            .onChange(of: settings.model) { _, _ in refreshAIIfExpanded() }
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
            .sheet(isPresented: $showConditionsEditor) {
                ConditionsEditorView(temp: $editTemp, date: $editDate)
            }
            .alert("AI Read", isPresented: $showAIDisclosure) {
                Button("Continue") { settings.aiDisclosureAccepted = true; startInlineAIRead() }
                Button("Cancel", role: .cancel) { aiExpanded = false }
            } message: {
                Text("AI Read sends this reading and your pool settings/notes to Anthropic using your API key. Offline recommendations stay on-device.")
            }
            .confirmationDialog("Delete this reading?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Reading", role: .destructive) { deleteSelectedReading() }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let s = selectedStored {
                    Text("Delete reading sampled at \(s.date.formatted(date: .abbreviated, time: .shortened))? This cannot be undone.")
                }
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

    private var shouldShowStatusCard: Bool {
        if ble.phase.isBusy { return true }
        if case .failed = ble.phase { return true }
        return liveUnverified != nil || selectedStored == nil
    }

    private var displayReading: SpinTouchReading? {
        if let live = liveUnverified { return live }
        return selectedStored?.reconstructedReading()
    }

    private func displayLSI(_ reading: SpinTouchReading) -> LSIResult? {
        if isStored, let lsi = selectedStored?.lsi { return LSIResult(value: lsi) }
        if liveUnverified != nil { return currentLSI(reading) }
        return nil
    }

    private func displayAdvice(_ reading: SpinTouchReading) -> [Advice] {
        Recommendations.evaluate(
            reading,
            poolType: settings.poolType,
            tempF: selectedStored?.tempF ?? settings.waterTempValue,
            lsi: displayLSI(reading))
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

    private func jumpOldest() { select(store.readings.first?.identityKey) }

    private func stepNewer() {
        guard let i = currentIndex, i < store.readings.count - 1 else { return }
        select(store.readings[i + 1].identityKey)
    }

    private func jumpLatest() { select(store.readings.last?.identityKey) }

    @ViewBuilder
    private var historyNavBar: some View {
        if store.readings.count > 1 || !atLatest {
            HStack(spacing: 12) {
                Button { jumpOldest() } label: {
                    Image(systemName: "backward.end.fill")
                }
                .disabled(!canStepOlder)

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

                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Reading", systemImage: "trash")
                    }
                    .disabled(selectedStored == nil)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func deleteSelectedReading() {
        guard let s = selectedStored,
              let i = store.readings.firstIndex(where: { $0.id == s.id }) else { return }
        store.delete(s)
        if store.readings.isEmpty {
            select(nil)
        } else if i < store.readings.count {
            select(store.readings[i].identityKey)
        } else {
            select(store.readings.last?.identityKey)
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
        refreshAIIfExpanded()                                // inputs changed → re-read (cache-aware)
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
                if let reading = displayReading, !ble.phase.isBusy {
                    let summary = WaterQuality.evaluate(
                        reading: reading,
                        advice: displayAdvice(reading),
                        lsi: displayLSI(reading))
                    Text(summary.title).font(.subheadline).bold()
                    Text(summary.subtitle)
                        .font(.caption)
                        .foregroundStyle(summaryColor(summary))
                } else {
                    Text(ble.phase.label).font(.subheadline).bold()
                }
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

    private func summaryColor(_ summary: WaterQualitySummary) -> Color {
        if summary.title == "Water is balanced" { return .green }
        switch summary.severity {
        case .watch: return .blue
        case .minor: return .orange
        case .action: return .orange
        case .critical: return .red
        }
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
        VStack(alignment: .leading, spacing: Layout.sectionGap) {
            HStack(alignment: .firstTextBaseline) {
                Text("Results").font(.headline)
                Spacer()
                if isStored {
                    Button {
                        showConditionsEditor = true
                    } label: {
                        HStack(spacing: 8) {
                            if let volume = compactPoolVolume {
                                Text(volume)
                            }
                            if let temp = selectedStored?.tempF {
                                Label("\(Int(temp.rounded()))°", systemImage: "thermometer.medium")
                            }
                            Label(sampleTimeText, systemImage: "clock")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(Metric.Group.allCases, id: \.self) { group in
                let values = groupedValues(reading, group)
                if !values.isEmpty {
                    VStack(alignment: .leading, spacing: Layout.rowGap) {
                        Text(group.rawValue)
                            .font(.caption).bold()
                            .foregroundStyle(.secondary)
                        ForEach(values) { value in
                            ReadingRow(value: value)
                        }
                    }
                    if group != Metric.Group.allCases.last { Divider() }
                }
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func groupedValues(_ reading: SpinTouchReading, _ group: Metric.Group) -> [ParameterValue] {
        reading.allValues.filter { MetricCatalog.info($0.spec.key)?.group == group }
    }

    /// Called when the AI section is expanded. Gates on the API key and the
    /// one-time data-sharing disclosure, then kicks off a (cache-aware) read.
    private func onAIExpand() {
        guard settings.hasAPIKey else {
            aiExpanded = false        // nothing to show yet — send them to add a key
            showSettings = true
            return
        }
        guard settings.aiDisclosureAccepted else { showAIDisclosure = true; return }
        startInlineAIRead()
    }

    /// Re-read when an input changed while the section is open. The reader serves
    /// an instant cache hit when the prompt is unchanged, so this only spends
    /// tokens when temperature, pool size/type/notes, model, or the reading move.
    private func refreshAIIfExpanded() {
        guard aiExpanded else { return }
        startInlineAIRead()
    }

    private func startInlineAIRead() {
        guard let s = selectedStored, settings.hasAPIKey, settings.aiDisclosureAccepted else { return }
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
        let advice = displayAdvice(reading)
        VStack(alignment: .leading, spacing: Layout.sectionGap) {
            HStack {
                Label("Recommendations", systemImage: "checklist")
                    .font(.headline)
                Spacer()
            }

            standardRecommendations(advice)

            Divider().padding(.vertical, 2)

            DisclosureGroup(isExpanded: $aiExpanded) {
                aiRecommendations
                    .padding(.top, 4)
            } label: {
                Label("AI recommendations", systemImage: "sparkles")
                    .font(.subheadline).bold()
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func standardRecommendations(_ advice: [Advice]) -> some View {
        if advice.isEmpty {
            Label("All measured parameters look in range.", systemImage: "checkmark.seal.fill")
                .font(.subheadline).foregroundStyle(.green)
        } else {
            ForEach(advice) { a in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: adviceIcon(a.severity))
                        .foregroundStyle(adviceColor(a.severity))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.title).font(.subheadline).bold()
                        Text(a.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var aiRecommendations: some View {
        if !settings.hasAPIKey {
            VStack(alignment: .leading, spacing: 8) {
                Label("Add an Anthropic API key in Settings to enable AI recommendations.", systemImage: "key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings") { showSettings = true }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            switch aiReader.state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Asking Claude…").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .streaming(let partial):
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Writing recommendations…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(Markup.plainText(fromHTML: partial))
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            case .done(let text):
                InlineHTMLView(html: Markup.html(from: text), height: $aiContentHeight)
                    .frame(height: aiContentHeight)
                    .frame(maxWidth: .infinity)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Try Again") { startInlineAIRead() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func adviceIcon(_ severity: AdviceSeverity) -> String {
        switch severity {
        case .watch: return "eye"
        case .minor: return "exclamationmark.circle"
        case .action: return "checklist"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    private func adviceColor(_ severity: AdviceSeverity) -> Color {
        switch severity {
        case .watch: return .blue
        case .minor: return .orange
        case .action: return .orange
        case .critical: return .red
        }
    }

    private var compactPoolVolume: String? {
        guard let gallons = settings.poolVolumeValue, gallons > 0 else { return nil }
        if gallons >= 10_000 {
            let k = Double(gallons) / 1000.0
            return k == k.rounded() ? "\(Int(k))k gal" : String(format: "%.1fk gal", k)
        }
        return "\(gallons) gal"
    }

    private var sampleTimeText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(editDate) {
            return editDate.formatted(date: .omitted, time: .shortened)
        }
        if calendar.component(.year, from: editDate) == calendar.component(.year, from: Date()) {
            return editDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
        return editDate.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Conditions (temperature + collection date)

    private var conditionsCard: some View {
        VStack(spacing: Layout.sectionGap) {
            HStack {
                Label("Water Temp", systemImage: "thermometer.medium")
                    .frame(width: Layout.conditionsLabelWidth, alignment: .leading)
                Spacer()
                TextField("—", text: $editTemp)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    .focused($tempFocused)
                Text("°F").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Label("Collected", systemImage: "calendar.badge.clock")
                    .frame(width: Layout.conditionsLabelWidth, alignment: .leading)
                Spacer()
                DatePicker("", selection: $editDate)
                    .labelsHidden()
            }
                .font(.subheadline)
        }
        .font(.subheadline)
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func metadataCard(_ reading: SpinTouchReading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow("Disk series", reading.diskSeries ?? "—")
            metaRow("Sanitizer", reading.sanitizer ?? "—")
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
        .padding(Layout.cardPadding)
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
        .padding(.horizontal, Layout.bottomBarPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(value.spec.name).font(.subheadline).bold()
                    if MetricCatalog.info(value.spec.key)?.kind == .calculated {
                        Image(systemName: "function")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Calculated")
                    }
                }
                Text(value.idealText ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .layoutPriority(1)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.formattedValue)
                    .font(.title3).monospacedDigit().bold()
                    .frame(minWidth: Layout.valueColumnWidth, alignment: .trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(value.displayUnit)
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: Layout.unitColumnWidth, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            statusChip
                .padding(.top, 1)
        }
        .padding(.vertical, Layout.rowVerticalPadding)
    }

    private var statusChip: some View {
        Text(value.status.label)
            .font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(chipColor.opacity(0.18), in: Capsule())
            .foregroundStyle(chipColor)
            .frame(width: Layout.statusColumnWidth)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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

private struct ConditionsEditorView: View {
    @Binding var temp: String
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss
    @FocusState private var tempFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Sample Conditions") {
                    HStack {
                        Image(systemName: "thermometer.medium")
                            .frame(width: 24, alignment: .center)
                        Text("Water Temp")
                        Spacer()
                        TextField("—", text: $temp)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .focused($tempFocused)
                        Text("°F").foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .frame(width: 24, alignment: .center)
                        DatePicker("Time", selection: $date)
                    }
                }
            }
            .navigationTitle("Edit Sample")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { tempFocused = false }
                }
            }
        }
    }
}

private enum Layout {
    static let cardGap: CGFloat = 12
    static let sectionGap: CGFloat = 8
    static let rowGap: CGFloat = 6
    static let cardPadding: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 2
    static let conditionsLabelWidth: CGFloat = 150
    static let pagePadding: CGFloat = 20
    static let pageVerticalPadding: CGFloat = 12
    static let bottomBarPadding: CGFloat = 28
    static let valueColumnWidth: CGFloat = 54
    static let unitColumnWidth: CGFloat = 24
    static let statusColumnWidth: CGFloat = 52
}
