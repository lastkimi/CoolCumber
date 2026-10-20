import Foundation
import XCTest
@testable import ThermFlowCore

final class TrustedThermalPressurePolicyTests: XCTestCase {
    private let now = TestFixtures.date
    private let policy = TrustedThermalPressurePolicy()

    func testAppStoreSeriousAndCriticalSystemReportsProduceDistinctAlerts() throws {
        let serious = try XCTUnwrap(alertEvent(for: .serious))
        XCTAssertEqual(serious.trigger, .serious)
        XCTAssertEqual(serious.value, .serious)

        let critical = try XCTUnwrap(alertEvent(for: .critical))
        XCTAssertEqual(critical.trigger, .critical)
        XCTAssertEqual(critical.value, .critical)
        XCTAssertNotEqual(serious.sampleIdentity, critical.sampleIdentity)
    }

    func testNominalAndFairSystemReportsDoNotAlert() {
        XCTAssertEqual(
            policy.assess(makeSnapshot(pressure: .nominal), at: now),
            .noAlert(value: .nominal)
        )
        XCTAssertEqual(
            policy.assess(makeSnapshot(pressure: .fair), at: now),
            .noAlert(value: .fair)
        )
    }

    func testStaleFutureAndUntrustedReportsFailClosed() {
        XCTAssertEqual(
            policy.assess(
                makeSnapshot(
                    pressure: .critical,
                    sampleDate: now.addingTimeInterval(-15.001),
                    capabilityDate: now
                ),
                at: now
            ),
            .rejected(.stale)
        )
        XCTAssertEqual(
            policy.assess(
                makeSnapshot(
                    pressure: .critical,
                    sampleDate: now.addingTimeInterval(0.001),
                    capabilityDate: now
                ),
                at: now
            ),
            .rejected(.futureDated)
        )
        XCTAssertEqual(
            policy.assess(
                makeSnapshot(
                    pressure: .critical,
                    provenance: .measured(by: .smc, collectorID: "test")
                ),
                at: now
            ),
            .rejected(.untrustedProvenance)
        )
    }

    func testStaleCapabilityIsRejectedBeforeFreshSample() {
        XCTAssertEqual(
            policy.assess(
                makeSnapshot(
                    pressure: .critical,
                    sampleDate: now,
                    capabilityDate: now.addingTimeInterval(-15.001)
                ),
                at: now
            ),
            .rejected(.capabilityUnavailable)
        )
    }

    private func alertEvent(
        for pressure: ThermalPressure
    ) -> TrustedThermalPressureAlertEvent? {
        guard case .alert(let event) = policy.assess(
            makeSnapshot(pressure: pressure),
            at: now
        ) else {
            return nil
        }
        return event
    }

    private func makeSnapshot(
        pressure: ThermalPressure,
        sampleDate: Date? = nil,
        capabilityDate: Date? = nil,
        provenance: MetricProvenance = .reported(
            by: .processInfo,
            collectorID: "ProcessInfo.thermalState"
        )
    ) -> SystemSnapshot {
        let sampleDate = sampleDate ?? now
        let capabilityDate = capabilityDate ?? now
        var capabilities = CapabilitySet.baseline(
            for: .appStore,
            evaluatedAt: capabilityDate
        )
        capabilities.set(.available(at: capabilityDate), for: .thermalPressure)
        return TestFixtures.snapshot(
            channel: .appStore,
            capabilities: capabilities,
            pressure: .available(
                pressure,
                provenance: provenance,
                observedAt: sampleDate
            ),
            at: sampleDate
        )
    }
}
