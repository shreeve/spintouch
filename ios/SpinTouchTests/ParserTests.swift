import XCTest
@testable import SpinTouch

final class ParserTests: XCTestCase {

    /// Build a minimal, valid 91-byte TTEST frame with pH and free chlorine.
    private func makeFrame(ph: Float = 7.4, fc: Float = 1.5) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 91)
        b[0] = 0x01; b[1] = 0x02; b[2] = 0x03; b[3] = 0x05      // start signature

        // Entry 0: pH (0x06), Entry 1: free chlorine (0x01).
        b[4] = 0x06; b[5] = 2; writeFloat(&b, 6, ph)
        b[10] = 0x01; b[11] = 2; writeFloat(&b, 12, fc)
        // bytes 16.. stay zero → parser stops at the 0/0 terminator entry.

        // Timestamp at 76: 2025-06-24 21:30:00, 24h clock.
        b[76] = 25; b[77] = 6; b[78] = 24; b[79] = 21; b[80] = 30; b[81] = 0; b[82] = 0; b[83] = 1
        // Metadata at 84: numValid, disk index (2 → "201"), sanitizer index (0 → Chlorine).
        b[84] = 2; b[85] = 2; b[86] = 0
        // End signature at 87.
        b[87] = 0x07; b[88] = 0x0B; b[89] = 0x0D; b[90] = 0x11
        return b
    }

    private func writeFloat(_ bytes: inout [UInt8], _ offset: Int, _ value: Float) {
        let bits = value.bitPattern
        bytes[offset] = UInt8(bits & 0xFF)
        bytes[offset + 1] = UInt8((bits >> 8) & 0xFF)
        bytes[offset + 2] = UInt8((bits >> 16) & 0xFF)
        bytes[offset + 3] = UInt8((bits >> 24) & 0xFF)
    }

    func testParsesValidFrame() throws {
        let reading = try XCTUnwrap(SpinTouchParser.parse(Data(makeFrame())))
        XCTAssertEqual(try XCTUnwrap(reading.value("ph")), 7.4, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(reading.value("free_chlorine")), 1.5, accuracy: 0.01)
        XCTAssertTrue(reading.endSignatureValid)
        XCTAssertEqual(reading.sanitizer, "Chlorine")
        XCTAssertEqual(reading.diskSeries, "201")
        XCTAssertNotNil(reading.reportTime)
        XCTAssertEqual(reading.rawHex.count, 182)   // 91 bytes * 2 hex chars
    }

    func testRejectsShortPayload() {
        let short = Data([UInt8](repeating: 0, count: 90))
        XCTAssertNil(SpinTouchParser.parse(short))
    }

    func testRejectsBadStartSignature() {
        var frame = makeFrame()
        frame[0] = 0xFF
        XCTAssertNil(SpinTouchParser.parse(Data(frame)))
    }

    func testTrailingBytesDoNotChangeParseOrIdentity() throws {
        let base = try XCTUnwrap(SpinTouchParser.parse(Data(makeFrame())))
        let padded = try XCTUnwrap(SpinTouchParser.parse(Data(makeFrame() + [0xAA, 0xBB, 0xCC])))
        // Extra transport bytes must not alter values or the identity hash.
        XCTAssertEqual(padded.rawHex, base.rawHex)
        XCTAssertEqual(padded.rawHex.count, 182)
        XCTAssertEqual(try XCTUnwrap(padded.value("ph")), 7.4, accuracy: 0.01)
    }

    func testRejectsImpossibleTimestamp() throws {
        var frame = makeFrame()
        frame[77] = 13   // month 13 is invalid
        let reading = try XCTUnwrap(SpinTouchParser.parse(Data(frame)))
        XCTAssertNil(reading.reportTime)   // values still parse; bad time is dropped
    }
}
