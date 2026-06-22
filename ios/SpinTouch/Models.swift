import Foundation

/// Where a measured value sits relative to its advisory ideal range.
enum RangeStatus {
    case low, ok, high, unknown

    var label: String {
        switch self {
        case .low: return "LOW"
        case .ok: return "OK"
        case .high: return "HIGH"
        case .unknown: return "—"
        }
    }
}

/// A single parsed parameter value plus its presentation spec.
struct ParameterValue: Identifiable {
    let spec: ParamSpec
    let value: Double
    let decimals: Int

    var id: String { spec.key }

    var formattedValue: String {
        // Honest, consistent per-metric precision (full precision is retained
        // internally for calculations like LSI / combined chlorine).
        MetricCatalog.format(value, key: spec.key)
    }

    var displayUnit: String { spec.unit ?? "" }

    var status: RangeStatus {
        guard spec.idealLow != nil || spec.idealHigh != nil else { return .unknown }
        if spec.suppressLowWhenZero && value <= 0.0001 { return .unknown }
        if let low = spec.idealLow, value < low { return .low }
        if let high = spec.idealHigh, value > high { return .high }
        return .ok
    }

    var idealText: String? {
        switch (spec.idealLow, spec.idealHigh) {
        case let (l?, h?): return "ideal \(trim(l))–\(trim(h))"
        case let (l?, nil): return "ideal ≥ \(trim(l))"
        case let (nil, h?): return "ideal ≤ \(trim(h))"
        default: return nil
        }
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// A complete decoded SpinTouch test report.
struct SpinTouchReading {
    let parameters: [ParameterValue]
    let derived: [ParameterValue]
    let diskSeries: String?
    let sanitizer: String?
    let numValidResults: Int
    let reportTime: Date?
    let receivedAt: Date
    let rawHex: String
    let endSignatureValid: Bool

    var allValues: [ParameterValue] { parameters + derived }

    /// Look up a measured/derived value by its stable key (e.g. "ph", "salt").
    func value(_ key: String) -> Double? {
        allValues.first { $0.spec.key == key }?.value
    }

    /// Parameters currently outside their ideal range (excludes neutral/unknown).
    var outOfRange: [ParameterValue] {
        allValues.filter { $0.status == .low || $0.status == .high }
    }

    /// Compact rollup like "pH ↑, CYA ↓", or nil if everything is in range.
    var qualitySummary: String? {
        let issues = outOfRange
        guard !issues.isEmpty else { return nil }
        return issues.map { p in
            let arrow = p.status == .high ? "↑" : "↓"
            return "\(Self.shortName(p.spec.key)) \(arrow)"
        }.joined(separator: ", ")
    }

    private static func shortName(_ key: String) -> String {
        [
            "free_chlorine": "FC", "total_chlorine": "TC", "combined_chlorine": "CC",
            "bromine": "Br", "ph": "pH", "alkalinity": "Alk", "calcium": "Ca",
            "cyanuric_acid": "CYA", "fc_cya_ratio": "FC/CYA", "salt": "Salt",
            "copper": "Cu", "iron": "Fe", "phosphate": "Phos", "borate": "Bor",
        ][key] ?? key
    }

    /// Compact "key=value" summary, handy for logging or feeding to an AI later.
    var summaryLine: String {
        allValues.map { "\($0.spec.key)=\($0.formattedValue)\($0.displayUnit)" }
            .joined(separator: " ")
    }
}
