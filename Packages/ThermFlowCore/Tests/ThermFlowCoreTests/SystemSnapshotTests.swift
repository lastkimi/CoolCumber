import Foundation
import XCTest
@testable import ThermFlowCore

final class SystemSnapshotTests: XCTestCase {
    func testEmptySnapshotContainsUnknownValuesInsteadOfSyntheticDefaults() {
        let snapshot = SystemSnapshot.empty(
            channel: .appStore,
            capturedAt: TestFixtures.date
        )

        XCTAssertEqual(snapshot.schemaVersion, SystemSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.channel, .appStore)
        XCTAssertEqual(snapshot.thermal.cpuTemperature.availability, .unknown)
        XCTAssertNil(snapshot.thermal.cpuTemperature.value)
        XCTAssertEqual(snapshot.cpu.usage.availability, .unknown)
        XCTAssertNil(snapshot.cpu.usage.value)
        XCTAssertEqual(snapshot.battery.cycleCount.availability, .unknown)
        XCTAssertTrue(snapshot.fans.isEmpty)
    }

    func testSnapshotRoundTripsThroughCodable() throws {
        var capabilities = CapabilitySet.baseline(
            for: .direct,
            evaluatedAt: TestFixtures.date
        )
        capabilities.set(.available(at: TestFixtures.date), for: .cpuTemperature)
        let snapshot = TestFixtures.snapshot(
            capabilities: capabilities,
            pressure: .available(
                .nominal,
                provenance: TestFixtures.reportedProcessInfo,
                observedAt: TestFixtures.date
            ),
            cpuTemperature: .available(
                TemperatureCelsius(61.5)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: TestFixtures.date
            ),
            cpuUsage: .available(
                Percent(35)!,
                provenance: TestFixtures.measuredMach,
                observedAt: TestFixtures.date
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let decoded = try JSONDecoder().decode(SystemSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testDecoderRejectsUnknownSchemaVersion() throws {
        let snapshot = SystemSnapshot.empty(
            channel: .appStore,
            capturedAt: TestFixtures.date
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = Int(SystemSnapshot.currentSchemaVersion) + 1
        let unknownSchema = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try JSONDecoder().decode(SystemSnapshot.self, from: unknownSchema)
        )
    }
}
