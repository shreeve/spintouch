import Foundation

/// One persisted reading (a flat, export-friendly snapshot).
struct StoredReading: Codable, Identifiable {
    var id: UUID = UUID()
    var identityKey: String        // dedupe key (device report time, else received)
    var date: Date                 // effective/report date (user-editable)
    var receivedAt: Date
    var diskSeries: String?
    var sanitizer: String?
    var tempF: Double?
    var lsi: Double?
    var values: [String: Double]   // metric key -> value

    init(reading: SpinTouchReading, tempF: Double?, date: Date, lsi: Double?) {
        self.identityKey = ISO8601DateFormatter().string(from: reading.reportTime ?? reading.receivedAt)
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
}

@MainActor
final class ReadingStore: ObservableObject {
    @Published private(set) var readings: [StoredReading] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("readings.json")
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(readings) {
            try? data.write(to: fileURL, options: .atomic)
        }
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
                    cols.append(String(format: "%g", v))
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

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
