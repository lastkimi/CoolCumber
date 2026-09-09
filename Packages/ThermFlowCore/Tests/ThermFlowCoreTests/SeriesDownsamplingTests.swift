import XCTest
@testable import ThermFlowCore

final class SeriesDownsamplingTests: XCTestCase {
    private struct Point: Equatable {
        let sequence: Int
        let series: String
    }

    func testInterleavedSeriesReceiveIndependentBudgets() {
        let points = (0..<100).flatMap { sequence in
            ["temperature", "cpu", "memory"].map {
                Point(sequence: sequence, series: $0)
            }
        }

        let sampled = SeriesDownsamplingPolicy.evenlySpaced(
            points,
            maximumCount: 30,
            seriesID: \Point.series
        )

        XCTAssertEqual(sampled.count, 30)
        XCTAssertEqual(Dictionary(grouping: sampled, by: \Point.series).mapValues(\.count), [
            "temperature": 10,
            "cpu": 10,
            "memory": 10
        ])
        for series in ["temperature", "cpu", "memory"] {
            let values = sampled.filter { $0.series == series }.map(\.sequence)
            XCTAssertEqual(values.first, 0)
            XCTAssertEqual(values.last, 99)
        }
        XCTAssertEqual(sampled.map(\.sequence), sampled.map(\.sequence).sorted())
    }

    func testReturnsInputWhenAlreadyWithinLimit() {
        let points = [Point(sequence: 1, series: "a"), Point(sequence: 2, series: "b")]
        XCTAssertEqual(
            SeriesDownsamplingPolicy.evenlySpaced(
                points,
                maximumCount: 2,
                seriesID: \Point.series
            ),
            points
        )
    }

    func testZeroBudgetReturnsNoPoints() {
        XCTAssertTrue(
            SeriesDownsamplingPolicy.evenlySpaced(
                [Point(sequence: 1, series: "a")],
                maximumCount: 0,
                seriesID: \Point.series
            ).isEmpty
        )
    }
}
