import Foundation
import XCTest
@testable import ThermFlowCore

final class DiagnosisEvaluatorTests: XCTestCase {
    private let evaluator = DiagnosisEvaluator()

    func testAllUnknownMetricsProduceInsufficientDataNotHealthy() {
        let snapshot = TestFixtures.snapshot()
        let diagnosis = evaluator.evaluate(snapshot, at: TestFixtures.date)

        XCTAssertEqual(diagnosis.status, .insufficientData)
        XCTAssertEqual(diagnosis.code, .insufficientData)
        XCTAssertEqual(diagnosis.evaluatedMetricCount, 0)
        XCTAssertNil(diagnosis.recommendation)
    }

    func testStaleAvailableMetricIsExcludedAndCannotProduceHealthy() {
        let staleDate = TestFixtures.date.addingTimeInterval(-16)
        let snapshot = TestFixtures.snapshot(
            pressure: .available(
                .nominal,
                provenance: TestFixtures.reportedProcessInfo,
                observedAt: staleDate
            )
        )
        let diagnosis = evaluator.evaluate(snapshot, at: TestFixtures.date)

        XCTAssertEqual(diagnosis.status, .insufficientData)
        XCTAssertEqual(diagnosis.evaluatedMetricCount, 0)
    }

    func testFreshNominalPressureProducesCautiousHealthyResult() {
        let snapshot = TestFixtures.snapshot(
            pressure: .available(
                .nominal,
                provenance: TestFixtures.reportedProcessInfo,
                observedAt: TestFixtures.date
            )
        )
        let diagnosis = evaluator.evaluate(snapshot, at: TestFixtures.date)

        XCTAssertEqual(diagnosis.status, .healthy)
        XCTAssertEqual(diagnosis.code, .noAlertsInAvailableMetrics)
        XCTAssertEqual(diagnosis.evaluatedMetricCount, 1)
    }

    func testCriticalTemperatureRecommendsFanOnlyWhenCapabilityIsAvailable() {
        var capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        )
        capabilities.set(.available(at: TestFixtures.date), for: .fanControl)
        let snapshot = TestFixtures.snapshot(
            capabilities: capabilities,
            cpuTemperature: .available(
                TemperatureCelsius(98)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: TestFixtures.date
            )
        )

