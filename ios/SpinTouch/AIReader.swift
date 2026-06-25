import Foundation

enum AIReadState {
    case idle
    case loading
    case streaming(String)   // accumulated text so far
    case done(String)
    case failed(String)
}

extension AIReadState {
    var text: String? {
        switch self {
        case .streaming(let text), .done(let text): return text
        default: return nil
        }
    }
}

@MainActor
final class AIReader: ObservableObject {
    @Published var state: AIReadState = .idle

    private var currentRequestID = UUID()
    private var runTask: Task<Void, Never>?
    private let cache = AIReadCache()

    func clearCache() { cache.clear() }
    func flushCache() { cache.flush() }
    var cacheCount: Int { cache.count }

    var isLoading: Bool {
        switch state {
        case .loading, .streaming: return true
        default: return false
        }
    }

    /// Start a read, cancelling any in-flight one (frees its network/tokens).
    func start(reading: SpinTouchReading, settings: AppSettings, collectionDate: Date, tempF: Double?) {
        runTask?.cancel()
        // Claim the request ID synchronously so any token/state from the
        // just-cancelled task is rejected by its `currentRequestID` guard.
        let requestID = UUID()
        currentRequestID = requestID
        runTask = Task { [weak self] in
            await self?.run(requestID: requestID, reading: reading, settings: settings,
                            collectionDate: collectionDate, tempF: tempF)
        }
    }

    /// Cancel an in-flight read (e.g. the AI section was collapsed or left).
    /// A completed `.done` result is preserved so re-expanding shows it instantly.
    func cancel() {
        runTask?.cancel()
        runTask = nil
        currentRequestID = UUID()
        if isLoading { state = .idle }
    }

    private func run(requestID: UUID, reading: SpinTouchReading, settings: AppSettings, collectionDate: Date, tempF: Double?) async {
        guard settings.hasAPIKey else {
            state = .failed("Add your Anthropic API key in Settings first.")
            return
        }
        guard currentRequestID == requestID else { return }

        // Snapshot everything off the main-actor-isolated settings here.
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = AnthropicService.systemPrompt
        let user = AnthropicService.userPrompt(reading: reading, settings: settings, collectionDate: collectionDate, tempF: tempF)

        // Return a memoized read instantly when the exact inputs repeat.
        let cacheKey = AIReadCache.key(model: model, system: system, user: user)
        if let cached = cache.get(cacheKey) {
            state = .done(cached)
            return
        }

        state = .loading
        var accumulated = ""
        var lastPublished = 0
        do {
            for try await delta in AnthropicService.stream(
                apiKey: apiKey, model: model,
                system: system, user: user) {
                guard currentRequestID == requestID else { return }
                accumulated += delta
                // Coalesce UI updates to avoid main-actor churn on every token.
                if accumulated.count - lastPublished >= 16 {
                    lastPublished = accumulated.count
                    state = .streaming(accumulated)
                }
            }
            guard currentRequestID == requestID else { return }
            if accumulated.isEmpty {
                state = .failed("No content returned.")
            } else {
                cache.set(cacheKey, accumulated)
                state = .done(accumulated)
            }
        } catch {
            // A cancelled request (user started a new one) is not an error.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            guard currentRequestID == requestID else { return }
            state = .failed(error.localizedDescription)
        }
    }
}

enum AnthropicError: LocalizedError {
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "Claude API error \(code): \(body)"
        case .badResponse: return "Unexpected response from Claude."
        }
    }
}

