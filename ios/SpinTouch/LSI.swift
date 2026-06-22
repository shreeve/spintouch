import Foundation

/// Langelier Saturation Index — water balance.
///   -0.3 … +0.3  balanced
///   < -0.3       corrosive (will dissolve plaster/metal)
///   > +0.3       scale-forming (will deposit calcium)
struct LSIResult {
    let value: Double

    enum Status { case corrosive, balanced, scaleForming }

    var status: Status {
        if value < -0.3 { return .corrosive }
        if value > 0.3 { return .scaleForming }
        return .balanced
    }

    var statusLabel: String {
        switch status {
        case .corrosive: return "Corrosive"
        case .balanced: return "Balanced"
        case .scaleForming: return "Scale-forming"
        }
    }
}

enum LSI {
    /// Standard LSI:  pH + TF + CF + AF − TDSF
    ///   CF = log10(CalciumHardness) − 0.4
    ///   AF = log10(carbonate alkalinity), where carbonate alk = TA − CYA correction
    ///   TDSF = 12.1 (or 12.2 when TDS ≥ 1000; salt used as a TDS proxy)
    static func compute(ph: Double?, calcium: Double?, alkalinity: Double?,
                        cya: Double?, tempF: Double?, salt: Double?) -> LSIResult? {
        guard let ph, let ca = calcium, let alk = alkalinity, let tempF,
              ca > 0, alk > 0 else { return nil }

        let tf = temperatureFactor(tempF: tempF)
        let cf = log10(ca) - 0.4
        let carbonateAlk = max(1, alk - cyaCorrection(ph: ph, cya: cya ?? 0))
        let af = log10(carbonateAlk)
        let tdsf = (salt ?? 0) >= 1000 ? 12.2 : 12.1

        let value = ph + tf + cf + af - tdsf
        return LSIResult(value: (value * 100).rounded() / 100)
    }

    /// Temperature factor table (matches the standard LSI breakpoints).
    static func temperatureFactor(tempF: Double) -> Double {
        let c = (tempF - 32) * 5 / 9
        if c <= 0 { return 0.0 }
        if c <= 4 { return 0.1 }
        if c <= 8 { return 0.2 }
        if c <= 12 { return 0.3 }
        if c <= 16 { return 0.4 }
        if c <= 19 { return 0.5 }
        if c <= 24 { return 0.6 }
        if c <= 29 { return 0.7 }
        if c <= 34 { return 0.8 }
        return 0.9
    }

    /// Portion of cyanuric acid that borrows from total alkalinity. Empirical,
    /// pH-dependent (~0.27 at pH 7.0 up to ~0.35 at pH 8.0).
    private static func cyaCorrection(ph: Double, cya: Double) -> Double {
        guard cya > 0 else { return 0 }
        let clampedPH = min(8.0, max(7.0, ph))
        let factor = 0.27 + (clampedPH - 7.0) * 0.08
        return cya * factor
    }
}
