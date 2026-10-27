import Foundation
import XCTest
@testable import ThermFlowCore

final class WorkloadCheckTests: XCTestCase {
    private let start = TestFixtures.date

    func testRealTwoPhaseObservationSummariesDoNotClaimCausation() throws {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        for index in 0..<3 { _ = check.ingest(snapshot(at: index * 10, sequence: UInt64(index + 1), cpu: 60), at: date(index * 10)) }
        XCTAssertTrue(check.canAdvance)
        try check.beginComparison(at: date(21))
        for index in 0..<3 { _ = check.ingest(snapshot(at: 30 + index * 10, sequence: UInt64(index + 4), cpu: 20), at: date(30 + index * 10)) }
        try check.finish(at: date(51))
        XCTAssertEqual(check.phase, .completed)
        XCTAssertEqual(check.baselineSummary.meanCPU, 60)
        XCTAssertEqual(check.comparisonSummary.meanCPU, 20)
        XCTAssertEqual(check.baselineSummary.cpuSampleCount, 3)
        XCTAssertEqual(check.comparisonSummary.thermalSampleCount, 3)
        XCTAssertEqual(check.comparisonSummary.highestThermalPressure, .fair)
        XCTAssertNoThrow(try check.validate(at: date(60)))
    }

    func testTooFewOrTooShortObservationsCannotAdvance() throws {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        XCTAssertThrowsError(try check.beginComparison(at: start)) { XCTAssertEqual($0 as? WorkloadCheckError, .insufficientSamples) }
        for index in 0..<3 { _ = check.ingest(snapshot(at: index, sequence: UInt64(index + 1)), at: date(index)) }
        XCTAssertFalse(check.canAdvance)
        XCTAssertThrowsError(try check.beginComparison(at: date(20)))
        XCTAssertThrowsError(try check.finish(at: date(21))) { XCTAssertEqual($0 as? WorkloadCheckError, .wrongPhase) }
    }

    func testDuplicateCachedAndOutOfOrderSnapshotsDoNotCreateProgress() throws {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        let first = snapshot(at: 0, sequence: 1)
        XCTAssertTrue(check.ingest(first, at: start))
        XCTAssertFalse(check.ingest(first, at: date(1)))
        XCTAssertFalse(check.ingest(snapshot(at: 10, sequence: 1), at: date(10)))
        XCTAssertFalse(check.ingest(snapshot(at: 10, sequence: 2, observedAt: 0), at: date(10)))
        XCTAssertFalse(check.ingest(snapshot(at: 20, sequence: 3, observedAt: 0), at: date(20)))
        XCTAssertEqual(check.points.count, 1)
        XCTAssertFalse(check.canAdvance)
    }

    func testFutureStaleAndWrongChannelSnapshotsAreRejected() throws {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        XCTAssertFalse(check.ingest(snapshot(at: 10, sequence: 1), at: start))
        XCTAssertFalse(check.ingest(snapshot(at: 0, sequence: 1), at: date(31)))
        XCTAssertFalse(check.ingest(TestFixtures.snapshot(channel: .direct, at: start), at: start))
        XCTAssertFalse(check.ingest(TestFixtures.snapshot(schemaVersion: 99, channel: .appStore, at: start), at: start))
        XCTAssertTrue(check.points.isEmpty)
    }

    func testCapabilityAndProvenanceMustBeTrusted() throws {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        let fixture = MetricProvenance(source: .fixture, quality: .fixture)
        _ = check.ingest(snapshot(at: 0, sequence: 1, provenance: fixture, thermalProvenance: fixture), at: start)
        XCTAssertEqual(check.usablePointCount, 0)
        XCTAssertNil(check.baselineSummary.meanCPU)
        XCTAssertNil(check.baselineSummary.meanMemory)
        XCTAssertNil(check.baselineSummary.highestThermalPressure)
        var unsupported = snapshot(at: 10, sequence: 2)
        unsupported = TestFixtures.snapshot(sequence: unsupported.sequence, channel: .appStore,
            pressure: unsupported.thermal.pressure, cpuUsage: unsupported.cpu.usage, memoryUsage: unsupported.memory.usage, at: date(10))
        _ = check.ingest(unsupported, at: date(10))
        XCTAssertFalse(check.canAdvance)
        XCTAssertEqual(check.usablePointCount, 0)
    }

