import Foundation
import XCTest
@testable import ThermFlowCore

final class HistoryRecordTests: XCTestCase {
    func testSnapshotConversionPreservesTypedValueAndTrustMetadata() throws {
        let fan = FanSnapshot(
            id: 0,
            label: "Left",
            currentSpeed: .available(
                FanRPM(2_345)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: TestFixtures.date
            ),
            mode: .unknown(observedAt: TestFixtures.date)
        )
        let snapshot = TestFixtures.snapshot(
            sequence: 42,
            cpuTemperature: .available(
                TemperatureCelsius(63.5)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: TestFixtures.date
            ),
            cpuUsage: .unavailable(
                .temporarilyUnavailable,
                provenance: TestFixtures.measuredMach,
                observedAt: TestFixtures.date,
                failure: MetricFailure(code: "needsPreviousSample")
            ),
            fans: [fan]
        )

        let record = try XCTUnwrap(HistoryRecord(snapshot: snapshot))

        XCTAssertEqual(record.schemaVersion, HistoryRecord.currentSchemaVersion)
        XCTAssertEqual(record.sequence, 42)
        XCTAssertEqual(record.capturedAt, TestFixtures.date)
        XCTAssertEqual(record.channel, .direct)
        XCTAssertEqual(record.cpuTemperature.value, TemperatureCelsius(63.5))
        XCTAssertEqual(record.cpuTemperature.availability, .available)
        XCTAssertEqual(record.cpuTemperature.provenance.source, .smc)
        XCTAssertEqual(record.cpuTemperature.observedAt, TestFixtures.date)
        XCTAssertNil(record.cpuUsage.value)
        XCTAssertEqual(record.cpuUsage.availability, .temporarilyUnavailable)
        XCTAssertEqual(record.cpuUsage.failureCode, "needsPreviousSample")
        XCTAssertEqual(record.fans.first?.speed.value, FanRPM(2_345))
        XCTAssertNil(record.fans.first?.mode.value)
    }

    func testEmptySnapshotNeverCreatesSyntheticHistoryValues() throws {
        let record = try XCTUnwrap(HistoryRecord(
            snapshot: .empty(
                channel: .appStore,
                capturedAt: TestFixtures.date
            )
        ))

        XCTAssertNil(record.cpuTemperature.value)
        XCTAssertNil(record.cpuUsage.value)
        XCTAssertNil(record.memoryUsage.value)
        XCTAssertNil(record.storageAvailable.value)
        XCTAssertNil(record.batteryMaximumCapacity.value)
        XCTAssertTrue(record.fans.isEmpty)
        XCTAssertEqual(record.usableValueCount(), 0)
    }

    func testHistoryMetricRejectsUnavailableValueDuringDecode() {
        let json = """
        {
          "v": 50,
          "a": "unknown",
          "p": {"s": "unknown", "q": "unknown", "d": []},
          "t": 0
        }
        """

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                HistoryMetric<Percent>.self,
                from: Data(json.utf8)
            )
        )
    }

    func testUsableValueRejectsStaleAndFutureObservedTimes() throws {
        let staleSnapshot = TestFixtures.snapshot(
            cpuTemperature: .available(
                TemperatureCelsius(50)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: TestFixtures.date.addingTimeInterval(-91)
            ),
            at: TestFixtures.date
        )
        let futureSnapshot = TestFixtures.snapshot(
            cpuTemperature: .available(
                TemperatureCelsius(51)!,
                provenance: TestFixtures.measuredSMC,
                observedAt: TestFixtures.date.addingTimeInterval(1)
            ),
            at: TestFixtures.date
        )

        XCTAssertNil(
            try XCTUnwrap(HistoryRecord(snapshot: staleSnapshot)).cpuTemperature.usableValue(
                at: TestFixtures.date,
                maximumAge: 90
            )
        )
        XCTAssertNil(
            try XCTUnwrap(HistoryRecord(snapshot: futureSnapshot)).cpuTemperature.usableValue(
                at: TestFixtures.date,
                maximumAge: 90
            )
        )
    }

    func testProjectionRejectsUnknownSystemSnapshotSchema() {
        let snapshot = TestFixtures.snapshot(schemaVersion: 2)
        XCTAssertNil(HistoryRecord(snapshot: snapshot))
    }

    func testRecordUsesCompactCodingKeysAndRoundTrips() throws {
        let record = TestFixtures.historyRecord(
            at: TestFixtures.date,
            cpuTemperature: 61
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"ct\""))
        XCTAssertFalse(json.contains("cpuTemperature"))
        XCTAssertEqual(
            try JSONDecoder().decode(HistoryRecord.self, from: data),
            record
        )
    }
}
