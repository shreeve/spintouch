# SpinTouch iOS — Improvement Plan (for the implementing agent)

This is a self-contained spec. You do **not** need any external chat context.
It describes a set of improvements to the iOS app in `ios/SpinTouch/`, derived
from reviewing the reference Home Assistant / ESPHome integration in
`misc/lamotte-spintouch/` (read-only reference; do not modify it).

The iOS app already faithfully ports the hard parts (BLE UUIDs, 91-byte parser,
param-ID catalog, disk/sanitizer maps, derived values, LSI, persistence/export).
These tasks add the remaining genuinely-useful behaviors the reference repo has
that the iOS app does not yet have.

Implement tasks in order. Each task lists: **Why**, **Files**, **Change**, and
**Acceptance**. Keep the existing code style (no narrating comments, SwiftUI
patterns already in the repo). After editing, ensure the project still builds and
fix any compiler/linter errors you introduce.

> Xcode note: Task 5 adds a **new Swift file** (`Recommendations.swift`). You must
> also register it in `ios/SpinTouch.xcodeproj/project.pbxproj` (add a
> `PBXFileReference`, a `PBXBuildFile`, an entry in the `SpinTouch` group, and an
> entry in the `Sources` build phase) the same way the other `.swift` files are
> registered. Mirror an existing file like `LSI.swift` exactly.

---

## Task 1 — Fix the Phosphate "high" threshold (100 → 500 ppb)

**Why:** Phosphate below ~500 ppb is fine; remediation is only warranted above
500 ppb (LaMotte 203/204 disks read 0–2000 ppb). The reference
`automations/chemistry_alerts.yaml` alerts at `> 500`. The current `idealHigh: 100`
flags HIGH almost always.

**Files:** `ios/SpinTouch/SpinTouchProtocol.swift`, `ios/SpinTouch/MetricCatalog.swift`

**Change A** — in `SpinTouchProtocol.swift`, the phosphate `ParamSpec`:

```swift
add(ParamSpec(paramID: 0x0E, key: "phosphate", name: "Phosphate", unit: "ppb",
              decimals: 0, minValid: 0, maxValid: 2500, idealLow: 0, idealHigh: 500, sortOrder: 12))
```

**Change B** — in `MetricCatalog.swift`, the phosphate `Metric`:

```swift
Metric(key: "phosphate", name: "Phosphate", unit: "ppb", idealLow: 0, idealHigh: 500),
```

**Acceptance:** A phosphate reading of, say, 250 ppb shows status `OK`; 600 ppb
shows `HIGH`.

---

## Task 2 — Don't flag "LOW" for parameters that are simply not in use

**Why:** `ParameterValue.status` returns `.low` whenever `value < idealLow`. On a
freshwater (non-salt) pool, `salt ≈ 0` → "LOW"; an un-borated pool shows
`borate = 0` → "LOW"; a bromine-free pool shows `bromine = 0` → "LOW". These are
"not applicable", not problems. The reference gates these (e.g. salt alert only
fires when `salt > 100`, FC/CYA only when `CYA > 30`). We replicate that by
returning `.unknown` (neutral) when an optional parameter reads ~0.

Keep flagging genuinely-dangerous lows: **free chlorine, pH, alkalinity, calcium**
must still report `.low` at low values.

**Files:** `ios/SpinTouch/SpinTouchProtocol.swift` (add computed flag on `ParamSpec`),
`ios/SpinTouch/Models.swift` (use it in `status`).

**Change A** — add a computed property to `ParamSpec` in `SpinTouchProtocol.swift`
(inside the `struct ParamSpec` body, after `var id: String { key }`):

```swift
    /// Parameters that are optional/disk- or pool-dependent: a ~0 reading means
    /// "not in use", not "too low". Used to suppress a misleading LOW status.
    var suppressLowWhenZero: Bool {
        ["bromine", "cyanuric_acid", "salt", "borate"].contains(key)
    }
```

**Change B** — in `Models.swift`, update `ParameterValue.status`:

```swift
    var status: RangeStatus {
        guard spec.idealLow != nil || spec.idealHigh != nil else { return .unknown }
        if spec.suppressLowWhenZero && value <= 0.0001 { return .unknown }
        if let low = spec.idealLow, value < low { return .low }
        if let high = spec.idealHigh, value > high { return .high }
        return .ok
    }
```

**Acceptance:** On a chlorine pool with `salt = 0`, the Salt row shows the neutral
`—` chip (not orange "LOW"). `free_chlorine = 0.2` still shows "LOW".

