import Foundation

public enum ThermalPressure: String, Codable, CaseIterable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

public enum MemoryPressure: String, Codable, CaseIterable, Sendable {
    case nominal
    case warning
    case critical
}

public enum FanMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual
    case unknown
}

public enum BatteryCondition: String, Codable, CaseIterable, Sendable {
    case normal
    case serviceRecommended
    case unknown
}

public struct ThermalSnapshot: Codable, Equatable, Sendable {
    public let pressure: MetricSample<ThermalPressure>
    public let cpuTemperature: MetricSample<TemperatureCelsius>
    public let gpuTemperature: MetricSample<TemperatureCelsius>

    public init(
        pressure: MetricSample<ThermalPressure>,
        cpuTemperature: MetricSample<TemperatureCelsius>,
        gpuTemperature: MetricSample<TemperatureCelsius>
    ) {
        self.pressure = pressure
        self.cpuTemperature = cpuTemperature
        self.gpuTemperature = gpuTemperature
    }

    public static func unknown(at date: Date) -> ThermalSnapshot {
        ThermalSnapshot(
            pressure: .unknown(observedAt: date),
            cpuTemperature: .unknown(observedAt: date),
            gpuTemperature: .unknown(observedAt: date)
        )
    }
}

public struct CPUSnapshot: Codable, Equatable, Sendable {
    public let usage: MetricSample<Percent>

    public init(usage: MetricSample<Percent>) {
        self.usage = usage
    }

    public static func unknown(at date: Date) -> CPUSnapshot {
        CPUSnapshot(usage: .unknown(observedAt: date))
    }
}

public struct MemorySnapshot: Codable, Equatable, Sendable {
    public let used: MetricSample<ByteCount>
    public let total: MetricSample<ByteCount>
    public let usage: MetricSample<Percent>
    public let pressure: MetricSample<MemoryPressure>

    public init(
        used: MetricSample<ByteCount>,
        total: MetricSample<ByteCount>,
        usage: MetricSample<Percent>,
        pressure: MetricSample<MemoryPressure>
    ) {
        self.used = used
        self.total = total
        self.usage = usage
        self.pressure = pressure
    }

    public static func unknown(at date: Date) -> MemorySnapshot {
        MemorySnapshot(
            used: .unknown(observedAt: date),
            total: .unknown(observedAt: date),
            usage: .unknown(observedAt: date),
            pressure: .unknown(observedAt: date)
        )
    }
}

public struct StorageSnapshot: Codable, Equatable, Sendable {
    public let total: MetricSample<ByteCount>
    public let available: MetricSample<ByteCount>
    public let usage: MetricSample<Percent>

    public init(
        total: MetricSample<ByteCount>,
        available: MetricSample<ByteCount>,
        usage: MetricSample<Percent>
    ) {
        self.total = total
        self.available = available
        self.usage = usage
    }

    public static func unknown(at date: Date) -> StorageSnapshot {
        StorageSnapshot(
            total: .unknown(observedAt: date),
            available: .unknown(observedAt: date),
            usage: .unknown(observedAt: date)
        )
    }
}

public struct NetworkSnapshot: Codable, Equatable, Sendable {
    public let uploadRate: MetricSample<ByteRate>
    public let downloadRate: MetricSample<ByteRate>

    public init(
        uploadRate: MetricSample<ByteRate>,
        downloadRate: MetricSample<ByteRate>
    ) {
        self.uploadRate = uploadRate
        self.downloadRate = downloadRate
    }

    public static func unknown(at date: Date) -> NetworkSnapshot {
        NetworkSnapshot(
            uploadRate: .unknown(observedAt: date),
            downloadRate: .unknown(observedAt: date)
        )
    }
}

public struct BatterySnapshot: Codable, Equatable, Sendable {
    public let cycleCount: MetricSample<UInt32>
    public let maximumCapacity: MetricSample<Percent>
    public let condition: MetricSample<BatteryCondition>

    public init(
        cycleCount: MetricSample<UInt32>,
        maximumCapacity: MetricSample<Percent>,
        condition: MetricSample<BatteryCondition>
    ) {
        self.cycleCount = cycleCount
        self.maximumCapacity = maximumCapacity
        self.condition = condition
    }

    public static func unknown(at date: Date) -> BatterySnapshot {
        BatterySnapshot(
            cycleCount: .unknown(observedAt: date),
            maximumCapacity: .unknown(observedAt: date),
            condition: .unknown(observedAt: date)
        )
    }
}

public struct FanSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let label: String?
    public let currentSpeed: MetricSample<FanRPM>
    public let mode: MetricSample<FanMode>

    public init(
        id: Int,
        label: String? = nil,
        currentSpeed: MetricSample<FanRPM>,
        mode: MetricSample<FanMode>
    ) {
        self.id = id
        self.label = label
        self.currentSpeed = currentSpeed
        self.mode = mode
    }
}

public struct SystemSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: UInt16 = 1

    public let schemaVersion: UInt16
    public let sequence: UInt64
    public let capturedAt: Date
    public let capabilities: CapabilitySet
    public let thermal: ThermalSnapshot
    public let cpu: CPUSnapshot
    public let memory: MemorySnapshot
    public let storage: StorageSnapshot
    public let network: NetworkSnapshot
    public let battery: BatterySnapshot
    public let fans: [FanSnapshot]

    public var channel: DistributionChannel { capabilities.channel }

    public init(
        schemaVersion: UInt16 = SystemSnapshot.currentSchemaVersion,
        sequence: UInt64,
        capturedAt: Date,
        capabilities: CapabilitySet,
        thermal: ThermalSnapshot,
        cpu: CPUSnapshot,
        memory: MemorySnapshot,
        storage: StorageSnapshot,
        network: NetworkSnapshot,
        battery: BatterySnapshot,
        fans: [FanSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.sequence = sequence
        self.capturedAt = capturedAt
        self.capabilities = capabilities
        self.thermal = thermal
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.network = network
        self.battery = battery
        self.fans = fans
    }

    public static func empty(
        channel: DistributionChannel,
        sequence: UInt64 = 0,
        capturedAt: Date
    ) -> SystemSnapshot {
        SystemSnapshot(
            sequence: sequence,
            capturedAt: capturedAt,
            capabilities: .baseline(for: channel, evaluatedAt: capturedAt),
            thermal: .unknown(at: capturedAt),
            cpu: .unknown(at: capturedAt),
            memory: .unknown(at: capturedAt),
            storage: .unknown(at: capturedAt),
            network: .unknown(at: capturedAt),
            battery: .unknown(at: capturedAt),
            fans: []
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sequence
        case capturedAt
        case capabilities
        case thermal
        case cpu
        case memory
        case storage
        case network
        case battery
        case fans
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(UInt16.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported system snapshot schema."
            )
        }

        self.init(
            schemaVersion: schemaVersion,
            sequence: try container.decode(UInt64.self, forKey: .sequence),
            capturedAt: try container.decode(Date.self, forKey: .capturedAt),
            capabilities: try container.decode(CapabilitySet.self, forKey: .capabilities),
            thermal: try container.decode(ThermalSnapshot.self, forKey: .thermal),
            cpu: try container.decode(CPUSnapshot.self, forKey: .cpu),
            memory: try container.decode(MemorySnapshot.self, forKey: .memory),
            storage: try container.decode(StorageSnapshot.self, forKey: .storage),
            network: try container.decode(NetworkSnapshot.self, forKey: .network),
            battery: try container.decode(BatterySnapshot.self, forKey: .battery),
            fans: try container.decode([FanSnapshot].self, forKey: .fans)
        )
    }
}
