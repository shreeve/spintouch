import Foundation

enum AIReadState {
    case idle
    case loading
    case done(String)
    case failed(String)
}

@MainActor
final class AIReader: ObservableObject {
    @Published var state: AIReadState = .idle

    private var currentRequestID = UUID()

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    func run(reading: SpinTouchReading, settings: AppSettings) async {
        guard settings.hasAPIKey else {
            state = .failed("Add your Anthropic API key in Settings first.")
            return
        }
        let requestID = UUID()
        currentRequestID = requestID
        state = .loading

        // Snapshot everything off the main-actor-isolated settings here.
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = AnthropicService.userPrompt(reading: reading, settings: settings)

        do {
            let text = try await AnthropicService.send(
                apiKey: apiKey, model: model,
                system: AnthropicService.systemPrompt, user: user)
            guard currentRequestID == requestID else { return }
            state = .done(text)
        } catch {
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
    nonisolated static func send(apiKey: String, model: String,
                                 system: String, user: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1200,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AnthropicError.http(http.statusCode, msg)
        }

        // Response: { content: [ { type: "text", text: "..." }, ... ] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AnthropicError.badResponse
        }
        let text = content.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? "No content returned." : text
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
    give approximate amounts of common consumer chemicals (liquid chlorine / \
    bleach, muriatic acid, sodium bicarbonate, soda ash, cyanuric acid, calcium \
    chloride, phosphate remover). If volume is unknown, dose per 10,000 gallons \
    and say so. A small table of "Chemical / Amount / Why" is welcome here.
    4. Re-test — what to re-test and when.

    Safety rules: never advise mixing chemicals together; always add chemical to \
    water (not water to chemical); adjust one thing at a time and re-test; \
    recommend professional help for severe imbalances. Keep it tight.
    """

    @MainActor
    static func userPrompt(reading: SpinTouchReading, settings: AppSettings) -> String {
        var lines: [String] = []
        lines.append("LaMotte SpinTouch reading.")
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
        if let temp = settings.waterTempValue {
            lines.append("Water temperature: \(Int(temp.rounded())) °F.")
        }
        if let lsi = LSI.compute(
            ph: reading.value("ph"), calcium: reading.value("calcium"),
            alkalinity: reading.value("alkalinity"), cya: reading.value("cyanuric_acid"),
            tempF: settings.waterTempValue, salt: reading.value("salt")) {
            lines.append("LSI (Langelier Saturation Index): \(String(format: "%+.2f", lsi.value)) — \(lsi.statusLabel) (ideal −0.3 to +0.3).")
        }

        lines.append("")
        lines.append("Measurements (value, unit, ideal range, status):")
        for v in reading.allValues {
            let unit = v.displayUnit.isEmpty ? "" : " \(v.displayUnit)"
            let ideal = v.idealText.map { " (\($0))" } ?? ""
            lines.append("- \(v.spec.name): \(v.formattedValue)\(unit)\(ideal) [\(v.status.label)]")
        }
        lines.append("")
        lines.append("Give the assessment and dosing steps.")
        return lines.joined(separator: "\n")
    }
}