---

## Task 3 — Polite BLE lifecycle: auto-disconnect after a reading

**Why:** The SpinTouch allows **one** BLE connection at a time and only advertises
while a results screen is shown (see `misc/lamotte-spintouch/docs/TROUBLESHOOTING.md`).
The reference integrations deliberately disconnect shortly after reading so the
official LaMotte app (and the device) aren't blocked. The iOS app currently holds
the link open until the user taps Stop. Add a short auto-disconnect after a
successful reading + ACK, while **keeping the parsed reading on screen**.

**Files:** `ios/SpinTouch/BLEManager.swift`

**Change A** — add stored state to `BLEManager` (near the other private vars):

```swift
    private var autoDisconnectTask: Task<Void, Never>?
    private let autoDisconnectDelaySeconds: UInt64 = 8
```

**Change B** — in `didUpdateValueFor`, right after a successful parse + `sendAck()`,
schedule the disconnect. The success branch becomes:

```swift
                if let parsed = SpinTouchParser.parse(value) {
                    self.reading = parsed
                    phase = .gotReading
                    addLog("Parsed: \(parsed.summaryLine)")
                    sendAck()
                    scheduleAutoDisconnect()
                } else {
```

**Change C** — add the helper (e.g. just below `sendAck()`):

```swift
    /// Disconnect a short time after a reading so the SpinTouch is free for the
    /// LaMotte app / its own UI. The parsed reading stays on screen because the
    /// disconnect handler preserves it while phase == .gotReading.
    private func scheduleAutoDisconnect() {
        autoDisconnectTask?.cancel()
        autoDisconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: (self?.autoDisconnectDelaySeconds ?? 8) * 1_000_000_000)
            guard let self, !Task.isCancelled, let p = self.peripheral else { return }
            self.addLog("Auto-disconnecting to free the device for the LaMotte app")
            self.central.cancelPeripheralConnection(p)
        }
    }
```

**Change D** — cancel the task on manual disconnect and on a new scan so it can't
fire late. In `disconnect()` add as the first line:

```swift
        autoDisconnectTask?.cancel()
```

and in `startScan()` add as the first line:

```swift
        autoDisconnectTask?.cancel()
```

**Notes:** The existing `didDisconnectPeripheral` handler already keeps
`self.reading` and the `.gotReading` phase, so the UI stays populated after the
auto-disconnect. Status notifications during the 8s window still trigger a re-read
(handles a user running a second test immediately).

**Acceptance:** After a reading appears, the link drops ~8s later (visible in the
BLE Log as "Auto-disconnecting…"), the results remain on screen, and tapping
"Scan Again" reconnects cleanly.

---

## Task 4 — End-signature validation (informational)

**Why:** The payload ends with `[0x07, 0x0B, 0x0D, 0x11]` at offset 87. Validating
it catches truncated/garbled payloads that happen to start correctly. Match the
reference behavior: **warn but don't reject** (some payloads may legitimately
vary), and surface the result for debugging.

**Files:** `ios/SpinTouch/SpinTouchProtocol.swift`, `ios/SpinTouch/Models.swift`,
`ios/SpinTouch/ContentView.swift`

**Change A** — add a field to `SpinTouchReading` in `Models.swift`:

```swift
    let endSignatureValid: Bool
```

Place it alongside the other stored properties (e.g. right after `rawHex`). Keep
the memberwise initializer usage in the parser in sync (Change B).

**Change B** — in `SpinTouchProtocol.swift`, inside `SpinTouchParser.parse(_:)`,
compute the flag and pass it through. After the metadata block and before the
`return SpinTouchReading(...)`:

```swift
        let endSignatureValid: Bool = {
            let o = Layout.endSignatureOffset
            guard bytes.count >= o + 4 else { return false }
            return Array(bytes[o..<o + 4]) == Layout.endSignature
        }()
```

Then add `endSignatureValid: endSignatureValid,` to the `SpinTouchReading(...)`
initializer call.

**Change C** — surface it in the log sheet. In `ContentView.swift`, in `logSheet`,
inside the `if let hex = ble.reading?.rawHex { … }` block, add after the hex text:

```swift
                        if ble.reading?.endSignatureValid == false {
                            Text("⚠︎ End signature mismatch (payload may be truncated)")
                                .font(.caption2).foregroundStyle(.orange)
                        }
```

**Acceptance:** A normal 91-byte payload parses with `endSignatureValid == true`
and no warning. The parser never rejects a payload solely due to the end signature.

