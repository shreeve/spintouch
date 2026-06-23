import Foundation
import CryptoKit

/// Persistent memoization of AI reads, keyed by the exact prompt inputs (model +
/// system + user prompt). Identical inputs return instantly; changing an input
/// that affects the prompt (e.g. water temperature) yields a new, separately
/// cached entry. Bounded with simple LRU eviction.
@MainActor
final class AIReadCache {
    private struct Entry: Codable {
        let key: String
        let text: String
        var date: Date
    }

    private var entries: [Entry] = []
    private let fileURL: URL
    private let maxEntries = 50
    private let persistQueue = DispatchQueue(label: "com.shreeve.SpinTouch.aicache")

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("ai_cache.json")
        load()
    }

    /// Stable content hash across launches.
    static func key(model: String, system: String, user: String) -> String {
        let joined = model + "\u{1}" + system + "\u{1}" + user
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func get(_ key: String) -> String? {
        guard let i = entries.firstIndex(where: { $0.key == key }) else { return nil }
        // LRU touch: move to the end.
        var entry = entries.remove(at: i)
        entry.date = Date()
        entries.append(entry)
        save()
        return entry.text
    }

    func set(_ key: String, _ text: String) {
        entries.removeAll { $0.key == key }
        entries.append(Entry(key: key, text: text, date: Date()))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        save()
    }

    var count: Int { entries.count }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    private func save() {
        let snapshot = entries
        let url = fileURL
        persistQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
