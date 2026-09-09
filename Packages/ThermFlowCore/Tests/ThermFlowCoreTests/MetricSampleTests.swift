import Foundation
import XCTest
@testable import ThermFlowCore

final class MetricSampleTests: XCTestCase {
    func testAvailableSampleCarriesValueSourceQualityAndTime() {
        let sample = MetricSample<Percent>.available(
            Percent(42)!,
            provenance: TestFixtures.measuredMach,
            observedAt: TestFixtures.date
        )

        XCTAssertEqual(sample.availability, .available)
        XCTAssertEqual(sample.value, Percent(42))
        XCTAssertEqual(sample.provenance.source, .machKernel)
        XCTAssertEqual(sample.provenance.quality, .measured)
        XCTAssertEqual(sample.observedAt, TestFixtures.date)
        XCTAssertNil(sample.failure)
    }

    func testUnknownAndFailedSamplesNeverPretendZeroIsAValue() {
        let unknown = MetricSample<ByteCount>.unknown(observedAt: TestFixtures.date)
        XCTAssertEqual(unknown.availability, .unknown)
        XCTAssertNil(unknown.value)

        let failed = MetricSample<ByteCount>.failed(
            code: "collectorTimedOut",
            provenance: TestFixtures.measuredMach,
            observedAt: TestFixtures.date
        )
        XCTAssertEqual(failed.availability, .failed)
        XCTAssertNil(failed.value)
        XCTAssertEqual(failed.failure?.code, "collectorTimedOut")
    }

    func testFreshnessBoundaryAndUsableValue() {
        let sample = MetricSample<Percent>.available(
            Percent(50)!,
            provenance: TestFixtures.measuredMach,
            observedAt: TestFixtures.date
        )

        XCTAssertEqual(
            sample.freshness(at: TestFixtures.date.addingTimeInterval(15), maximumAge: 15),
            .fresh
        )
        XCTAssertEqual(
            sample.freshness(at: TestFixtures.date.addingTimeInterval(15.001), maximumAge: 15),
            .stale
        )
        XCTAssertEqual(
            sample.usableValue(at: TestFixtures.date.addingTimeInterval(15), maximumAge: 15),
            Percent(50)
        )
        XCTAssertNil(
            sample.usableValue(at: TestFixtures.date.addingTimeInterval(16), maximumAge: 15)
        )
        XCTAssertEqual(
            sample.freshness(at: TestFixtures.date, maximumAge: -1),
            .stale
        )
        XCTAssertEqual(
            sample.freshness(
                at: TestFixtures.date.addingTimeInterval(-0.001),
                maximumAge: 15
            ),
            .stale
        )
        XCTAssertNil(
            sample.usableValue(
                at: TestFixtures.date.addingTimeInterval(-0.001),
                maximumAge: 15
            )
        )
    }

    func testUnavailableSampleIsNotUsableEvenWhenFresh() {
        let sample = MetricSample<Percent>.unavailable(
            .unsupported,
            provenance: .reported(by: .processInfo),
            observedAt: TestFixtures.date
        )
        XCTAssertNil(sample.usableValue(at: TestFixtures.date, maximumAge: 15))
    }

    func testSampleRoundTripsThroughCodable() throws {
        let original = MetricSample<TemperatureCelsius>.available(
            TemperatureCelsius(72.5)!,
            provenance: TestFixtures.measuredSMC,
            observedAt: TestFixtures.date
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(
            try JSONDecoder().decode(MetricSample<TemperatureCelsius>.self, from: data),
            original
        )
    }

    func testDecoderRejectsValueOnUnavailableSample() {
        let json = """
        {
          "value": 42,
          "availability": "unknown",
          "provenance": {
            "source": "unknown",
            "quality": "unknown",
            "derivedFrom": []
          },
          "observedAt": 0
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(MetricSample<Percent>.self, from: Data(json.utf8))
        )
    }

    func testDecoderRejectsFailedSampleWithoutFailureDetails() {
        let json = """
        {
          "availability": "failed",
          "provenance": {
            "source": "unknown",
            "quality": "unknown",
            "derivedFrom": []
          },
          "observedAt": 0
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(MetricSample<Percent>.self, from: Data(json.utf8))
        )
    }
}
