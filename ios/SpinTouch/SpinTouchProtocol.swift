import Foundation
import CoreBluetooth

// MARK: - BLE UUIDs
//
// Reverse-engineered from the LaMotte WaterLink Solutions Home app.
// Source of truth: misc/lamotte-spintouch/RESEARCH.md + the Home Assistant
// integration's const.py / coordinator.py.

enum SpinTouchUUID {
    static let service = CBUUID(string: "00000000-0000-1000-8000-BBBD00000000") // SPIN_TOUCH_SERVICE
    static let data    = CBUUID(string: "00000000-0000-1000-8000-BBBD00000010") // TTEST   (read, 91 bytes)
    static let status  = CBUUID(string: "00000000-0000-1000-8000-BBBD00000011") // TESTAVAIL (notify)
    static let sendTest = CBUUID(string: "00000000-0000-1000-8000-BBBD00000012") // SENDTEST
    static let ack     = CBUUID(string: "00000000-0000-1000-8000-BBBD00000013") // TESTACK (write 0x01)
}

// MARK: - Parameter catalog

/// One measurable water-chemistry parameter and how to present/validate it.
struct ParamSpec: Identifiable {
    let paramID: UInt8       // TestType byte in the BLE payload
    let key: String          // stable identifier
    let name: String         // display name
    let unit: String?        // e.g. "ppm", "ppb", nil for pH
    let decimals: Int        // fallback display precision
    let minValid: Double     // reject sensor noise outside [min, max]
    let maxValid: Double
    let idealLow: Double?    // "good" range for pool water (advisory)
    let idealHigh: Double?
    let sortOrder: Int

    var id: String { key }
}

enum SpinTouchCatalog {
    /// Param-ID -> spec. Mirrors PARAM_ID_TO_SENSOR in the proven Python code.
    /// Calcium has two IDs: 0x08 (high range) and 0x0F (standard) -> same key.
    static let specs: [UInt8: ParamSpec] = {
        var m: [UInt8: ParamSpec] = [:]
        func add(_ s: ParamSpec) { m[s.paramID] = s }

        add(ParamSpec(paramID: 0x01, key: "free_chlorine", name: "Free Chlorine", unit: "ppm",
                      decimals: 2, minValid: 0, maxValid: 20, idealLow: 1.0, idealHigh: 3.0, sortOrder: 0))
        add(ParamSpec(paramID: 0x02, key: "total_chlorine", name: "Total Chlorine", unit: "ppm",
                      decimals: 2, minValid: 0, maxValid: 20, idealLow: nil, idealHigh: nil, sortOrder: 1))
        add(ParamSpec(paramID: 0x03, key: "bromine", name: "Bromine", unit: "ppm",
                      decimals: 2, minValid: 0, maxValid: 20, idealLow: 2.0, idealHigh: 4.0, sortOrder: 2))
        add(ParamSpec(paramID: 0x06, key: "ph", name: "pH", unit: nil,
                      decimals: 2, minValid: 0, maxValid: 14, idealLow: 7.2, idealHigh: 7.6, sortOrder: 3))
        add(ParamSpec(paramID: 0x07, key: "alkalinity", name: "Total Alkalinity", unit: "ppm",
                      decimals: 1, minValid: 0, maxValid: 500, idealLow: 80, idealHigh: 120, sortOrder: 4))
        add(ParamSpec(paramID: 0x08, key: "calcium", name: "Calcium Hardness", unit: "ppm",
                      decimals: 1, minValid: 0, maxValid: 1200, idealLow: 200, idealHigh: 400, sortOrder: 5))
        add(ParamSpec(paramID: 0x0A, key: "cyanuric_acid", name: "Cyanuric Acid", unit: "ppm",
                      decimals: 1, minValid: 0, maxValid: 300, idealLow: 30, idealHigh: 50, sortOrder: 6))
        add(ParamSpec(paramID: 0x0B, key: "iron", name: "Iron", unit: "ppm",
                      decimals: 2, minValid: 0, maxValid: 5, idealLow: 0, idealHigh: 0.3, sortOrder: 9))
        add(ParamSpec(paramID: 0x0C, key: "copper", name: "Copper", unit: "ppm",
                      decimals: 2, minValid: 0, maxValid: 5, idealLow: 0, idealHigh: 0.3, sortOrder: 10))
        add(ParamSpec(paramID: 0x0D, key: "borate", name: "Borate", unit: "ppm",
                      decimals: 1, minValid: 0, maxValid: 100, idealLow: 30, idealHigh: 50, sortOrder: 11))
        add(ParamSpec(paramID: 0x0E, key: "phosphate", name: "Phosphate", unit: "ppb",
                      decimals: 0, minValid: 0, maxValid: 2500, idealLow: 0, idealHigh: 100, sortOrder: 12))
        add(ParamSpec(paramID: 0x0F, key: "calcium", name: "Calcium Hardness", unit: "ppm",
                      decimals: 1, minValid: 0, maxValid: 1200, idealLow: 200, idealHigh: 400, sortOrder: 5))
        add(ParamSpec(paramID: 0x10, key: "salt", name: "Salt", unit: "ppm",
                      decimals: 0, minValid: 0, maxValid: 10000, idealLow: 2700, idealHigh: 3400, sortOrder: 7))
        return m
    }()

