import Foundation
import XCTest
@testable import ThermFlowCore

final class CPULoadCalculatorTests: XCTestCase {
    func testFirstSampleIsUnavailableInsteadOfZeroPercent() {
        var calculator = CPULoadCalculator()
        let sample = calculator.sample(
            ticks: CPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            capturedAt: TestFixtures.date
        )

        XCTAssertEqual(sample.availability, .temporarilyUnavailable)
        XCTAssertNil(sample.value)
        XCTAssertEqual(sample.failure?.code, "needsPreviousSample")
        XCTAssertEqual(sample.provenance.derivedFrom, [.machKernel])
    }

    func testUsageIsCalculatedFromBusyAndTotalTickDeltas() {
        var calculator = CPULoadCalculator()
        _ = calculator.sample(
            ticks: CPUTicks(user: 100, system: 50, idle: 850, nice: 0),
            capturedAt: TestFixtures.date
        )
        let sample = calculator.sample(
            ticks: CPUTicks(user: 200, system: 100, idle: 900, nice: 0),
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )

        XCTAssertEqual(sample.availability, .available)
        XCTAssertEqual(sample.value?.value, 75)
    }

    func testNiceTicksCountAsBusy() {
        var calculator = CPULoadCalculator()
        _ = calculator.sample(
            ticks: CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
            capturedAt: TestFixtures.date
        )
        let sample = calculator.sample(
            ticks: CPUTicks(user: 20, system: 10, idle: 60, nice: 10),
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )
        XCTAssertEqual(sample.value?.value, 40)
    }

    func testCounterResetDoesNotCreateFalseHighUsage() {
        var calculator = CPULoadCalculator()
        _ = calculator.sample(
            ticks: CPUTicks(user: 100, system: 100, idle: 800, nice: 0),
            capturedAt: TestFixtures.date
        )
        let reset = calculator.sample(
            ticks: CPUTicks(user: 5, system: 5, idle: 40, nice: 0),
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )
        let recovered = calculator.sample(
            ticks: CPUTicks(user: 15, system: 10, idle: 75, nice: 0),
            capturedAt: TestFixtures.date.addingTimeInterval(2)
        )

        XCTAssertEqual(reset.availability, .temporarilyUnavailable)
        XCTAssertEqual(reset.failure?.code, "counterReset")
        XCTAssertNil(reset.value)
        XCTAssertEqual(recovered.value?.value, 30)
    }

    func testNoTickProgressIsUnavailable() {
        let ticks = CPUTicks(user: 10, system: 10, idle: 80, nice: 0)
        var calculator = CPULoadCalculator()
        _ = calculator.sample(ticks: ticks, capturedAt: TestFixtures.date)
        let sample = calculator.sample(
            ticks: ticks,
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )

        XCTAssertEqual(sample.availability, .temporarilyUnavailable)
        XCTAssertEqual(sample.failure?.code, "noTickProgress")
        XCTAssertNil(sample.value)
    }

    func testNonMonotonicTimestampFailsWithoutReplacingBaseline() {
        var calculator = CPULoadCalculator()
        _ = calculator.sample(
            ticks: CPUTicks(user: 0, system: 0, idle: 100, nice: 0),
            capturedAt: TestFixtures.date
        )
        let failed = calculator.sample(
            ticks: CPUTicks(user: 10, system: 0, idle: 110, nice: 0),
            capturedAt: TestFixtures.date
        )
        let recovered = calculator.sample(
            ticks: CPUTicks(user: 20, system: 0, idle: 180, nice: 0),
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )

        XCTAssertEqual(failed.failure?.code, "nonMonotonicTimestamp")
        XCTAssertEqual(recovered.value?.value, 20)
    }

    func testExplicitResetRequiresAnotherBaselineSample() {
        var calculator = CPULoadCalculator()
        _ = calculator.sample(
            ticks: CPUTicks(user: 0, system: 0, idle: 100, nice: 0),
            capturedAt: TestFixtures.date
        )
        calculator.reset()
        let sample = calculator.sample(
            ticks: CPUTicks(user: 10, system: 0, idle: 110, nice: 0),
            capturedAt: TestFixtures.date.addingTimeInterval(1)
        )
        XCTAssertEqual(sample.failure?.code, "needsPreviousSample")
    }
}
