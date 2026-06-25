import Foundation

enum AdviceSeverity {
    case watch     // marginal or context says no immediate correction
    case minor     // small adjustment / keep an eye on it
    case action    // correction recommended
    case critical  // safety / strongly out of range
}

struct Advice: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let severity: AdviceSeverity
    let affectedKeys: [String]
}

/// Deterministic, offline pool-chemistry guidance derived from the reference
/// integration's alert rules. Intentionally conservative and brand-neutral.
enum Recommendations {
    static func evaluate(_ reading: SpinTouchReading,
                         poolType: String = "Chlorine",
                         tempF: Double? = nil,
                         lsi: LSIResult? = nil) -> [Advice] {
        var out: [Advice] = []
        func v(_ key: String) -> Double? { reading.value(key) }
        let pool = poolType.lowercased()
        let isSalt = pool.contains("salt")
        let isBromine = pool.contains("bromine")
        let lsiBalanced = lsi?.status == .balanced

        if let fc = v("free_chlorine") {
            if !isBromine && fc < 1.0 {
                out.append(Advice(title: "Low Free Chlorine",
                    detail: "FC is \(fmt(fc)) ppm (ideal 1–3). Add liquid chlorine or bleach; re-test in a few hours.",
                    severity: .critical,
                    affectedKeys: ["free_chlorine"]))
            } else if fc > 5.0 {
                out.append(Advice(title: "High Free Chlorine",
                    detail: "FC is \(fmt(fc)) ppm. Avoid swimming above 5 ppm; let it dissipate before re-testing.",
                    severity: .action,
                    affectedKeys: ["free_chlorine"]))
            } else if !isBromine, let cya = v("cyanuric_acid"), cya >= 30, let ratio = v("fc_cya_ratio"), ratio < 7.5 {
                let severity: AdviceSeverity = ratio >= 6.5 ? .watch : .minor
                out.append(Advice(title: "Free Chlorine Slightly Low for CYA",
                    detail: "FC/CYA is \(fmt(ratio))% (aim about 7.5%). This is marginal; raise FC a little or re-test before heavy use.",
                    severity: severity,
                    affectedKeys: ["free_chlorine", "cyanuric_acid", "fc_cya_ratio"]))
            }
        }

        if let cc = v("combined_chlorine"), cc > 0.2 {
            out.append(Advice(title: "Chloramines Present",
                detail: "Combined chlorine is \(fmt(cc)) ppm (ideal ≤ 0.2). Shock the pool (breakpoint chlorination).",
                severity: cc > 0.5 ? .action : .minor,
                affectedKeys: ["combined_chlorine"]))
        }

        if let ph = v("ph") {
            if ph < 7.2 {
                out.append(Advice(title: "Low pH",
                    detail: "pH is \(fmt(ph)) (ideal 7.2–7.6). Add soda ash (sodium carbonate).",
                    severity: .action,
                    affectedKeys: ["ph"]))
            } else if ph > 7.8 {
                out.append(Advice(title: "High pH",
                    detail: "pH is \(fmt(ph)). Add muriatic acid or dry acid (sodium bisulfate).",
                    severity: .action,
                    affectedKeys: ["ph"]))
            }
        }

        if let alk = v("alkalinity") {
            if alk < 80 {
                out.append(Advice(title: "Low Alkalinity",
                    detail: "TA is \(fmt0(alk)) ppm (ideal 80–120). Add sodium bicarbonate (baking soda).",
                    severity: .minor,
                    affectedKeys: ["alkalinity"]))
            } else if alk > 120 {
                if alk <= 140 && lsiBalanced {
                    let saltText = isSalt ? " For saltwater pools, modestly lower TA can reduce pH drift, but" : ""
                    out.append(Advice(title: "Alkalinity Slightly Elevated",
                        detail: "TA is \(fmt0(alk)) ppm, but pH and LSI are balanced.\(saltText) no immediate correction is needed unless pH keeps rising.",
                        severity: .watch,
                        affectedKeys: ["alkalinity", "ph", "lsi"]))
                } else {
                    out.append(Advice(title: "High Alkalinity",
                        detail: "TA is \(fmt0(alk)) ppm. Lower gradually with muriatic acid and aeration, watching pH and LSI.",
                        severity: .minor,
                        affectedKeys: ["alkalinity", "ph", "lsi"]))
                }
            }
        }

        if let ca = v("calcium") {
            if ca > 0 && ca < 200 {
                out.append(Advice(title: "Low Calcium Hardness",
                    detail: "CH is \(fmt0(ca)) ppm (ideal 200–400). Add calcium chloride to reduce corrosivity.",
                    severity: lsi?.status == .corrosive ? .action : .minor,
                    affectedKeys: ["calcium", "lsi"]))
            } else if ca > 400 {
                out.append(Advice(title: "High Calcium Hardness",
                    detail: "CH is \(fmt0(ca)) ppm. Scale risk; partially drain and refill with softer water.",
                    severity: lsi?.status == .scaleForming ? .action : .minor,
                    affectedKeys: ["calcium", "lsi"]))
            }
        }

        if let cya = v("cyanuric_acid"), cya > 50 {
            out.append(Advice(title: "High Cyanuric Acid",
                detail: "CYA is \(fmt0(cya)) ppm (ideal 30–50). Chlorine is less effective; dilute with fresh water.",
                severity: cya > 80 ? .action : .minor,
                affectedKeys: ["cyanuric_acid"]))
        }

        if let salt = v("salt"), salt > 100 {
            if salt < 2700 {
                out.append(Advice(title: "Low Salt",
                    detail: "Salt is \(fmt0(salt)) ppm (ideal 2700–3400). Add pool salt for the chlorine generator.",
                    severity: isSalt ? .action : .watch,
                    affectedKeys: ["salt"]))
            } else if salt > 3400 {
                out.append(Advice(title: "High Salt",
                    detail: "Salt is \(fmt0(salt)) ppm. Dilute with fresh water.",
                    severity: isSalt ? .minor : .watch,
                    affectedKeys: ["salt"]))
            }
        }

        if let po4 = v("phosphate"), po4 > 500 {
            out.append(Advice(title: "High Phosphate",
                detail: "Phosphate is \(fmt0(po4)) ppb (act above 500). Use a phosphate remover to limit algae.",
                severity: po4 > 1000 ? .action : .minor,
                affectedKeys: ["phosphate"]))
        }

        if let fe = v("iron"), fe > 0.3 {
            out.append(Advice(title: "Iron Present",
                detail: "Iron is \(fmt(fe)) ppm. Use a metal sequestrant to prevent staining.",
                severity: .minor,
                affectedKeys: ["iron"]))
        }
        if let cu = v("copper"), cu > 0.3 {
            out.append(Advice(title: "Copper Present",
                detail: "Copper is \(fmt(cu)) ppm. Use a metal sequestrant; check for low pH / ionizers.",
                severity: .minor,
                affectedKeys: ["copper"]))
        }

        if let tempF, tempF < 65, lsi?.status == .corrosive {
            out.append(Advice(title: "Cold Water Corrosion Risk",
                detail: "Cold water lowers LSI. Avoid lowering pH or alkalinity further until balance is corrected.",
                severity: .watch,
                affectedKeys: ["temp", "lsi"]))
        }

        return out
    }

    private static func fmt(_ d: Double) -> String { String(format: "%.2f", d) }
    private static func fmt0(_ d: Double) -> String { String(format: "%.0f", d) }
}
