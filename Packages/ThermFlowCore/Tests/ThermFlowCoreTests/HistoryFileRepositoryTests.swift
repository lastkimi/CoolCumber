import Foundation
import XCTest
@testable import ThermFlowCore

final class HistoryFileRepositoryTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testPersistReloadAndRemoveRoundTripUsesRealTemporaryFile() throws {
        let now = TestFixtures.date
        let fileURL = makeHistoryFileURL()
        let repository = HistoryFileRepository(
            fileURL: fileURL,
            maximumRecords: 2,
            maximumBytes: 1_000_000
        )
        let records = [
            TestFixtures.historyRecord(at: now.addingTimeInterval(-600), sequence: 1),
            TestFixtures.historyRecord(at: now.addingTimeInterval(-300), sequence: 2),
            TestFixtures.historyRecord(at: now, sequence: 3)
        ]

        let persisted = repository.persist(records)
        XCTAssertEqual(persisted.status, .ready)
        XCTAssertEqual(persisted.records, Array(records.suffix(2)))
        XCTAssertEqual(
            repository.load(access: .pro, referenceDate: now),
            persisted
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        XCTAssertEqual(
            repository.remove(existingRecords: persisted.records),
            HistoryPersistenceResult(records: [], status: .ready)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testBoundedReadRejectsOversizedArchiveBeforeDecode() throws {
        let fileURL = makeHistoryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 33).write(to: fileURL)
        let repository = HistoryFileRepository(
            fileURL: fileURL,
            maximumRecords: 10,
            maximumBytes: 32
        )

        XCTAssertEqual(
            repository.load(access: .pro, referenceDate: TestFixtures.date),
            HistoryPersistenceResult(records: [], status: .limitsExceeded)
        )
    }

    func testLoadAppliesConfirmedFreeRetentionWithoutMutatingArchive() throws {
        let now = TestFixtures.date
        let fileURL = makeHistoryFileURL()
        let oldPaidRecord = TestFixtures.historyRecord(
            at: now.addingTimeInterval(-10 * 24 * 60 * 60),
            sequence: 1
        )
        let recentRecord = TestFixtures.historyRecord(
            at: now.addingTimeInterval(-60),
            sequence: 2
        )
        let repository = HistoryFileRepository(fileURL: fileURL)
        XCTAssertEqual(repository.persist([oldPaidRecord, recentRecord]).status, .ready)

        XCTAssertEqual(
            repository.load(access: .free, referenceDate: now),
            HistoryPersistenceResult(records: [recentRecord], status: .ready)
        )
        XCTAssertEqual(
            repository.load(access: .pro, referenceDate: now).records,
            [oldPaidRecord, recentRecord],
            "A read-only Free projection must not silently destroy the paid archive."
        )
    }

    func testCorruptArchiveFailsClosedWithoutDeletingEvidenceFile() throws {
        let fileURL = makeHistoryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let corrupt = Data("{not-json".utf8)
        try corrupt.write(to: fileURL)
        let repository = HistoryFileRepository(fileURL: fileURL)

        XCTAssertEqual(
            repository.load(access: .pro, referenceDate: TestFixtures.date),
            HistoryPersistenceResult(records: [], status: .corruptArchive)
        )
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
        let fresh = TestFixtures.historyRecord(at: TestFixtures.date, cpuUsage: 20)
        XCTAssertEqual(repository.persist([fresh]).status, .corruptArchive)
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt,
                       "New real telemetry must not erase the unreadable legacy evidence.")
    }

    func testUnavailableContainerFailsClosedWithoutDiscardingWriteInput() {
        let record = TestFixtures.historyRecord(at: TestFixtures.date)
        let repository = HistoryFileRepository(fileURL: nil)

        XCTAssertEqual(
            repository.load(access: .pro, referenceDate: TestFixtures.date),
            HistoryPersistenceResult(records: [], status: .appGroupUnavailable)
        )
        XCTAssertEqual(
            repository.persist([record]),
            HistoryPersistenceResult(
                records: [record],
                status: .appGroupUnavailable
            )
        )
    }

    private func makeHistoryFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CoolCumberHistoryRepositoryTests-\(UUID().uuidString)",
                isDirectory: true
            )
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("history.json")
    }
}
