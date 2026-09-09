import Foundation
import XCTest
@testable import ThermFlowCore

final class CapabilityTests: XCTestCase {
    func testAppStoreBaselinePermanentlyBlocksPrivilegedFeatures() {
        let capabilities = CapabilitySet.baseline(
            for: .appStore,
            evaluatedAt: TestFixtures.date
        )

        let privileged: [CapabilityID] = [
            .cpuTemperature,
            .gpuTemperature,
            .fanRead,
            .fanControl,
            .batteryChargeLimit,
            .processRead,
            .processControl,
            .launchServiceManagement,
            .systemMaintenance
        ]
        for capability in privileged {
            XCTAssertEqual(capabilities.state(for: capability).availability, .unsupported)
            XCTAssertEqual(capabilities.state(for: capability).reasonCode, "appSandbox")
            XCTAssertFalse(capabilities.allows(capability, at: TestFixtures.date))
        }
    }

    func testDirectBaselineRequiresRuntimeProbeInsteadOfAssumingSupport() {
        let capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        )

        XCTAssertEqual(capabilities.state(for: .fanControl).availability, .unknown)
        XCTAssertFalse(capabilities.allows(.fanControl, at: TestFixtures.date))
    }

    func testOnlyAvailableCapabilityAllowsAction() {
        var capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        )
        capabilities.set(.available(at: TestFixtures.date), for: .fanControl)
        XCTAssertTrue(capabilities.allows(.fanControl, at: TestFixtures.date))

        capabilities.set(
            CapabilityState(
                availability: .authorizationRequired,
                reasonCode: "helperNotAuthorized",
                evaluatedAt: TestFixtures.date
            ),
            for: .fanControl
        )
        XCTAssertFalse(capabilities.allows(.fanControl, at: TestFixtures.date))
    }

    func testAvailableCapabilityExpiresAndRejectsFutureEvaluationTimestamp() {
        let capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        ).setting(.available(at: TestFixtures.date), for: .fanControl)

        XCTAssertTrue(
            capabilities.allows(
                .fanControl,
                at: TestFixtures.date.addingTimeInterval(30),
                maximumAge: 30
            )
        )
        XCTAssertFalse(
            capabilities.allows(
                .fanControl,
                at: TestFixtures.date.addingTimeInterval(30.001),
                maximumAge: 30
            )
        )
        XCTAssertFalse(
            capabilities.allows(
                .fanControl,
                at: TestFixtures.date.addingTimeInterval(-1),
                maximumAge: 30
            )
        )
    }

    func testCapabilityRejectsInvalidMaximumAge() {
        let capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        ).setting(.available(at: TestFixtures.date), for: .fanControl)

        XCTAssertFalse(
            capabilities.allows(.fanControl, at: TestFixtures.date, maximumAge: -.infinity)
        )
        XCTAssertFalse(
            capabilities.allows(.fanControl, at: TestFixtures.date, maximumAge: .infinity)
        )
    }

    func testCapabilitySetRoundTripsWithStableStringKeys() throws {
        let original = CapabilitySet.baseline(
            for: .appStore,
            evaluatedAt: TestFixtures.date
        ).setting(.available(at: TestFixtures.date), for: .thermalPressure)

        let data = try JSONEncoder().encode(original)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"fanControl\""))
        XCTAssertEqual(try JSONDecoder().decode(CapabilitySet.self, from: data), original)
    }

    func testCapabilityDecoderRejectsUnknownIdentifier() {
        let json = """
        {
          "channel": "direct",
          "states": {
            "madeUpFeature": {
              "availability": "available",
              "evaluatedAt": 0
            }
          }
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(CapabilitySet.self, from: Data(json.utf8))
        )
    }
}
