import Foundation
import XCTest
@testable import ThermFlowCore

final class HistoryPolicyTests: XCTestCase {
    private let sampler = HistorySamplingPolicy()

    func testUndeterminedEntitlementPreservesProRetentionUntilFreeIsDefinitive() {
        XCTAssertEqual(HistoryEntitlementAccess.undetermined.retentionAccess, .pro)
        XCTAssertEqual(HistoryEntitlementAccess.pro.retentionAccess, .pro)
        XCTAssertEqual(HistoryEntitlementAccess.free.retentionAccess, .free)
    }

    func testSameFiveMinuteBucketKeepsLatestEquallyTrustedRecord() {
        let first = TestFixtures.historyRecord(
            at: Date(timeIntervalSince1970: 0),
            sequence: 10,
            cpuTemperature: 50
        )
        let latest = TestFixtures.historyRecord(
            at: Date(timeIntervalSince1970: 299.999),
            sequence: 1,
            cpuTemperature: 60
        )

        let result = sampler.inserting(latest, into: [first])

        XCTAssertEqual(result.action, .replaced)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records[0].capturedAt, latest.capturedAt)
        XCTAssertEqual(result.records[0].cpuTemperature.value, TemperatureCelsius(60))
    }

    func testMoreCompleteRecordWinsWithinBucket() {
        let complete = TestFixtures.historyRecord(
            at: Date(timeIntervalSince1970: 1),
            cpuTemperature: 55,
            cpuUsage: 20
        )
        let laterButSparse = TestFixtures.historyRecord(
            at: Date(timeIntervalSince1970: 250),
            sequence: 99,
            cpuTemperature: 65
        )

        let result = sampler.inserting(laterButSparse, into: [complete])

        XCTAssertEqual(result.action, .ignored)
        XCTAssertEqual(result.records, [complete])
    }

    func testExactFiveMinuteBoundaryCreatesNewBucket() {
        let first = TestFixtures.historyRecord(at: Date(timeIntervalSince1970: 0))
        let next = TestFixtures.historyRecord(at: Date(timeIntervalSince1970: 300))

        let result = sampler.inserting(next, into: [first])

        XCTAssertEqual(result.action, .appended)
        XCTAssertEqual(result.records, [first, next])
    }

    func testDuplicateInsertionIsIdempotent() {
        let record = TestFixtures.historyRecord(
            at: TestFixtures.date,
            sequence: 7,
            cpuUsage: 42
        )

        let result = sampler.inserting(record, into: [record])

        XCTAssertEqual(result.action, .ignored)
        XCTAssertEqual(result.records, [record])
    }

    func testNegativeEpochUsesFloorInsteadOfIntegerTruncation() {
        XCTAssertEqual(
            sampler.bucketID(for: Date(timeIntervalSince1970: -0.001)),
            -1
        )
        XCTAssertEqual(
            sampler.bucketID(for: Date(timeIntervalSince1970: 0)),
            0
        )
    }

    func testNormalizationSortsAndDeduplicatesUnorderedRecords() {
        let early = TestFixtures.historyRecord(at: Date(timeIntervalSince1970: 1))
        let sameBucketLatest = TestFixtures.historyRecord(
            at: Date(timeIntervalSince1970: 200),
            sequence: 2
        )
        let next = TestFixtures.historyRecord(at: Date(timeIntervalSince1970: 600))

        XCTAssertEqual(
            sampler.normalized([next, early, sameBucketLatest]),
            [sameBucketLatest, next]
        )
    }

    func testFreeRetentionKeepsExact24HourBoundaryAndRejectsOlderAndFuture() {
        let policy = HistoryRetentionPolicy(access: .free)
        let now = TestFixtures.date
        let cutoff = now.addingTimeInterval(-HistoryRetentionPolicy.freeDuration)
        let tooOld = TestFixtures.historyRecord(at: cutoff.addingTimeInterval(-0.001))
        let exact = TestFixtures.historyRecord(at: cutoff)
        let current = TestFixtures.historyRecord(at: now)
        let future = TestFixtures.historyRecord(at: now.addingTimeInterval(0.001))

        let retained = policy.applying(
            to: [future, current, tooOld, exact],
            referenceDate: now
        )

        XCTAssertEqual(retained, [exact, current])
        XCTAssertEqual(policy.maximumExpectedRecordCount, 289)
    }

    func testProRetentionKeepsExact30DayBoundary() {
        let policy = HistoryRetentionPolicy(access: .pro)
        let now = TestFixtures.date
        let cutoff = now.addingTimeInterval(-HistoryRetentionPolicy.proDuration)
        let tooOld = TestFixtures.historyRecord(at: cutoff.addingTimeInterval(-1))
        let exact = TestFixtures.historyRecord(at: cutoff)

        XCTAssertEqual(
            policy.applying(to: [tooOld, exact], referenceDate: now),
            [exact]
        )
        XCTAssertEqual(policy.maximumExpectedRecordCount, 8_641)
    }

    func testDowngradeToFreePrunesWithoutInventingOrRestoringRecords() {
        let now = TestFixtures.date
        let recent = TestFixtures.historyRecord(at: now.addingTimeInterval(-60))
        let tenDaysOld = TestFixtures.historyRecord(
            at: now.addingTimeInterval(-10 * 24 * 60 * 60)
        )
        let pro = HistoryRetentionPolicy(access: .pro).applying(
            to: [tenDaysOld, recent],
            referenceDate: now
        )
        let free = HistoryRetentionPolicy(access: .free).applying(
            to: pro,
            referenceDate: now
        )
        let upgradedAgain = HistoryRetentionPolicy(access: .pro).applying(
            to: free,
            referenceDate: now
        )

        XCTAssertEqual(pro, [tenDaysOld, recent])
        XCTAssertEqual(free, [recent])
        XCTAssertEqual(upgradedAgain, [recent])
    }
}
