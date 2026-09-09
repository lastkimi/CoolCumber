import Foundation
import XCTest
@testable import ThermFlowCore

final class CounterRateCalculatorTests: XCTestCase {
    func testFirstSampleIsUnavailableInsteadOfZero() {
        var calculator = CounterRateCalculator()
        let sample = calculator.sample(counter: 1_000, capturedAt: TestFixtures.date)

        XCTAssertEqual(sample.availability, .temporarilyUnavailable)
        XCTAssertNil(sample.value)
        XCTAssertEqual(sample.failure?.code, "needsPreviousSample")
        XCTAssertEqual(sample.provenance.source, .derived)
        XCTAssertEqual(sample.provenance.derivedFrom, [.networkInterface])
    }

    func testDeltaIsDividedByElapsedSeconds() {
        var calculator = CounterRateCalculator()
        _ = calculator.sample(counter: 1_000, capturedAt: TestFixtures.date)
        let sample = calculator.sample(
            counter: 1_600,
            capturedAt: TestFixtures.date.addingTimeInterval(2)
        )

        XCTAssertEqual(sample.availability, .available)
        XCTAssertEqual(sample.value?.bytesPerSecond, 300)
    }

    func testNoCounterChangeProducesRealZeroRate() {
        var calculator = CounterRateCalculator()
        _ = calculator.sample(counter: 1_000, capturedAt: TestFixtures.date)
        let sample = calculator.sample(
            counter: 1_000,
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )

        XCTAssertEqual(sample.availability, .available)
        XCTAssertEqual(sample.value, ByteRate(0))
    }

    func testCounterResetIsUnavailableAndBecomesNewBaseline() {
        var calculator = CounterRateCalculator()
        _ = calculator.sample(counter: 1_000, capturedAt: TestFixtures.date)
        _ = calculator.sample(
            counter: 1_500,
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )
        let reset = calculator.sample(
            counter: 100,
            capturedAt: TestFixtures.date.addingTimeInterval(2)
        )
        let recovered = calculator.sample(
            counter: 300,
            capturedAt: TestFixtures.date.addingTimeInterval(3)
        )

        XCTAssertEqual(reset.availability, .temporarilyUnavailable)
        XCTAssertEqual(reset.failure?.code, "counterReset")
        XCTAssertNil(reset.value)
        XCTAssertEqual(recovered.value?.bytesPerSecond, 200)
    }

    func testNonMonotonicTimestampFailsWithoutReplacingBaseline() {
        var calculator = CounterRateCalculator()
        _ = calculator.sample(counter: 100, capturedAt: TestFixtures.date)
        let failed = calculator.sample(counter: 200, capturedAt: TestFixtures.date)
        let recovered = calculator.sample(
            counter: 300,
            capturedAt: TestFixtures.date.addingTimeInterval(2)
        )

        XCTAssertEqual(failed.availability, .failed)
        XCTAssertEqual(failed.failure?.code, "nonMonotonicTimestamp")
        XCTAssertEqual(recovered.value?.bytesPerSecond, 100)
    }

    func testExplicitResetRequiresAnotherBaselineSample() {
        var calculator = CounterRateCalculator()
        _ = calculator.sample(counter: 100, capturedAt: TestFixtures.date)
        calculator.reset()
        let sample = calculator.sample(
            counter: 500,
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )
        XCTAssertEqual(sample.failure?.code, "needsPreviousSample")
    }
}
