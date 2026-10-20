import Foundation
import XCTest
@testable import ThermFlowCore

final class WidgetSnapshotPolicyTests: XCTestCase {
    private let policy = WidgetSnapshotPolicy()

    func testFreshSnapshotWithUsableDisplayedMetricIsCurrent() {
        let now = TestFixtures.date
        let pressure = MetricSample<ThermalPressure>.available(
            .fair,
            provenance: TestFixtures.reportedProcessInfo,
            observedAt: now
        )

        XCTAssertEqual(
            policy.state(
                for: TestFixtures.snapshot(pressure: pressure, at: now),
                at: now
            ),
            .current
        )
    }

    func testSnapshotFreshnessBoundaryAndFutureTimestampAreDistinguished() {
        let now = TestFixtures.date
        let exactBoundary = now.addingTimeInterval(
            -WidgetSnapshotPolicy.defaultMaximumSnapshotAge
        )
        let pressure = MetricSample<ThermalPressure>.available(
            .nominal,
            provenance: TestFixtures.reportedProcessInfo,
            observedAt: exactBoundary
        )

        XCTAssertEqual(
            policy.state(
                for: TestFixtures.snapshot(pressure: pressure, at: exactBoundary),
                at: now
            ),
            .current
        )
        XCTAssertEqual(
            policy.state(
                for: TestFixtures.snapshot(
                    pressure: pressure,
                    at: exactBoundary.addingTimeInterval(-0.001)
                ),
                at: now
            ),
            .stale
        )
        XCTAssertEqual(
            policy.state(
                for: TestFixtures.snapshot(at: now.addingTimeInterval(0.001)),
                at: now
            ),
            .unavailable
        )
    }

    func testFreshSnapshotWithoutUsableDisplayedMetricIsUnavailable() {
        let now = TestFixtures.date

        XCTAssertEqual(
            policy.state(for: TestFixtures.snapshot(at: now), at: now),
            .unavailable
        )
        XCTAssertEqual(policy.state(for: nil, at: now), .unavailable)
    }

    func testUnsupportedSchemaAndExcessFanPayloadAreUnavailable() throws {
        let now = TestFixtures.date
        let speed = MetricSample<FanRPM>.available(
            try XCTUnwrap(FanRPM(2_000)),
            provenance: TestFixtures.measuredSMC,
            observedAt: now
        )
        let fan = FanSnapshot(
            id: 0,
            currentSpeed: speed,
            mode: .unknown(observedAt: now)
        )

        XCTAssertEqual(
            policy.state(
                for: TestFixtures.snapshot(
                    schemaVersion: SystemSnapshot.currentSchemaVersion + 1,
                    at: now
                ),
                at: now
            ),
            .unavailable
        )
        XCTAssertEqual(
            policy.state(
                for: TestFixtures.snapshot(
                    fans: Array(repeating: fan, count: 9),
                    at: now
                ),
                at: now
            ),
            .unavailable
        )
    }

    func testLaterUsableFanDoesNotClaimCurrentWhenWidgetDisplaysOnlyFirstFan() throws {
        let now = TestFixtures.date
        let unavailableFan = FanSnapshot(
            id: 0,
            currentSpeed: .unknown(observedAt: now),
            mode: .unknown(observedAt: now)
        )
        let availableFan = FanSnapshot(
            id: 1,
            currentSpeed: .available(
                try XCTUnwrap(FanRPM(2_000)),
                provenance: TestFixtures.measuredSMC,
                observedAt: now
            ),
            mode: .unknown(observedAt: now)
        )

        XCTAssertEqual(
            policy.state(
                for: TestFixtures.snapshot(
                    fans: [unavailableFan, availableFan],
                    at: now
                ),
                at: now
            ),
            .unavailable
        )
    }
}
