import Foundation

/// Converts a monotonically increasing byte counter into a byte-per-second rate.
/// Counter decreases are treated as resets, never as unsigned wrap-around traffic.
public struct CounterRateCalculator: Sendable {
    private struct Baseline: Sendable {
        let counter: UInt64
        let capturedAt: Date
    }

    private var baseline: Baseline?
    private let inputSource: MetricSource
    private let collectorID: String

    public init(
        inputSource: MetricSource = .networkInterface,
        collectorID: String = "CounterRateCalculator"
    ) {
        self.inputSource = inputSource
        self.collectorID = collectorID
    }

    public mutating func reset() {
        baseline = nil
    }

    public mutating func sample(
        counter: UInt64,
        capturedAt: Date
    ) -> MetricSample<ByteRate> {
        let provenance = MetricProvenance.derived(
            collectorID: collectorID,
            from: [inputSource]
        )

        guard let previous = baseline else {
            baseline = Baseline(counter: counter, capturedAt: capturedAt)
            return .unavailable(
                .temporarilyUnavailable,
                provenance: provenance,
                observedAt: capturedAt,
                failure: MetricFailure(code: "needsPreviousSample")
            )
        }

        let elapsed = capturedAt.timeIntervalSince(previous.capturedAt)
        guard elapsed.isFinite, elapsed > 0 else {
            return .failed(
                code: "nonMonotonicTimestamp",
                provenance: provenance,
                observedAt: capturedAt
            )
        }

        guard counter >= previous.counter else {
            baseline = Baseline(counter: counter, capturedAt: capturedAt)
            return .unavailable(
                .temporarilyUnavailable,
                provenance: provenance,
                observedAt: capturedAt,
                failure: MetricFailure(code: "counterReset")
            )
        }

        let delta = counter - previous.counter
        baseline = Baseline(counter: counter, capturedAt: capturedAt)
        guard let rate = ByteRate(Double(delta) / elapsed) else {
            return .failed(
                code: "invalidRate",
                provenance: provenance,
                observedAt: capturedAt
            )
        }

        return .available(
            rate,
            provenance: provenance,
            observedAt: capturedAt
        )
    }
}
