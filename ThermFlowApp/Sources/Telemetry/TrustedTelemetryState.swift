import Foundation
import ThermFlowCore

struct TrustedTelemetryState {
    private(set) var sequence: UInt64 = 0
    var capabilities: CapabilitySet
    var thermal: ThermalSnapshot
    var cpu: CPUSnapshot
    var memory: MemorySnapshot
    var storage: StorageSnapshot
    var network: NetworkSnapshot
    var battery: BatterySnapshot
    var fans: [FanSnapshot]

    init(channel: DistributionChannel, at date: Date) {
        capabilities = .baseline(for: channel, evaluatedAt: date)
        thermal = .unknown(at: date)
        cpu = .unknown(at: date)
        memory = .unknown(at: date)
        storage = .unknown(at: date)
        network = .unknown(at: date)
        battery = .unknown(at: date)
        fans = []
    }

    mutating func setCapability(
        _ capability: CapabilityID,
        from sampleAvailability: MetricAvailability,
        reasonCode: String? = nil,
        at date: Date
    ) {
        let availability: CapabilityAvailability
        switch sampleAvailability {
        case .available:
            availability = .available
        case .unsupported:
            availability = .unsupported
        case .notPresent:
            availability = .notPresent
        case .permissionRequired:
            availability = .authorizationRequired
        case .temporarilyUnavailable, .failed:
            availability = .temporarilyUnavailable
        case .unknown:
            availability = .unknown
        }
        capabilities.set(
            CapabilityState(
                availability: availability,
                reasonCode: reasonCode,
                evaluatedAt: date
            ),
            for: capability
        )
    }

    mutating func makeSnapshot(capturedAt: Date) -> SystemSnapshot {
        sequence &+= 1
        return SystemSnapshot(
            sequence: sequence,
            capturedAt: capturedAt,
            capabilities: capabilities,
            thermal: thermal,
            cpu: cpu,
            memory: memory,
            storage: storage,
            network: network,
            battery: battery,
            fans: fans
        )
    }
}