enum AnthropicService {
    /// Server-sent-events stream of text deltas from the Anthropic Messages API.
    nonisolated static func stream(apiKey: String, model: String,
                                   system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.timeoutInterval = 60
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.httpBody = try JSONSerialization.data(withJSONObject: [
                        "model": model,
                        "max_tokens": 900,
                        "stream": true,
                        "system": system,
                        "messages": [["role": "user", "content": user]],
                    ])

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var data = Data()
                        for try await b in bytes { data.append(b) }
                        throw AnthropicError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { continuation.finish(); return }
                        guard let d = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                        else { continue }

                        switch obj["type"] as? String {
                        case "content_block_delta":
                            if let delta = obj["delta"] as? [String: Any],
                               (delta["type"] as? String) == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }
                        case "message_stop":
                            continuation.finish()
                            return
                        case "error":
                            let msg = (obj["error"] as? [String: Any])?["message"] as? String ?? "stream error"
                            throw AnthropicError.http(http.statusCode, msg)
                        default:
                            break  // ignore message_start, ping, content_block_start/stop, message_delta
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static let systemPrompt = """
    You are a professional pool and spa water-chemistry advisor. You receive \
    readings from a LaMotte SpinTouch photometer. Be concise, practical, and \
    safety-conscious.

    Respond with a clean HTML fragment only. Do NOT include <html>, <head>, \
    <body>, <style>, or <script> tags, and do NOT use inline style attributes or \
    external resources. Use semantic tags: <h2> for section titles, <p>, \
    <ul>/<li>, <ol>/<li>, <strong>, and a <table> (with <thead>/<tbody>) when a \
    dosing breakdown is clearer as a table.

    Sections (each an <h2>):
    1. Overall — one or two sentences on whether the water is balanced.
    2. Out of range — list each parameter that is off, with why it matters. If an \
    LSI value is provided, comment on water balance (corrosive vs scaling).
    3. What to do — concrete, ordered dosing steps (<ol>). Use the pool volume to \
    give homeowner-friendly product amounts, not lab units. Prefer gallons, \
    quarts, cups, fluid ounces, pounds, or ounces of common pool products. \
    Examples: "add 1/2 gallon of 10% liquid chlorine" or "add 1 quart of 31.45% \
    muriatic acid". Do NOT answer in mg/L, mg/mL, moles, or abstract \
    concentration changes unless also converted to a real product amount. If \
    volume is unknown, dose per 10,000 gallons and say so. A small table of \
    "Chemical / Amount / Why" is welcome here.
    4. Re-test — what to re-test and when.

    Safety rules: never advise mixing chemicals together; always add chemical to \
    water (not water to chemical); adjust one thing at a time and re-test; \
    recommend professional help for severe imbalances.

    Be brief and skip filler — short sentences, only the parameters that matter.
    """

    private static let collectionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    @MainActor
    static func userPrompt(reading: SpinTouchReading, settings: AppSettings, collectionDate: Date, tempF: Double?) -> String {
        var lines: [String] = []
        lines.append("LaMotte SpinTouch reading.")
        lines.append("Sample collected: \(collectionFormatter.string(from: collectionDate)).")
        if let disk = reading.diskSeries { lines.append("Disk series: \(disk).") }
        if let san = reading.sanitizer { lines.append("Sanitizer: \(san).") }
        if let vol = settings.poolVolumeValue {
            lines.append("Pool volume: \(vol) gallons.")
        } else {
            lines.append("Pool volume: unknown (dose per 10,000 gallons).")
        }
        let type = settings.poolType.trimmingCharacters(in: .whitespaces)
        if !type.isEmpty { lines.append("Pool type (user-set): \(type).") }
        let notes = settings.poolNotes.trimmingCharacters(in: .whitespaces)
        if !notes.isEmpty { lines.append("Notes: \(notes).") }
        if let temp = tempF {
            lines.append("Water temperature: \(Int(temp.rounded())) °F.")
        }
        if let lsi = LSI.compute(
            ph: reading.value("ph"), calcium: reading.value("calcium"),
            alkalinity: reading.value("alkalinity"), cya: reading.value("cyanuric_acid"),
            tempF: tempF, salt: reading.value("salt")) {
            lines.append("LSI (Langelier Saturation Index): \(String(format: "%+.2f", lsi.value)) — \(lsi.statusLabel) (ideal −0.3 to +0.3).")
        }

        lines.append("")
        lines.append("Measurements (value, unit, ideal range, status):")
        for v in reading.allValues {
            let unit = v.displayUnit.isEmpty ? "" : " \(v.displayUnit)"
            let ideal = v.idealText.map { " (\($0))" } ?? ""
            let kind = MetricCatalog.info(v.spec.key)?.kind.rawValue ?? "Measured"
            lines.append("- \(v.spec.name): \(v.formattedValue)\(unit)\(ideal) [\(v.status.label), \(kind)]")
        }

        let lsi = LSI.compute(
            ph: reading.value("ph"), calcium: reading.value("calcium"),
            alkalinity: reading.value("alkalinity"), cya: reading.value("cyanuric_acid"),
            tempF: tempF, salt: reading.value("salt"))
        let advice = Recommendations.evaluate(reading, poolType: settings.poolType, tempF: tempF, lsi: lsi)
        if !advice.isEmpty {
            lines.append("")
            lines.append("Offline deterministic recommendations (use as context; explain/refine, don't contradict without reason):")
            for a in advice {
                lines.append("- \(a.title) [\(a.severity)]: \(a.detail)")
            }
        }
        lines.append("")
        lines.append("Explain this test and suggest next steps.")
        return lines.joined(separator: "\n")
    }
}