    static let diskTypeMap: [UInt8: String] = [
        0: "101", 1: "102", 2: "201", 3: "202", 4: "301", 5: "302", 6: "401",
        7: "402", 8: "501", 9: "601", 16: "103", 17: "203", 18: "303",
        19: "503", 20: "603", 22: "104", 23: "204", 24: "304",
    ]

    static let sanitizerTypeMap: [UInt8: String] = [
        0: "Chlorine", 1: "Salt", 2: "Bromine", 3: "Biguanide",
        4: "DWTreated", 5: "AQFresh", 6: "CTCL", 7: "CTBR", 8: "Unknown",
    ]
}

// MARK: - Parsing

private enum Layout {
    static let startSignature: [UInt8] = [0x01, 0x02, 0x03, 0x05]
    static let endSignature: [UInt8] = [0x07, 0x0B, 0x0D, 0x11]
    static let headerSize = 4
    static let entrySize = 6
    static let maxEntries = 12
    static let timestampOffset = 76
    static let metadataOffset = 84
    static let endSignatureOffset = 87
    static let minDataSize = 91
}

enum SpinTouchParser {
    /// Parse a 91-byte SpinTouch TTEST payload. Returns nil if the payload is
    /// malformed (bad length or start signature).
    static func parse(_ data: Data) -> SpinTouchReading? {
        guard data.count >= Layout.minDataSize else { return nil }
        let bytes = [UInt8](data)

        guard Array(bytes[0..<Layout.headerSize]) == Layout.startSignature else { return nil }

        var readings: [ParameterValue] = []
        var detectedParamIDs: Set<UInt8> = []

        var offset = Layout.headerSize
        var parsed = 0
        while offset + Layout.entrySize <= bytes.count && parsed < Layout.maxEntries {
            let testType = bytes[offset]
            let decimals = bytes[offset + 1]
            if testType == 0 && decimals == 0 { break }
            detectedParamIDs.insert(testType)

            if let spec = SpinTouchCatalog.specs[testType] {
                let value = Double(readFloatLE(bytes, at: offset + 2))
                if value.isFinite && value >= spec.minValid && value <= spec.maxValid {
                    let displayDecimals = decimals < 10 ? Int(decimals) : spec.decimals
                    readings.append(ParameterValue(spec: spec, value: value, decimals: displayDecimals))
                }
            }
            offset += Layout.entrySize
            parsed += 1
        }

        // Metadata (bytes 84-86)
        var diskSeries: String? = nil
        var sanitizer: String? = nil
        var numValid = 0
        if bytes.count >= Layout.metadataOffset + 3 {
            numValid = Int(bytes[Layout.metadataOffset])
            diskSeries = SpinTouchCatalog.diskTypeMap[bytes[Layout.metadataOffset + 1]]
            sanitizer = SpinTouchCatalog.sanitizerTypeMap[bytes[Layout.metadataOffset + 2]]
        }

        let reportTime = parseTimestamp(bytes)

        // Collapse duplicate keys (calcium 0x08/0x0F) keeping first occurrence,
        // then sort by display order.
        var seen = Set<String>()
        let deduped = readings.filter { seen.insert($0.spec.key).inserted }
            .sorted { $0.spec.sortOrder < $1.spec.sortOrder }

        let derived = deriveValues(from: deduped)

        return SpinTouchReading(
            parameters: deduped,
            derived: derived,
            diskSeries: diskSeries ?? autoDetectSeries(detectedParamIDs),
            sanitizer: sanitizer,
            numValidResults: numValid,
            reportTime: reportTime,
            receivedAt: Date(),
            rawHex: data.map { String(format: "%02X", $0) }.joined()
        )
    }