    func testDerivedKernelUsageIsAcceptedButUnknownParentsAreNot() throws {
        var good = try WorkloadCheck(channel: .appStore, startedAt: start)
        _ = good.ingest(snapshot(at: 0, sequence: 1, provenance: .derived(collectorID: "test", from: [.machKernel])), at: start)
        XCTAssertEqual(good.points.first?.cpuValue, 30)
        var bad = try WorkloadCheck(channel: .appStore, startedAt: start)
        let unknown = MetricProvenance.derived(collectorID: "test", from: [.unknown])
        _ = bad.ingest(snapshot(at: 0, sequence: 1, provenance: unknown), at: start)
        XCTAssertNil(bad.points.first?.cpuValue)
        XCTAssertNil(bad.points.first?.memoryValue)
    }

    func testReadingsFromBeforeComparisonBoundaryAreNotReused() throws {
        var check = try baseline()
        try check.beginComparison(at: date(21))
        _ = check.ingest(snapshot(at: 30, sequence: 4, observedAt: 20), at: date(30))
        XCTAssertEqual(check.comparisonSummary.cpuSampleCount, 0)
        XCTAssertEqual(check.comparisonSummary.thermalSampleCount, 0)
        XCTAssertFalse(check.canAdvance)
    }

    func testFreshnessIsCheckedAgainstLiveReferenceNotOnlySnapshotTime() throws {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        _ = check.ingest(snapshot(at: 29, sequence: 1, observedAt: 0), at: date(40))
        XCTAssertEqual(check.points.count, 1)
        XCTAssertEqual(check.usablePointCount, 0)
    }

    func testDurationLimitInterruptsWithoutInventingData() throws {
        var check = try baseline()
        XCTAssertFalse(check.ingest(snapshot(at: 301, sequence: 9), at: date(301)))
        XCTAssertEqual(check.phase, .interrupted)
        XCTAssertEqual(check.endedAt, date(20))
        XCTAssertEqual(check.points.count, 3)
        XCTAssertNoThrow(try check.validate(at: date(302)))
    }

    func testPointLimitIsBounded() throws {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        for index in 0..<WorkloadCheck.maximumPoints {
            XCTAssertTrue(check.ingest(snapshot(at: index, sequence: UInt64(index + 1)), at: date(index)))
        }
        XCTAssertFalse(check.ingest(snapshot(at: 100, sequence: 101), at: date(100)))
        XCTAssertEqual(check.points.count, WorkloadCheck.maximumPoints)
        XCTAssertEqual(check.phase, .interrupted)
    }

