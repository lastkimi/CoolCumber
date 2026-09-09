import Foundation
import XCTest
@testable import ThermFlowCore

final class HistoryArchiveTests: XCTestCase {
    func testArchiveRoundTripPreservesMillisecondTimestamp() throws {
        let date = Date(timeIntervalSince1970: 1_750_000_000.999)
        let record = TestFixtures.historyRecord(
            at: date,
            sequence: 8,
            cpuTemperature: 64.25
        )
        let codec = HistoryArchiveCodec()

        let decoded = try codec.decode(codec.encode([record]))

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(
            decoded[0].capturedAt.timeIntervalSince1970,
            date.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(decoded[0].cpuTemperature.value, TemperatureCelsius(64.25))
    }

    func testMalformedAndTruncatedArchivesFailClosed() {
        let codec = HistoryArchiveCodec()

        XCTAssertThrowsError(try codec.decode(Data())) { error in
            XCTAssertEqual(error as? HistoryArchiveError, .invalidArchive)
        }
        XCTAssertThrowsError(try codec.decode(Data("{\"v\":1,\"r\":[".utf8))) { error in
            XCTAssertEqual(error as? HistoryArchiveError, .invalidArchive)
        }
    }

    func testUnsupportedArchiveSchemaIsRejected() {
        let data = Data("{\"v\":2,\"r\":[]}".utf8)

        XCTAssertThrowsError(try HistoryArchiveCodec().decode(data)) { error in
            XCTAssertEqual(error as? HistoryArchiveError, .unsupportedSchema)
        }
    }

    func testDecodeRejectsEntryCountBeyondHardLimit() throws {
        let records = [
            TestFixtures.historyRecord(at: TestFixtures.date),
            TestFixtures.historyRecord(at: TestFixtures.date.addingTimeInterval(300))
        ]
        let data = try HistoryArchiveCodec(
            maximumRecords: 10,
            maximumBytes: 1_000_000
        ).encode(records)
        let limited = HistoryArchiveCodec(
            maximumRecords: 1,
            maximumBytes: 1_000_000
        )

        XCTAssertThrowsError(try limited.decode(data)) { error in
            XCTAssertEqual(error as? HistoryArchiveError, .tooManyRecords)
        }
    }

    func testOversizedInputIsRejectedBeforeDecode() {
        let codec = HistoryArchiveCodec(maximumRecords: 10, maximumBytes: 8)

        XCTAssertThrowsError(try codec.decode(Data(repeating: 0, count: 9))) { error in
            XCTAssertEqual(error as? HistoryArchiveError, .archiveTooLarge)
        }
    }

    func testEncodingFitsLimitsByKeepingNewestRecordsOnly() throws {
        let records = (0..<3).map {
            TestFixtures.historyRecord(
                at: TestFixtures.date.addingTimeInterval(Double($0) * 300),
                sequence: UInt64($0)
            )
        }
        let roomy = HistoryArchiveCodec(
            maximumRecords: 10,
            maximumBytes: 1_000_000
        )
        let oneRecordSize = try roomy.encode([records.last!]).count
        let limited = HistoryArchiveCodec(
            maximumRecords: 10,
            maximumBytes: oneRecordSize
        )

        let result = try limited.encodeNewestRecordsFitting(records)

        XCTAssertEqual(result.records, [records.last!])
        XCTAssertLessThanOrEqual(result.data.count, oneRecordSize)
        XCTAssertEqual(try limited.decode(result.data), [records.last!])
    }

    func testEncodeRejectsRecordCountInsteadOfSilentlyDropping() {
        let codec = HistoryArchiveCodec(maximumRecords: 1, maximumBytes: 1_000_000)
        let records = [
            TestFixtures.historyRecord(at: TestFixtures.date),
            TestFixtures.historyRecord(at: TestFixtures.date.addingTimeInterval(300))
        ]

        XCTAssertThrowsError(try codec.encode(records)) { error in
            XCTAssertEqual(error as? HistoryArchiveError, .tooManyRecords)
        }
    }
}