    private static func readFloatLE(_ bytes: [UInt8], at i: Int) -> Float {
        let bits = UInt32(bytes[i]) | (UInt32(bytes[i+1]) << 8) |
                   (UInt32(bytes[i+2]) << 16) | (UInt32(bytes[i+3]) << 24)
        return Float(bitPattern: bits)
    }

    private static func parseTimestamp(_ bytes: [UInt8]) -> Date? {
        let o = Layout.timestampOffset
        guard bytes.count >= o + 8 else { return nil }
        let year = 2000 + Int(bytes[o])
        let month = Int(bytes[o + 1])
        let day = Int(bytes[o + 2])
        var hour = Int(bytes[o + 3])
        let minute = Int(bytes[o + 4])
        let second = Int(bytes[o + 5])
        let ampm = Int(bytes[o + 6])
        let military = Int(bytes[o + 7])

        if military == 0 {
            if ampm == 1 && hour < 12 { hour += 12 }
            else if ampm == 0 && hour == 12 { hour = 0 }
        }

        guard (2020...2099).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second)
        else { return nil }

        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return Calendar.current.date(from: comps)
    }

    private static func deriveValues(from params: [ParameterValue]) -> [ParameterValue] {
        func value(_ key: String) -> Double? { params.first { $0.spec.key == key }?.value }
        var out: [ParameterValue] = []

        if let fc = value("free_chlorine"), let tc = value("total_chlorine") {
            let cc = max(0, tc - fc)
            let spec = ParamSpec(paramID: 0xF1, key: "combined_chlorine", name: "Combined Chlorine",
                                 unit: "ppm", decimals: 2, minValid: 0, maxValid: 20,
                                 idealLow: 0, idealHigh: 0.2, sortOrder: 100)
            out.append(ParameterValue(spec: spec, value: cc, decimals: 2))
        }
        if let fc = value("free_chlorine"), let cya = value("cyanuric_acid"), cya > 0 {
            let ratio = fc / cya * 100
            let spec = ParamSpec(paramID: 0xF2, key: "fc_cya_ratio", name: "FC / CYA Ratio",
                                 unit: "%", decimals: 1, minValid: 0, maxValid: 1000,
                                 idealLow: 7.5, idealHigh: nil, sortOrder: 101)
            out.append(ParameterValue(spec: spec, value: ratio, decimals: 1))
        }
        return out
    }

    private static func autoDetectSeries(_ ids: Set<UInt8>) -> String? {
        let hasChlorine = ids.contains(0x01) || ids.contains(0x02)
        let hasBromine = ids.contains(0x03)
        let hasBorate0E = ids.contains(0x0E)
        if hasBromine { return "203" }
        if hasChlorine && !hasBorate0E { return "303" }
        if hasBorate0E && !hasChlorine && !hasBromine { return "204" }
        if hasChlorine { return "303" }
        return nil
    }
}