---

## Task 5 — Offline, deterministic recommendation engine (no API key needed)

**Why:** Today the only guidance path is `AIReader` → Anthropic, which requires an
API key and network. The reference `automations/chemistry_alerts.yaml` encodes
vetted, concrete corrective advice. Provide an instant offline "Recommendations"
layer that always works, and use it as the fallback inside the AI sheet when no
key is set.

**Files:** NEW `ios/SpinTouch/Recommendations.swift` (+ register in pbxproj),
`ios/SpinTouch/ContentView.swift`, `ios/SpinTouch/AIReadView.swift`

**Change A** — create `ios/SpinTouch/Recommendations.swift`:

```swift
import Foundation

enum AdviceSeverity {
    case warning   // out of ideal range, act soon
    case critical  // safety / strongly out of range
}

struct Advice: Identifiable {
    let id = UUID()
    let title: String       // e.g. "Low pH"
    let detail: String      // what to do
    let severity: AdviceSeverity
}

/// Deterministic, offline pool-chemistry guidance derived from the reference
/// integration's alert rules. Intentionally conservative and brand-neutral.
enum Recommendations {
    static func evaluate(_ reading: SpinTouchReading) -> [Advice] {
        var out: [Advice] = []
        func v(_ key: String) -> Double? { reading.value(key) }

        // Free chlorine (only meaningful when chlorine was measured)
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

        // Combined chlorine / chloramines
        if let cc = v("combined_chlorine"), cc > 0.2 {
            out.append(Advice(title: "Chloramines Present",
                detail: "Combined chlorine is \(fmt(cc)) ppm (ideal ≤ 0.2). Shock the pool (breakpoint chlorination).",
                severity: .warning))
        }

        // pH
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

        // Total alkalinity
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

        // Calcium hardness
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

        // Cyanuric acid (only relevant on chlorine pools)
        if let cya = v("cya"), false { _ = cya } // placeholder; key is cyanuric_acid
        if let cya = v("cyanuric_acid"), cya > 50 {
            out.append(Advice(title: "High Cyanuric Acid",
                detail: "CYA is \(fmt0(cya)) ppm (ideal 30–50). Chlorine is less effective; dilute with fresh water.",
                severity: .warning))
        }

        // FC/CYA ratio
        if let ratio = v("fc_cya_ratio"), let cya = v("cyanuric_acid"), cya > 30, ratio < 7.5 {
            out.append(Advice(title: "Low FC/CYA Ratio",
                detail: "Ratio is \(fmt(ratio))% (aim ≥ 7.5%). Raise free chlorine or dilute to lower CYA.",
                severity: .warning))
        }

        // Salt (only for salt pools)
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

        // Phosphate
        if let po4 = v("phosphate"), po4 > 500 {
            out.append(Advice(title: "High Phosphate",
                detail: "Phosphate is \(fmt0(po4)) ppb (act above 500). Use a phosphate remover to limit algae.",
                severity: .warning))
        }

        // Metals
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
```

> Implementation note: remove the dead placeholder line
> `if let cya = v("cya"), false { _ = cya }` — it's only there to highlight that
> the catalog key is `cyanuric_acid`, not `cya`. Use `cyanuric_acid`.

**Change B** — show recommendations in `ContentView.swift`. Add a card and place
it just above `aiReadPlaceholder` in `body`'s results section. Insert into the
`if let reading = ble.reading { … }` block:

```swift
                        recommendationsCard(reading)
                        aiReadPlaceholder
```

And add the card builder:

```swift
    @ViewBuilder
    private func recommendationsCard(_ reading: SpinTouchReading) -> some View {
        let advice = Recommendations.evaluate(reading)
        VStack(alignment: .leading, spacing: 10) {
            Label("Recommendations", systemImage: "checklist")
                .font(.headline)
            if advice.isEmpty {
                Label("All measured parameters look in range.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(.green)
            } else {
                ForEach(advice) { a in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: a.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            .foregroundStyle(a.severity == .critical ? .red : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.title).font(.subheadline).bold()
                            Text(a.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
```

**Change C** — use it as the AI fallback in `AIReadView.swift`. When the reader
fails specifically because there's no API key, the offline advice is still useful.
Replace the `.failed(let message)` branch body so it offers the offline list:

