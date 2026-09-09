import Foundation
import XCTest
@testable import ThermFlowCore

final class HistoryCSVEncoderTests: XCTestCase {
    func testCSVExportsOnlyFreshAvailableValues() throws {
        let record = TestFixtures.historyRecord(
            at: TestFixtures.date,
            cpuTemperature: 55.5
        )
        let table = try csvTable(HistoryCSVEncoder().string(from: [record]))

        XCTAssertEqual(table.value(row: 0, column: "cpu_temperature_c_value"), "55.5")
        XCTAssertEqual(table.value(row: 0, column: "cpu_temperature_c_availability"), "available")
        XCTAssertEqual(table.value(row: 0, column: "cpu_temperature_c_source"), "smc")
        XCTAssertEqual(table.value(row: 0, column: "cpu_usage_percent_value"), "")
        XCTAssertEqual(table.value(row: 0, column: "cpu_usage_percent_availability"), "unknown")
    }

    func testUnknownSnapshotLeavesEveryValueColumnBlankInsteadOfZero() throws {
        let record = try XCTUnwrap(
            HistoryRecord(
                snapshot: .empty(channel: .appStore, capturedAt: TestFixtures.date)
            )
        )
        let table = try csvTable(HistoryCSVEncoder().string(from: [record]))

        for (index, header) in table.headers.enumerated()
        where header.hasSuffix("_value") || header == "fans_rpm" {
            XCTAssertEqual(table.rows[0][index], "", "Unexpected value in \(header)")
        }
    }

    func testStaleAndFutureAvailableMetricsAreBlank() throws {
        let stale = try XCTUnwrap(
            HistoryRecord(
                snapshot: TestFixtures.snapshot(
                    cpuTemperature: .available(
                        TemperatureCelsius(70)!,
                        provenance: TestFixtures.measuredSMC,
                        observedAt: TestFixtures.date.addingTimeInterval(-91)
                    ),
                    at: TestFixtures.date
                )
            )
        )
        let future = try XCTUnwrap(
            HistoryRecord(
                snapshot: TestFixtures.snapshot(
                    cpuTemperature: .available(
                        TemperatureCelsius(71)!,
                        provenance: TestFixtures.measuredSMC,
                        observedAt: TestFixtures.date.addingTimeInterval(301)
                    ),
                    at: TestFixtures.date.addingTimeInterval(300)
                )
            )
        )
        let table = try csvTable(HistoryCSVEncoder().string(from: [stale, future]))

        XCTAssertEqual(table.value(row: 0, column: "cpu_temperature_c_value"), "")
        XCTAssertEqual(table.value(row: 1, column: "cpu_temperature_c_value"), "")
        XCTAssertEqual(table.value(row: 0, column: "cpu_temperature_c_availability"), "available")
        XCTAssertEqual(table.value(row: 1, column: "cpu_temperature_c_availability"), "available")
    }

    func testTextEscapingIsRFC4180Compatible() {
        XCTAssertEqual(HistoryCSVEncoder.escapeText("plain"), "plain")
        XCTAssertEqual(HistoryCSVEncoder.escapeText("中文🌡️"), "中文🌡️")
        XCTAssertEqual(
            HistoryCSVEncoder.escapeText("a,\"b\"\n"),
            "\"a,\"\"b\"\"\n\""
        )
        XCTAssertEqual(HistoryCSVEncoder.escapeText("a\0b"), "a�b")
    }

    func testSpreadsheetFormulaPrefixesAreNeutralized() {
        XCTAssertEqual(HistoryCSVEncoder.escapeText("=1+1"), "'=1+1")
        XCTAssertEqual(HistoryCSVEncoder.escapeText(" +SUM(A1)"), "' +SUM(A1)")
        XCTAssertEqual(HistoryCSVEncoder.escapeText("\t@command"), "'\t@command")
        XCTAssertEqual(
            HistoryCSVEncoder.escapeText("\u{FEFF}=command"),
            "'\u{FEFF}=command"
        )
    }

    func testLegitimateNegativeNumericValueRemainsNumeric() throws {
        let record = TestFixtures.historyRecord(
            at: TestFixtures.date,
            cpuTemperature: -5
        )
        let table = try csvTable(HistoryCSVEncoder().string(from: [record]))

        XCTAssertEqual(table.value(row: 0, column: "cpu_temperature_c_value"), "-5")
    }

    func testEmptyHistoryProducesStableHeaderOnlyCSV() throws {
        let csv = HistoryCSVEncoder().string(from: [])
        let lines = csv.components(separatedBy: "\r\n")

        XCTAssertTrue(lines[0].hasPrefix("captured_at,sequence,channel"))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], "")
        XCTAssertEqual(HistoryCSVEncoder().data(from: []), Data(csv.utf8))
    }

    private func csvTable(_ csv: String) throws -> CSVTable {
        let lines = csv.components(separatedBy: "\r\n")
        guard lines.count >= 3 else { throw TestError.invalidCSV }
        let headers = lines[0].split(
            separator: ",",
            omittingEmptySubsequences: false
        ).map(String.init)
        let rows = lines.dropFirst().dropLast().map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        guard rows.allSatisfy({ $0.count == headers.count }) else {
            throw TestError.invalidCSV
        }
        return CSVTable(headers: headers, rows: rows)
    }

    private enum TestError: Error {
        case invalidCSV
    }

    private struct CSVTable {
        let headers: [String]
        let rows: [[String]]

        func value(row: Int, column: String) -> String? {
            guard let index = headers.firstIndex(of: column), rows.indices.contains(row) else {
                return nil
            }
            return rows[row][index]
        }
    }
}
