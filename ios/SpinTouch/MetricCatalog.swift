import Foundation

/// Display metadata for every chartable/exportable metric, keyed by the same
/// stable keys produced by the parser (plus derived metrics, LSI and temp).
struct Metric: Identifiable {
    let key: String
    let name: String
    let unit: String?
    let idealLow: Double?
    let idealHigh: Double?
    let decimals: Int
    var id: String { key }

    var unitSuffix: String { unit.map { " \($0)" } ?? "" }
}

enum MetricCatalog {
    /// Chemistry metrics in display order (matches the results screen).
    /// `decimals` is the honest display precision for each parameter — the
    /// device can't resolve more than this, so we never imply false precision.
    static let chemistry: [Metric] = [
        Metric(key: "free_chlorine", name: "Free Chlorine", unit: "ppm", idealLow: 1, idealHigh: 3, decimals: 2),
        Metric(key: "total_chlorine", name: "Total Chlorine", unit: "ppm", idealLow: nil, idealHigh: nil, decimals: 2),
        Metric(key: "combined_chlorine", name: "Combined Chlorine", unit: "ppm", idealLow: 0, idealHigh: 0.2, decimals: 2),
        Metric(key: "bromine", name: "Bromine", unit: "ppm", idealLow: 2, idealHigh: 4, decimals: 2),
        Metric(key: "ph", name: "pH", unit: nil, idealLow: 7.2, idealHigh: 7.6, decimals: 1),
        Metric(key: "alkalinity", name: "Total Alkalinity", unit: "ppm", idealLow: 80, idealHigh: 120, decimals: 0),
        Metric(key: "calcium", name: "Calcium Hardness", unit: "ppm", idealLow: 200, idealHigh: 400, decimals: 0),
        Metric(key: "cyanuric_acid", name: "Cyanuric Acid", unit: "ppm", idealLow: 30, idealHigh: 50, decimals: 0),
        Metric(key: "fc_cya_ratio", name: "FC / CYA Ratio", unit: "%", idealLow: 7.5, idealHigh: nil, decimals: 1),
        Metric(key: "salt", name: "Salt", unit: "ppm", idealLow: 2700, idealHigh: 3400, decimals: 0),
        Metric(key: "copper", name: "Copper", unit: "ppm", idealLow: 0, idealHigh: 0.3, decimals: 2),
        Metric(key: "iron", name: "Iron", unit: "ppm", idealLow: 0, idealHigh: 0.3, decimals: 2),
        Metric(key: "phosphate", name: "Phosphate", unit: "ppb", idealLow: 0, idealHigh: 500, decimals: 0),
        Metric(key: "borate", name: "Borate", unit: "ppm", idealLow: 30, idealHigh: 50, decimals: 0),
    ]

    static let lsi = Metric(key: "lsi", name: "Water Balance (LSI)", unit: nil, idealLow: -0.3, idealHigh: 0.3, decimals: 2)
    static let temp = Metric(key: "temp", name: "Water Temperature", unit: "°F", idealLow: nil, idealHigh: nil, decimals: 0)

    /// Everything that can be charted, LSI first.
    static let all: [Metric] = [lsi] + chemistry + [temp]

    static func info(_ key: String) -> Metric? { all.first { $0.key == key } }

    /// Honest display precision for a metric key (falls back to 2).
    static func decimals(_ key: String) -> Int { info(key)?.decimals ?? 2 }

    /// Format a value at its metric's display precision.
    static func format(_ value: Double, key: String) -> String {
        String(format: "%.\(decimals(key))f", value)
    }

    /// Stable column order for CSV export.
    static let csvKeys: [String] = chemistry.map(\.key) + ["lsi", "temp"]
}
