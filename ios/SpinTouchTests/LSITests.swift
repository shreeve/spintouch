import XCTest
@testable import SpinTouch

final class LSITests: XCTestCase {

    func testBalancedWater() throws {
        let lsi = try XCTUnwrap(LSI.compute(
            ph: 7.4, calcium: 300, alkalinity: 100, cya: 30, tempF: 80, salt: 0))
        XCTAssertEqual(lsi.value, 0.04, accuracy: 0.05)
        XCTAssertEqual(lsi.status, .balanced)
    }

    func testCorrosiveWater() throws {
        // Low pH + low calcium + low alkalinity → strongly negative LSI.
        let lsi = try XCTUnwrap(LSI.compute(
            ph: 6.8, calcium: 120, alkalinity: 40, cya: 0, tempF: 60, salt: 0))
        XCTAssertLessThan(lsi.value, -0.3)
        XCTAssertEqual(lsi.status, .corrosive)
    }

    func testScaleFormingWater() throws {
        // High pH + high calcium + high alkalinity → strongly positive LSI.
        let lsi = try XCTUnwrap(LSI.compute(
            ph: 8.2, calcium: 600, alkalinity: 220, cya: 0, tempF: 90, salt: 0))
        XCTAssertGreaterThan(lsi.value, 0.3)
        XCTAssertEqual(lsi.status, .scaleForming)
    }

    func testReturnsNilWhenInputsMissing() {
        XCTAssertNil(LSI.compute(ph: 7.4, calcium: nil, alkalinity: 100, cya: 30, tempF: 80, salt: 0))
        XCTAssertNil(LSI.compute(ph: 7.4, calcium: 300, alkalinity: 100, cya: 30, tempF: nil, salt: 0))
        XCTAssertNil(LSI.compute(ph: 7.4, calcium: 0, alkalinity: 100, cya: 30, tempF: 80, salt: 0))
    }

    func testSaltRaisesTDSFactor() throws {
        let fresh = try XCTUnwrap(LSI.compute(
            ph: 7.5, calcium: 300, alkalinity: 100, cya: 0, tempF: 80, salt: 0))
        let salty = try XCTUnwrap(LSI.compute(
            ph: 7.5, calcium: 300, alkalinity: 100, cya: 0, tempF: 80, salt: 3200))
        // A higher TDS factor (12.2 vs 12.1) lowers LSI by ~0.1.
        XCTAssertEqual(fresh.value - salty.value, 0.1, accuracy: 0.001)
    }
}
