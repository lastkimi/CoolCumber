import Foundation
@testable import ThermFlowCore

enum TestFixtures {
    static let date = Date(timeIntervalSince1970: 1_750_000_000)
    static let measuredMach = MetricProvenance.measured(
        by: .machKernel,
        collectorID: "test"
    )
    static let reportedProcessInfo = MetricProvenance.reported(
        by: .processInfo,
        collectorID: "test"
    )
    static let measuredSMC = MetricProvenance.measured(
        by: .smc,
        collectorID: "test"
    )
    static let measuredFileSystem = MetricProvenance.reported(
        by: .fileSystem,
        collectorID: "test"
    )

    static func snapshot(
        schemaVersion: UInt16 = SystemSnapshot.currentSchemaVersion,
        sequence: UInt64 = 1,
        channel: DistributionChannel = .direct,
        capabilities: CapabilitySet? = nil,
        pressure: MetricSample<ThermalPressure>? = nil,
        cpuTemperature: MetricSample<TemperatureCelsius>? = nil,
        gpuTemperature: MetricSample<TemperatureCelsius>? = nil,
        cpuUsage: MetricSample<Percent>? = nil,
        memoryUsage: MetricSample<Percent>? = nil,
        diskAvailable: MetricSample<ByteCount>? = nil,
        fans: [FanSnapshot] = [],
        at date: Date = TestFixtures.date
    ) -> SystemSnapshot {
        SystemSnapshot(
            schemaVersion: schemaVersion,
            sequence: sequence,
            capturedAt: date,
            capabilities: capabilities ?? .baseline(for: channel, evaluatedAt: date),
            thermal: ThermalSnapshot(
                pressure: pressure ?? .unknown(observedAt: date),
                cpuTemperature: cpuTemperature ?? .unknown(observedAt: date),
                gpuTemperature: gpuTemperature ?? .unknown(observedAt: date)
            ),
            cpu: CPUSnapshot(
                usage: cpuUsage ?? .unknown(observedAt: date)
            ),
            memory: MemorySnapshot(
                used: .unknown(observedAt: date),
                total: .unknown(observedAt: date),
                usage: memoryUsage ?? .unknown(observedAt: date),
                pressure: .unknown(observedAt: date)
            ),
            storage: StorageSnapshot(
                total: .unknown(observedAt: date),
                available: diskAvailable ?? .unknown(observedAt: date),
                usage: .unknown(observedAt: date)
            ),
            network: .unknown(at: date),
            battery: .unknown(at: date),
            fans: fans
        )
    }

    static func historyRecord(
        at date: Date,
        sequence: UInt64 = 1,
        cpuTemperature: Double? = nil,
        cpuUsage: Double? = nil
    ) -> HistoryRecord {
        let temperatureSample = cpuTemperature.flatMap(TemperatureCelsius.init).map {
            MetricSample<TemperatureCelsius>.available(
                $0,
                provenance: measuredSMC,
                observedAt: date
            )
        }
        let usageSample = cpuUsage.flatMap { Percent($0) }.map {
            MetricSample<Percent>.available(
                $0,
                provenance: measuredMach,
                observedAt: date
            )
        }
        return HistoryRecord(
            snapshot: snapshot(
                sequence: sequence,
                cpuTemperature: temperatureSample,
                cpuUsage: usageSample,
                at: date
            )
        )!
    }
}
