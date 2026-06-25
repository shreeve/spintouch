import Foundation

/// Display metadata for every chartable/exportable metric, keyed by the same
/// stable keys produced by the parser (plus derived metrics, LSI and temp).
struct Metric: Identifiable {
    enum Group: String, CaseIterable {
        case sanitation = "Sanitation"
        case balance = "Balance"
        case metalsNutrients = "Metals & Nutrients"
    }

    enum Kind: String {
        case measured = "Measured"
        case calculated = "Calculated"
    }

    let key: String
    let name: String
    let unit: String?
    let idealLow: Double?
    let idealHigh: Double?
    let decimals: Int
    let group: Group
    let kind: Kind
    let help: String?
    var id: String { key }

    var unitSuffix: String { unit.map { " \($0)" } ?? "" }
}

enum MetricCatalog {
    /// Chemistry metrics in display order (matches the results screen).
    /// `decimals` is the honest display precision for each parameter — the
    /// device can't resolve more than this, so we never imply false precision.
    static let chemistry: [Metric] = [
        Metric(key: "free_chlorine", name: "Free Chlorine", unit: "ppm", idealLow: 1, idealHigh: 3, decimals: 2, group: .sanitation, kind: .measured, help: "sanitizer"),
        Metric(key: "combined_chlorine", name: "Combined Chlorine", unit: "ppm", idealLow: 0, idealHigh: 0.2, decimals: 2, group: .sanitation, kind: .calculated, help: "total − free"),
        Metric(key: "total_chlorine", name: "Total Chlorine", unit: "ppm", idealLow: nil, idealHigh: nil, decimals: 2, group: .sanitation, kind: .measured, help: "free + combined"),
        Metric(key: "cyanuric_acid", name: "Cyanuric Acid", unit: "ppm", idealLow: 30, idealHigh: 50, decimals: 0, group: .sanitation, kind: .measured, help: "stabilizer"),
        Metric(key: "fc_cya_ratio", name: "FC / CYA Ratio", unit: "%", idealLow: 7.5, idealHigh: nil, decimals: 1, group: .sanitation, kind: .calculated, help: "FC vs CYA"),
        Metric(key: "bromine", name: "Bromine", unit: "ppm", idealLow: 2, idealHigh: 4, decimals: 2, group: .sanitation, kind: .measured, help: "active sanitizer"),

        Metric(key: "ph", name: "pH", unit: nil, idealLow: 7.2, idealHigh: 7.6, decimals: 1, group: .balance, kind: .measured, help: "acid/base"),
        Metric(key: "alkalinity", name: "Total Alkalinity", unit: "ppm", idealLow: 80, idealHigh: 120, decimals: 0, group: .balance, kind: .measured, help: "pH buffer"),
        Metric(key: "calcium", name: "Calcium Hardness", unit: "ppm", idealLow: 200, idealHigh: 400, decimals: 0, group: .balance, kind: .measured, help: "scale risk"),
        Metric(key: "salt", name: "Salt", unit: "ppm", idealLow: 2700, idealHigh: 3400, decimals: 0, group: .balance, kind: .measured, help: "SWG level"),

        Metric(key: "copper", name: "Copper", unit: "ppm", idealLow: 0, idealHigh: 0.3, decimals: 2, group: .metalsNutrients, kind: .measured, help: "staining risk"),
        Metric(key: "iron", name: "Iron", unit: "ppm", idealLow: 0, idealHigh: 0.3, decimals: 2, group: .metalsNutrients, kind: .measured, help: "staining risk"),
        Metric(key: "phosphate", name: "Phosphate", unit: "ppb", idealLow: 0, idealHigh: 500, decimals: 0, group: .metalsNutrients, kind: .measured, help: "algae nutrient"),
        Metric(key: "borate", name: "Borate", unit: "ppm", idealLow: 30, idealHigh: 50, decimals: 0, group: .metalsNutrients, kind: .measured, help: "buffer"),
    ]

    static let lsi = Metric(key: "lsi", name: "Water Balance (LSI)", unit: nil, idealLow: -0.3, idealHigh: 0.3, decimals: 2, group: .balance, kind: .calculated, help: "scale/corrosion")
    static let temp = Metric(key: "temp", name: "Water Temperature", unit: "°F", idealLow: nil, idealHigh: nil, decimals: 0, group: .balance, kind: .measured, help: nil)

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
