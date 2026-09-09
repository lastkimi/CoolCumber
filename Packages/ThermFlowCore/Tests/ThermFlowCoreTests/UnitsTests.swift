import Foundation
import XCTest
@testable import ThermFlowCore

final class UnitsTests: XCTestCase {
    func testPercentAcceptsOnlyFiniteValuesInClosedRange() {
        XCTAssertEqual(Percent(0)?.value, 0)
        XCTAssertEqual(Percent(100)?.value, 100)
        XCTAssertEqual(Percent(ratio: 0.375)?.value, 37.5)
        XCTAssertEqual(Percent(25)?.ratio, 0.25)
        XCTAssertNil(Percent(-0.001))
        XCTAssertNil(Percent(100.001))
        XCTAssertNil(Percent(.infinity))
        XCTAssertNil(Percent(.nan))
    }

    func testInvalidPercentCannotBeDecoded() {
        XCTAssertThrowsError(try JSONDecoder().decode(Percent.self, from: Data("101".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(Percent.self, from: Data("-1".utf8)))
    }

    func testByteCountUsesBytesAndOffersExplicitBinaryConversions() {
        let count = ByteCount(1_073_741_824)
        XCTAssertEqual(count.value, 1_073_741_824)
        XCTAssertEqual(count.kibibytes, 1_048_576)
        XCTAssertEqual(count.mebibytes, 1_024)
        XCTAssertEqual(count.gibibytes, 1)
    }

    func testByteRateDistinguishesDecimalAndBinaryMegabytes() {
        let decimal = ByteRate(1_000_000)!
        let binary = ByteRate(1_048_576)!
        XCTAssertEqual(decimal.megabytesPerSecond, 1)
        XCTAssertEqual(binary.mebibytesPerSecond, 1)
        XCTAssertNil(ByteRate(-1))
        XCTAssertNil(ByteRate(.infinity))
    }

    func testTemperatureAndFanSpeedRejectImpossibleDomainValues() {
        XCTAssertEqual(TemperatureCelsius(-273.15)?.value, -273.15)
        XCTAssertNil(TemperatureCelsius(-273.151))
        XCTAssertNil(TemperatureCelsius(.nan))
        XCTAssertEqual(FanRPM(0)?.value, 0)
        XCTAssertNil(FanRPM(-1))
    }

    func testValidatedUnitsRoundTripThroughCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let temperature = TemperatureCelsius(81.25)!
        XCTAssertEqual(
            try decoder.decode(TemperatureCelsius.self, from: encoder.encode(temperature)),
            temperature
        )

        let rate = ByteRate(123_456.75)!
        XCTAssertEqual(
            try decoder.decode(ByteRate.self, from: encoder.encode(rate)),
            rate
        )
    }
}