```swift
                case .failed(let message):
                    ScrollView {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle).foregroundStyle(.orange)
                            Text(message)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            Button("Try Again") { Task { await reader.run(reading: reading, settings: settings) } }
                                .buttonStyle(.borderedProminent)

                            let advice = Recommendations.evaluate(reading)
                            if !advice.isEmpty {
                                Divider().padding(.vertical, 4)
                                Text("Offline recommendations").font(.headline)
                                ForEach(advice) { a in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.title).font(.subheadline).bold()
                                        Text(a.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding()
                    }
```

**Acceptance:** With no API key set, the main screen still shows a populated
"Recommendations" card after a reading, and opening "Get AI Read" shows the
offline list under the error. With everything in range, the card shows the green
"all in range" line.

---

## Task 6 — One-glance "Water Quality" rollup on the status card

**Why:** The reference exposes a single summary (`SpinTouchWaterQualitySensor`),
e.g. "pH ↑, CYA ↓". The iOS app only shows per-row chips. Add a compact rollup so
users see overall status at a glance.

**Files:** `ios/SpinTouch/Models.swift`, `ios/SpinTouch/ContentView.swift`

**Change A** — add to `SpinTouchReading` in `Models.swift`:

```swift
    /// Parameters currently out of their ideal range (excludes neutral/unknown).
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
```

**Change B** — show it in `ContentView.swift`'s `statusCard`. Inside the
`VStack(alignment: .leading, spacing: 2)`, after the device-name line, add:

```swift
                if let reading = ble.reading {
                    if let summary = reading.qualitySummary {
                        Text("Out of range: \(summary)")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("All measured parameters in range")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
```

**Acceptance:** After a reading with high pH and low CYA, the status card shows
"Out of range: pH ↑, CYA ↓". A clean reading shows the green in-range line.

---

## Task 7 — "Test age" / staleness indicator

**Why:** The ESPHome config exposes a "Test Age". A reading that's days old should
be visibly flagged so users don't act on stale chemistry.

**Files:** `ios/SpinTouch/ContentView.swift`

**Change** — in `metadataCard(_:)`, replace the "Report time" row block with one
that appends a relative age and a Stale badge when older than 3 days. Use the
report time when available, else `receivedAt`:

```swift
            if let report = reading.reportTime {
                metaRow("Report time", report.formatted(date: .abbreviated, time: .shortened))
            }
            let effective = reading.reportTime ?? reading.receivedAt
            let age = Date().timeIntervalSince(effective)
            HStack {
                Text("Test age").foregroundStyle(.secondary)
                Spacer()
                Text(effective.formatted(.relative(presentation: .named)))
                    .bold()
                if age > 3 * 24 * 3600 {
                    Text("STALE")
                        .font(.caption2).bold()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
```

**Acceptance:** A reading whose report time is 5 days ago shows a relative age
("5 days ago") and an orange "STALE" badge; a fresh reading shows no badge.

---

## Task 8 — Onboarding copy: mention closing the LaMotte app

**Why:** Single-connection devices fail to connect if the official app holds the
link (`docs/TROUBLESHOOTING.md`). The empty state already tells users to keep the
device on a results screen; add the "close the LaMotte app" hint.

**Files:** `ios/SpinTouch/ContentView.swift`

**Change** — in `emptyState`, update the instructional `Text`:

```swift
            Text("Power on the SpinTouch, run a test, and keep it on the results screen. Close the LaMotte app if it's open, then tap Scan.")
```

**Acceptance:** The empty state mentions closing the LaMotte app.

---

## Out of scope (intentionally not included)

- **Deterministic dosing math (`LaMotte.TreatmentEngine.dll`)**: referenced in
  `RESEARCH.md` but the engine source is **not** present in this repo, so there's
  nothing to port. The AI read + offline rules (Task 5) cover guidance for now.
- **Localization (16 languages)**: the reference ships translated strings under
  `custom_components/spintouch/translations/`. Nice-to-have later; not required
  for these tasks. If desired, those JSON files are a ready-made source of
  translated parameter names.
- **IntelliCenter sync / Home Assistant automations**: not applicable to a
  standalone iOS app.

## Final checklist for the implementing agent

- [ ] All 8 tasks applied.
- [ ] `Recommendations.swift` created **and** registered in `project.pbxproj`.
- [ ] Project builds with no new warnings/errors.
- [ ] Phosphate 250 → OK, 600 → HIGH.
- [ ] Salt 0 on a chlorine pool → neutral chip (not LOW).
- [ ] After a reading, BLE auto-disconnects ~8s later but results stay on screen.
- [ ] Recommendations card renders with and without an API key.
