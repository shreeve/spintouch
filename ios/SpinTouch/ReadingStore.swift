import Foundation

/// One persisted reading (a flat, export-friendly snapshot).
struct StoredReading: Codable, Identifiable {
    var id: UUID = UUID()
    var identityKey: String        // dedupe key: hex of the raw 91-byte BLE frame
    var date: Date                 // effective/report date (user-editable)
    var receivedAt: Date
    var diskSeries: String?
    var sanitizer: String?
    var tempF: Double?
    var lsi: Double?
    var values: [String: Double]   // metric key -> value

    init(reading: SpinTouchReading, tempF: Double?, date: Date, lsi: Double?) {
        // Identity is the raw frame: identical frames (a re-scan of the same
        // physical result) dedupe; distinct tests never collide.
        self.identityKey = reading.rawHex
        self.date = date
        self.receivedAt = reading.receivedAt
        self.diskSeries = reading.diskSeries
        self.sanitizer = reading.sanitizer
        self.tempF = tempF
        self.lsi = lsi
        var v: [String: Double] = [:]
        for p in reading.allValues { v[p.spec.key] = p.value }
        self.values = v
    }

    /// Series value for a metric key (handles lsi/temp specially).
    func metricValue(_ key: String) -> Double? {
        switch key {
        case "lsi": return lsi
        case "temp": return tempF
        default: return values[key]
        }
    }

    /// Rebuild a displayable reading from this stored snapshot (for browsing
    /// history with the same UI). Read-only; specs are synthesized from the
    /// metric catalog.
    func reconstructedReading() -> SpinTouchReading {
        var valuesInCatalogOrder: [ParameterValue] = []
        for (i, metric) in MetricCatalog.chemistry.enumerated() {
            guard let v = values[metric.key] else { continue }
            let spec = ParamSpec(paramID: 0, key: metric.key, name: metric.name, unit: metric.unit,
                                 decimals: metric.decimals, minValid: -1e9, maxValid: 1e9,
                                 idealLow: metric.idealLow, idealHigh: metric.idealHigh, sortOrder: i)
            let pv = ParameterValue(spec: spec, value: v, decimals: metric.decimals)
            valuesInCatalogOrder.append(pv)
        }
        return SpinTouchReading(
            parameters: valuesInCatalogOrder, derived: [],
            diskSeries: diskSeries, sanitizer: sanitizer,
            numValidResults: valuesInCatalogOrder.count, reportTime: date, receivedAt: receivedAt,
            rawHex: identityKey, endSignatureValid: true)
    }
}

@MainActor
final class ReadingStore: ObservableObject {
    @Published private(set) var readings: [StoredReading] = []

    private let fileURL: URL
    private let persistQueue = DispatchQueue(label: "com.shreeve.SpinTouch.readingstore")

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("readings.json")
        load()
    }

    /// Insert or update the record for this reading (keyed by report time).
    func upsert(reading: SpinTouchReading, tempF: Double?, date: Date, lsi: Double?) {
        let rec = StoredReading(reading: reading, tempF: tempF, date: date, lsi: lsi)
        if let i = readings.firstIndex(where: { $0.identityKey == rec.identityKey }) {
            let keepID = readings[i].id
            var updated = rec
            updated.id = keepID
            readings[i] = updated
        } else {
            readings.append(rec)
        }
        readings.sort { $0.date < $1.date }
        save()
    }

    /// Edit a stored reading's temperature and/or collection date, recomputing
    /// LSI and re-sorting (collection date can change order).
    func updateConditions(identityKey: String, tempF: Double?, date: Date) {
        guard let i = readings.firstIndex(where: { $0.identityKey == identityKey }) else { return }
        var e = readings[i]
        e.tempF = tempF
        e.date = date
        e.lsi = LSI.compute(
            ph: e.values["ph"], calcium: e.values["calcium"],
            alkalinity: e.values["alkalinity"], cya: e.values["cyanuric_acid"],
            tempF: tempF, salt: e.values["salt"])?.value
        readings[i] = e
        readings.sort { $0.date < $1.date }
        save()
    }

    func delete(_ rec: StoredReading) {
        readings.removeAll { $0.id == rec.id }
        save()
    }

    func clear() {
        readings.removeAll()
        save()
    }

    /// Time-ordered (date, value) pairs for a metric.
    func series(for key: String) -> [(date: Date, value: Double)] {
        readings.compactMap { r in r.metricValue(key).map { (r.date, $0) } }
    }

    func latest(for key: String) -> Double? { series(for: key).last?.value }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        readings = (try? decoder.decode([StoredReading].self, from: data)) ?? []
    }

    private func save() {
        // Snapshot on the main actor, then encode + write on a serial queue so
        // writes are ordered (no out-of-order/stale persistence) and never block UI.
        let snapshot = readings
        let url = fileURL
        persistQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("ReadingStore save failed: \(error)")
            }
        }
    }

    /// Block until pending writes have flushed to disk. Call on app backgrounding
    /// so the most recent scan/edit survives an immediate termination.
    func flush() {
        persistQueue.sync {}
    }

    // MARK: - Export

    func exportJSONURL() throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(readings)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spintouch_readings.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func exportCSVURL() throws -> URL {
        var header = ["date", "received_at", "disk_series", "sanitizer"]
        header += MetricCatalog.csvKeys
        var rows = [header.joined(separator: ",")]

        let iso = ISO8601DateFormatter()
        for r in readings {
            var cols = [
                iso.string(from: r.date),
                iso.string(from: r.receivedAt),
                csvEscape(r.diskSeries ?? ""),
                csvEscape(r.sanitizer ?? ""),
            ]
            for key in MetricCatalog.csvKeys {
                if let v = r.metricValue(key) {
                    cols.append(String(format: "%g", locale: Self.posix, v))
                } else {
                    cols.append("")
                }
            }
            rows.append(cols.joined(separator: ","))
        }

        let csv = rows.joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spintouch_readings.csv")
        try csv.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
