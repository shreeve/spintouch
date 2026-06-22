import Foundation

/// Display metadata for every chartable/exportable metric, keyed by the same
/// stable keys produced by the parser (plus derived metrics, LSI and temp).
struct Metric: Identifiable {
    let key: String
    let name: String
    let unit: String?
    let idealLow: Double?
    let idealHigh: Double?
    var id: String { key }

    var unitSuffix: String { unit.map { " \($0)" } ?? "" }
}

enum MetricCatalog {
    /// Chemistry metrics in display order (matches the results screen).
    static let chemistry: [Metric] = [
        Metric(key: "free_chlorine", name: "Free Chlorine", unit: "ppm", idealLow: 1, idealHigh: 3),
        Metric(key: "total_chlorine", name: "Total Chlorine", unit: "ppm", idealLow: nil, idealHigh: nil),
        Metric(key: "combined_chlorine", name: "Combined Chlorine", unit: "ppm", idealLow: 0, idealHigh: 0.2),
        Metric(key: "bromine", name: "Bromine", unit: "ppm", idealLow: 2, idealHigh: 4),
        Metric(key: "ph", name: "pH", unit: nil, idealLow: 7.2, idealHigh: 7.6),
        Metric(key: "alkalinity", name: "Total Alkalinity", unit: "ppm", idealLow: 80, idealHigh: 120),
        Metric(key: "calcium", name: "Calcium Hardness", unit: "ppm", idealLow: 200, idealHigh: 400),
        Metric(key: "cyanuric_acid", name: "Cyanuric Acid", unit: "ppm", idealLow: 30, idealHigh: 50),
        Metric(key: "fc_cya_ratio", name: "FC / CYA Ratio", unit: "%", idealLow: 7.5, idealHigh: nil),
        Metric(key: "salt", name: "Salt", unit: "ppm", idealLow: 2700, idealHigh: 3400),
        Metric(key: "copper", name: "Copper", unit: "ppm", idealLow: 0, idealHigh: 0.3),
        Metric(key: "iron", name: "Iron", unit: "ppm", idealLow: 0, idealHigh: 0.3),
        Metric(key: "phosphate", name: "Phosphate", unit: "ppb", idealLow: 0, idealHigh: 100),
        Metric(key: "borate", name: "Borate", unit: "ppm", idealLow: 30, idealHigh: 50),
    ]

    static let lsi = Metric(key: "lsi", name: "Water Balance (LSI)", unit: nil, idealLow: -0.3, idealHigh: 0.3)
    static let temp = Metric(key: "temp", name: "Water Temperature", unit: "°F", idealLow: nil, idealHigh: nil)

    /// Everything that can be charted, LSI first.
    static let all: [Metric] = [lsi] + chemistry + [temp]

    static func info(_ key: String) -> Metric? { all.first { $0.key == key } }

    /// Stable column order for CSV export.
    static let csvKeys: [String] = chemistry.map(\.key) + ["lsi", "temp"]
}