        let diagnosis = evaluator.evaluate(snapshot, at: TestFixtures.date)
        XCTAssertEqual(diagnosis.status, .critical)
        XCTAssertEqual(diagnosis.code, .criticalCPUTemperature)
        XCTAssertEqual(diagnosis.recommendation?.kind, .increaseFan)
        XCTAssertEqual(diagnosis.recommendation?.targetFanSpeed, FanRPM(4_500))
        XCTAssertNil(diagnosis.blockedCapability)
    }

    func testFreshMetricCannotUseStaleActionCapability() {
        let evaluationDate = TestFixtures.date.addingTimeInterval(16)
        var capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        )
        capabilities.set(.available(at: TestFixtures.date), for: .fanControl)
        let snapshot = TestFixtures.snapshot(
            capabilities: capabilities,
            cpuTemperature: .available(
                TemperatureCelsius(98)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: evaluationDate
            ),
            at: evaluationDate
        )

        let diagnosis = evaluator.evaluate(snapshot, at: evaluationDate)

        XCTAssertEqual(diagnosis.code, .criticalCPUTemperature)
        XCTAssertNil(diagnosis.recommendation)
        XCTAssertEqual(diagnosis.blockedCapability, .fanControl)
    }

    func testCriticalTemperatureNeverSuggestsUnsupportedAppStoreFanAction() {
        let capabilities = CapabilitySet.baseline(
            for: .appStore,
            evaluatedAt: TestFixtures.date
        )
        let snapshot = TestFixtures.snapshot(
            channel: .appStore,
            capabilities: capabilities,
            cpuTemperature: .available(
                TemperatureCelsius(98)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: TestFixtures.date
            )
        )

        let diagnosis = evaluator.evaluate(snapshot, at: TestFixtures.date)
        XCTAssertEqual(diagnosis.status, .critical)
        XCTAssertNil(diagnosis.recommendation)
        XCTAssertEqual(diagnosis.blockedCapability, .fanControl)
    }

    func testUnknownDirectCapabilityAlsoBlocksAutomaticAction() {
        let snapshot = TestFixtures.snapshot(
            cpuTemperature: .available(
                TemperatureCelsius(88)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: TestFixtures.date
            )
        )

        let diagnosis = evaluator.evaluate(snapshot, at: TestFixtures.date)
        XCTAssertEqual(diagnosis.status, .warning)
        XCTAssertEqual(diagnosis.code, .highCPUTemperature)
        XCTAssertNil(diagnosis.recommendation)
        XCTAssertEqual(diagnosis.blockedCapability, .fanControl)
    }

    func testHighMemoryInspectionIsCapabilityGated() {
        let highMemory = MetricSample<Percent>.available(
            Percent(96)!,
            provenance: TestFixtures.measuredMach,
            observedAt: TestFixtures.date
        )
        let blockedSnapshot = TestFixtures.snapshot(memoryUsage: highMemory)
        let blocked = evaluator.evaluate(blockedSnapshot, at: TestFixtures.date)
        XCTAssertEqual(blocked.code, .highMemoryUsage)
        XCTAssertNil(blocked.recommendation)
        XCTAssertEqual(blocked.blockedCapability, .processRead)

        var capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        )
        capabilities.set(.available(at: TestFixtures.date), for: .processRead)
        let allowedSnapshot = TestFixtures.snapshot(
            capabilities: capabilities,
            memoryUsage: highMemory
        )
        let allowed = evaluator.evaluate(allowedSnapshot, at: TestFixtures.date)
        XCTAssertEqual(allowed.recommendation?.kind, .inspectProcesses)
        XCTAssertNil(allowed.blockedCapability)
    }

    func testThermalCriticalTakesPrecedenceOverOtherWarnings() {
        var capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        )
        capabilities.set(.available(at: TestFixtures.date), for: .fanControl)
        let snapshot = TestFixtures.snapshot(
            capabilities: capabilities,
            pressure: .available(
                .critical,
                provenance: TestFixtures.reportedProcessInfo,
                observedAt: TestFixtures.date
            ),
            memoryUsage: .available(
                Percent(99)!,
                provenance: TestFixtures.measuredMach,
                observedAt: TestFixtures.date
            )
        )

        let diagnosis = evaluator.evaluate(snapshot, at: TestFixtures.date)
        XCTAssertEqual(diagnosis.status, .critical)
        XCTAssertEqual(diagnosis.code, .thermalPressureCritical)
        XCTAssertEqual(diagnosis.recommendation?.kind, .increaseFan)
    }

    func testFairThermalPressureProducesWarningWithoutDangerousAction() {
        let snapshot = TestFixtures.snapshot(
            pressure: .available(
                .fair,
                provenance: TestFixtures.reportedProcessInfo,
                observedAt: TestFixtures.date
            )
        )
        let diagnosis = evaluator.evaluate(snapshot, at: TestFixtures.date)
        XCTAssertEqual(diagnosis.status, .warning)
        XCTAssertEqual(diagnosis.code, .thermalPressureFair)
        XCTAssertNil(diagnosis.recommendation)
        XCTAssertNil(diagnosis.blockedCapability)
    }

    func testLowDiskRecommendationRequiresObservedDiskCapability() {
        let lowDisk = MetricSample<ByteCount>.available(
            ByteCount(5 * 1_073_741_824),
            provenance: TestFixtures.measuredFileSystem,
            observedAt: TestFixtures.date
        )
        let blocked = evaluator.evaluate(
            TestFixtures.snapshot(diskAvailable: lowDisk),
            at: TestFixtures.date
        )
        XCTAssertEqual(blocked.code, .lowDiskSpace)
        XCTAssertNil(blocked.recommendation)
        XCTAssertEqual(blocked.blockedCapability, .diskSpace)

        var capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        )
        capabilities.set(.available(at: TestFixtures.date), for: .diskSpace)
        let allowed = evaluator.evaluate(
            TestFixtures.snapshot(capabilities: capabilities, diskAvailable: lowDisk),
            at: TestFixtures.date
        )
        XCTAssertEqual(allowed.recommendation?.kind, .reviewStorage)
    }
}
