import Foundation

public struct CPUTicks: Codable, Equatable, Sendable {
    public let user: UInt64
    public let system: UInt64
    public let idle: UInt64
    public let nice: UInt64

    public init(
        user: UInt64,
        system: UInt64,
        idle: UInt64,
        nice: UInt64
    ) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

/// Derives total CPU utilization from cumulative Mach CPU ticks.
public struct CPULoadCalculator: Sendable {
    private struct Baseline: Sendable {
        let ticks: CPUTicks
        let capturedAt: Date
    }

    private var baseline: Baseline?

    public init() {}

    public mutating func reset() {
        baseline = nil
    }

    public mutating func sample(
        ticks: CPUTicks,
        capturedAt: Date
    ) -> MetricSample<Percent> {
        let provenance = MetricProvenance.derived(
            collectorID: "CPULoadCalculator",
            from: [.machKernel]
        )

        guard let previous = baseline else {
            baseline = Baseline(ticks: ticks, capturedAt: capturedAt)
            return .unavailable(
                .temporarilyUnavailable,
                provenance: provenance,
                observedAt: capturedAt,
                failure: MetricFailure(code: "needsPreviousSample")
            )
        }

        guard capturedAt > previous.capturedAt else {
            return .failed(
                code: "nonMonotonicTimestamp",
                provenance: provenance,
                observedAt: capturedAt
            )
        }

        guard ticks.user >= previous.ticks.user,
              ticks.system >= previous.ticks.system,
              ticks.idle >= previous.ticks.idle,
              ticks.nice >= previous.ticks.nice else {
            baseline = Baseline(ticks: ticks, capturedAt: capturedAt)
            return .unavailable(
                .temporarilyUnavailable,
                provenance: provenance,
                observedAt: capturedAt,
                failure: MetricFailure(code: "counterReset")
            )
        }

        let userDelta = ticks.user - previous.ticks.user
        let systemDelta = ticks.system - previous.ticks.system
        let idleDelta = ticks.idle - previous.ticks.idle
        let niceDelta = ticks.nice - previous.ticks.nice
        baseline = Baseline(ticks: ticks, capturedAt: capturedAt)

        let (busyPartial, busyOverflow) = userDelta.addingReportingOverflow(systemDelta)
        let (busy, niceOverflow) = busyPartial.addingReportingOverflow(niceDelta)
        let (total, totalOverflow) = busy.addingReportingOverflow(idleDelta)
        guard !busyOverflow, !niceOverflow, !totalOverflow else {
            return .failed(
                code: "counterOverflow",
                provenance: provenance,
                observedAt: capturedAt
            )
        }

        guard total > 0 else {
            return .unavailable(
                .temporarilyUnavailable,
                provenance: provenance,
                observedAt: capturedAt,
                failure: MetricFailure(code: "noTickProgress")
            )
        }

        guard let percent = Percent(ratio: Double(busy) / Double(total)) else {
            return .failed(
                code: "invalidPercentage",
                provenance: provenance,
                observedAt: capturedAt
            )
        }

        return .available(
            percent,
            provenance: provenance,
            observedAt: capturedAt
        )
    }
}