    func testNoteValidationAndSpreadsheetSafeExport() throws {
        XCTAssertThrowsError(try WorkloadCheck(note: String(repeating: "a", count: 81), channel: .appStore, startedAt: start))
        XCTAssertThrowsError(try WorkloadCheck(note: "one\ntwo", channel: .appStore, startedAt: start))
        var check = try WorkloadCheck(note: "=HYPERLINK(\"bad\")", channel: .appStore, startedAt: start)
        _ = check.ingest(snapshot(at: 0, sequence: 1), at: start)
        let csv = String(decoding: WorkloadCheckCSVEncoder().data(from: check), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"'=HYPERLINK(\"\"bad\"\")\""))
        XCTAssertTrue(csv.contains("30.00"))
        XCTAssertTrue(csv.contains("fair"))
        XCTAssertFalse(csv.contains("cpu_temperature"))
    }

    func testUnavailableExportValuesRemainBlankNotZero() throws {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        let unknown = MetricProvenance(source: .unknown, quality: .unknown)
        _ = check.ingest(snapshot(at: 0, sequence: 1, provenance: unknown), at: start)
        let csv = String(decoding: WorkloadCheckCSVEncoder().data(from: check), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"\",\"stale_or_untrusted\""))
        XCTAssertFalse(csv.contains(",\"0.00\","))
    }

    func testSeparateRepositoryPreservesLegacyHistoryBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyURL = directory.appendingPathComponent("telemetry-history-v1.json")
        let legacy = try HistoryArchiveCodec().encodeNewestRecordsFitting([TestFixtures.historyRecord(at: start, cpuUsage: 20)]).data
        try legacy.write(to: legacyURL)
        let repository = WorkloadCheckFileRepository(fileURL: directory.appendingPathComponent("workload-check-v1.json"))
        let check = try baseline()
        XCTAssertEqual(repository.persist(check, at: date(21)).status, .ready)
        XCTAssertEqual(repository.load(at: date(21)).check, check)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacy)
        XCTAssertEqual(HistoryFileRepository(fileURL: legacyURL).load(access: .undetermined, referenceDate: date(21)).records.count, 1)
    }

    func testUnknownAndOversizedArchivesArePreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workload-check-v1.json")
        let repository = WorkloadCheckFileRepository(fileURL: url)
        let invalid = Data("{\"version\":99,\"check\":{}}".utf8)
        try invalid.write(to: url)
        XCTAssertEqual(repository.load(at: date(30)).status, .invalidArchivePreserved)
        XCTAssertEqual(repository.persist(try baseline(), at: date(30)).status, .invalidArchivePreserved)
        XCTAssertEqual(try Data(contentsOf: url), invalid)
        let oversized = Data(repeating: 0x20, count: WorkloadCheckFileRepository.maximumBytes + 1)
        try oversized.write(to: url)
        XCTAssertEqual(repository.load(at: date(30)).status, .limitsExceeded)
        XCTAssertEqual(repository.persist(try baseline(), at: date(30)).status, .limitsExceeded)
        XCTAssertEqual(try Data(contentsOf: url), oversized)
    }

    func testFutureArchiveAndMissingStorageFailClosed() throws {
        let repository = WorkloadCheckFileRepository(fileURL: nil)
        XCTAssertEqual(repository.load(at: start).status, .storageUnavailable)
        XCTAssertEqual(repository.persist(try baseline(), at: date(30)).status, .storageUnavailable)
        XCTAssertThrowsError(try baseline().validate(at: date(-1)))
    }

    private func baseline() throws -> WorkloadCheck {
        var check = try WorkloadCheck(channel: .appStore, startedAt: start)
        for index in 0..<3 { _ = check.ingest(snapshot(at: index * 10, sequence: UInt64(index + 1)), at: date(index * 10)) }
        return check
    }

    private func date(_ seconds: Int) -> Date { start.addingTimeInterval(TimeInterval(seconds)) }

    private func snapshot(at second: Int, sequence: UInt64, cpu: Double = 30, observedAt: Int? = nil,
                          provenance: MetricProvenance = TestFixtures.measuredMach,
                          thermalProvenance: MetricProvenance = TestFixtures.reportedProcessInfo) -> SystemSnapshot {
        let captured = date(second)
        let observed = date(observedAt ?? second)
        var capabilities = CapabilitySet.baseline(for: .appStore, evaluatedAt: captured)
        for id: CapabilityID in [.cpuUsage, .memoryUsage, .thermalPressure] { capabilities.set(.available(at: captured), for: id) }
        return TestFixtures.snapshot(sequence: sequence, channel: .appStore, capabilities: capabilities,
            pressure: .available(.fair, provenance: thermalProvenance, observedAt: observed),
            cpuUsage: .available(Percent(cpu)!, provenance: provenance, observedAt: observed),
            memoryUsage: .available(Percent(50)!, provenance: provenance, observedAt: observed), at: captured)
    }
}
