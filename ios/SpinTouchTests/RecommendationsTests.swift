import XCTest
@testable import SpinTouch

final class RecommendationsTests: XCTestCase {

    /// Build a reading whose `value(key)` returns the given numbers. The
    /// recommendation engine only reads numeric values, so the specs are dummies.
    private func makeReading(_ values: [String: Double]) -> SpinTouchReading {
        let params = values.map { key, value -> ParameterValue in
            let spec = ParamSpec(paramID: 0, key: key, name: key, unit: nil, decimals: 2,
                                 minValid: -1e9, maxValid: 1e9, idealLow: nil, idealHigh: nil, sortOrder: 0)
            return ParameterValue(spec: spec, value: value, decimals: 2)
        }
        return SpinTouchReading(parameters: params, derived: [], diskSeries: nil, sanitizer: nil,
                                numValidResults: params.count, reportTime: nil, receivedAt: Date(),
                                rawHex: "", endSignatureValid: true)
    }

    private func titles(_ advice: [Advice]) -> [String] { advice.map(\.title) }

    func testLowFreeChlorineIsCritical() {
        let advice = Recommendations.evaluate(makeReading(["free_chlorine": 0.4]), poolType: "Chlorine")
        let low = advice.first { $0.title == "Low Free Chlorine" }
        XCTAssertNotNil(low)
        XCTAssertEqual(low?.severity, .critical)
    }

    func testHighPH() {
        let advice = Recommendations.evaluate(makeReading(["ph": 8.0]), poolType: "Chlorine")
        XCTAssertTrue(titles(advice).contains("High pH"))
    }

    func testLowBromineForBrominePool() {
        let advice = Recommendations.evaluate(makeReading(["bromine": 1.0]), poolType: "Bromine")
        XCTAssertTrue(titles(advice).contains("Low Bromine"))
    }

    func testBrominePoolSuppressesChlorineAdvice() {
        // A bromine pool with low FC should not raise a chlorine warning.
        let advice = Recommendations.evaluate(makeReading(["free_chlorine": 0.2]), poolType: "Bromine")
        XCTAssertFalse(titles(advice).contains("Low Free Chlorine"))
    }

    func testBalancedWaterHasNoAdvice() {
        let advice = Recommendations.evaluate(
            makeReading(["ph": 7.4, "free_chlorine": 2.0, "alkalinity": 100, "calcium": 300]),
            poolType: "Chlorine")
        XCTAssertTrue(advice.isEmpty, "Unexpected advice: \(titles(advice))")
    }
}
