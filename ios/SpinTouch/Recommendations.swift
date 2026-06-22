import Foundation

enum AdviceSeverity {
    case warning   // out of ideal range, act soon
    case critical  // safety / strongly out of range
}

struct Advice: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let severity: AdviceSeverity
}

/// Deterministic, offline pool-chemistry guidance derived from the reference
/// integration's alert rules. Intentionally conservative and brand-neutral.
enum Recommendations {
    static func evaluate(_ reading: SpinTouchReading) -> [Advice] {
        var out: [Advice] = []
        func v(_ key: String) -> Double? { reading.value(key) }

        if let fc = v("free_chlorine") {
            if fc < 1.0 {
                out.append(Advice(title: "Low Free Chlorine",
                    detail: "FC is \(fmt(fc)) ppm (ideal 1–3). Add liquid chlorine or bleach; re-test in a few hours.",
                    severity: .critical))
            } else if fc > 5.0 {
                out.append(Advice(title: "High Free Chlorine",
                    detail: "FC is \(fmt(fc)) ppm. Avoid swimming above 5 ppm; let it dissipate before re-testing.",
                    severity: .warning))
            }
        }

        if let cc = v("combined_chlorine"), cc > 0.2 {
            out.append(Advice(title: "Chloramines Present",
                detail: "Combined chlorine is \(fmt(cc)) ppm (ideal ≤ 0.2). Shock the pool (breakpoint chlorination).",
                severity: .warning))
        }

        if let ph = v("ph") {
            if ph < 7.2 {
                out.append(Advice(title: "Low pH",
                    detail: "pH is \(fmt(ph)) (ideal 7.2–7.6). Add soda ash (sodium carbonate).",
                    severity: .warning))
            } else if ph > 7.8 {
                out.append(Advice(title: "High pH",
                    detail: "pH is \(fmt(ph)). Add muriatic acid or dry acid (sodium bisulfate).",
                    severity: .warning))
            }
        }

        if let alk = v("alkalinity") {
            if alk < 80 {
                out.append(Advice(title: "Low Alkalinity",
                    detail: "TA is \(fmt0(alk)) ppm (ideal 80–120). Add sodium bicarbonate (baking soda).",
                    severity: .warning))
            } else if alk > 120 {
                out.append(Advice(title: "High Alkalinity",
                    detail: "TA is \(fmt0(alk)) ppm. Lower with muriatic acid and aerate.",
                    severity: .warning))
            }
        }

        if let ca = v("calcium") {
            if ca > 0 && ca < 200 {
                out.append(Advice(title: "Low Calcium Hardness",
                    detail: "CH is \(fmt0(ca)) ppm (ideal 200–400). Add calcium chloride to reduce corrosivity.",
                    severity: .warning))
            } else if ca > 400 {
                out.append(Advice(title: "High Calcium Hardness",
                    detail: "CH is \(fmt0(ca)) ppm. Scale risk; partially drain and refill with softer water.",
                    severity: .warning))
            }
        }

        if let cya = v("cyanuric_acid"), cya > 50 {
            out.append(Advice(title: "High Cyanuric Acid",
                detail: "CYA is \(fmt0(cya)) ppm (ideal 30–50). Chlorine is less effective; dilute with fresh water.",
                severity: .warning))
        }

        if let ratio = v("fc_cya_ratio"), let cya = v("cyanuric_acid"), cya > 30, ratio < 7.5 {
            out.append(Advice(title: "Low FC/CYA Ratio",
                detail: "Ratio is \(fmt(ratio))% (aim ≥ 7.5%). Raise free chlorine or dilute to lower CYA.",
                severity: .warning))
        }

        if let salt = v("salt"), salt > 100 {
            if salt < 2700 {
                out.append(Advice(title: "Low Salt",
                    detail: "Salt is \(fmt0(salt)) ppm (ideal 2700–3400). Add pool salt for the chlorine generator.",
                    severity: .warning))
            } else if salt > 3400 {
                out.append(Advice(title: "High Salt",
                    detail: "Salt is \(fmt0(salt)) ppm. Dilute with fresh water.",
                    severity: .warning))
            }
        }

        if let po4 = v("phosphate"), po4 > 500 {
            out.append(Advice(title: "High Phosphate",
                detail: "Phosphate is \(fmt0(po4)) ppb (act above 500). Use a phosphate remover to limit algae.",
                severity: .warning))
        }

        if let fe = v("iron"), fe > 0.3 {
            out.append(Advice(title: "Iron Present",
                detail: "Iron is \(fmt(fe)) ppm. Use a metal sequestrant to prevent staining.",
                severity: .warning))
        }
        if let cu = v("copper"), cu > 0.3 {
            out.append(Advice(title: "Copper Present",
                detail: "Copper is \(fmt(cu)) ppm. Use a metal sequestrant; check for low pH / ionizers.",
                severity: .warning))
        }

        return out
    }

    private static func fmt(_ d: Double) -> String { String(format: "%.2f", d) }
    private static func fmt0(_ d: Double) -> String { String(format: "%.0f", d) }
}
