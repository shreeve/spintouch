import Foundation

struct WaterQualitySummary {
    let title: String
    let subtitle: String
    let severity: AdviceSeverity
}

enum WaterQuality {
    static func evaluate(reading: SpinTouchReading,
                         advice: [Advice],
                         lsi: LSIResult?) -> WaterQualitySummary {
        if advice.contains(where: { $0.severity == .critical }) {
            return WaterQualitySummary(
                title: "Action recommended",
                subtitle: compact(advice, fallback: "Review critical chemistry items"),
                severity: .critical)
        }

        let actions = advice.filter { $0.severity == .action }
        if !actions.isEmpty {
            return WaterQualitySummary(
                title: actions.count == 1 ? "1 adjustment suggested" : "\(actions.count) adjustments suggested",
                subtitle: compact(actions, fallback: "Review recommended actions"),
                severity: .action)
        }

        let minor = advice.filter { $0.severity == .minor }
        if !minor.isEmpty {
            return WaterQualitySummary(
                title: minor.count == 1 ? "1 small adjustment suggested" : "\(minor.count) small adjustments suggested",
                subtitle: compact(minor, fallback: "Minor chemistry adjustments"),
                severity: .minor)
        }

        let watch = advice.filter { $0.severity == .watch }
        if !watch.isEmpty {
            return WaterQualitySummary(
                title: watch.count == 1 ? "1 item to watch" : "\(watch.count) items to watch",
                subtitle: compact(watch, fallback: "Watch trend before adjusting"),
                severity: .watch)
        }

        if let lsi, lsi.status != .balanced {
            return WaterQualitySummary(
                title: lsi.statusLabel,
                subtitle: "LSI \(String(format: "%+.2f", lsi.value))",
                severity: .watch)
        }

        return WaterQualitySummary(
            title: "Water is balanced",
            subtitle: lsi.map { "LSI \(String(format: "%+.2f", $0.value))" } ?? "All measured parameters in range",
            severity: .watch)
    }

    private static func compact(_ advice: [Advice], fallback: String) -> String {
        let titles = advice.prefix(2).map(\.title)
        if titles.isEmpty { return fallback }
        if advice.count > 2 { return titles.joined(separator: ", ") + "…" }
        return titles.joined(separator: ", ")
    }
}
