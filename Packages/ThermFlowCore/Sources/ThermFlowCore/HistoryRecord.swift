import Foundation

/// Compact provenance retained with a historical metric. Short coding keys keep
/// the 30-day JSON archive bounded without discarding trust metadata.
public struct HistoryProvenance: Codable, Equatable, Sendable {
    public let source: MetricSource
    public let quality: MetricQuality
    public let collectorID: String?
    public let derivedFrom: [MetricSource]

    public init(_ provenance: MetricProvenance) {
        source = provenance.source
        quality = provenance.quality
        collectorID = provenance.collectorID
        derivedFrom = provenance.derivedFrom
    }

    private enum CodingKeys: String, CodingKey {
        case source = "s"
        case quality = "q"
        case collectorID = "c"
        case derivedFrom = "d"
    }
}

/// A strongly typed historical value. Unavailable values are always nil and
/// carry their explicit availability instead of a synthetic zero/default.
public struct HistoryMetric<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    public let value: Value?
    public let availability: MetricAvailability
    public let provenance: HistoryProvenance
    public let observedAt: Date
    public let failureCode: String?

    public init(_ sample: MetricSample<Value>) {
        value = sample.availability == .available ? sample.value : nil
        availability = sample.availability
        provenance = HistoryProvenance(sample.provenance)
        observedAt = sample.observedAt
        failureCode = sample.failure?.code
    }

    public var hasAvailableValue: Bool {
        availability == .available && value != nil
    }

    /// Returns a value only when it is explicitly available and not stale or
    /// future-dated relative to the historical record.
    public func usableValue(
        at referenceDate: Date,
        maximumAge: TimeInterval
    ) -> Value? {
        guard hasAvailableValue,
              maximumAge.isFinite,
              maximumAge >= 0 else {
            return nil
        }
        let age = referenceDate.timeIntervalSince(observedAt)
        guard age.isFinite, age >= 0, age <= maximumAge else { return nil }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case value = "v"
        case availability = "a"
        case provenance = "p"
        case observedAt = "t"
        case failureCode = "e"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decodeIfPresent(Value.self, forKey: .value)
        let availability = try container.decode(
            MetricAvailability.self,
            forKey: .availability
        )
        let provenance = try container.decode(
            HistoryProvenance.self,
            forKey: .provenance
        )
        let observedAt = try container.decode(Date.self, forKey: .observedAt)
        let failureCode = try container.decodeIfPresent(
            String.self,
            forKey: .failureCode
        )

        if availability == .available, value == nil {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Available history metrics require a value."
            )
        }
        if availability != .available, value != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Unavailable history metrics cannot contain a value."
            )
        }

        self.value = value
        self.availability = availability
        self.provenance = provenance
        self.observedAt = observedAt
        self.failureCode = failureCode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encode(availability, forKey: .availability)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encodeIfPresent(failureCode, forKey: .failureCode)
    }
}

public struct HistoryFanRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: Int
    public let label: String?
    public let speed: HistoryMetric<FanRPM>
    public let mode: HistoryMetric<FanMode>

    public init(_ fan: FanSnapshot) {
        id = fan.id
        label = fan.label
        speed = HistoryMetric(fan.currentSpeed)
        mode = HistoryMetric(fan.mode)
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i"
        case label = "l"
        case speed = "s"
        case mode = "m"
    }
}

/// A compact, complete historical projection of `SystemSnapshot`.
public struct HistoryRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion: UInt8 = 1

    public let schemaVersion: UInt8
    public let sequence: UInt64
    public let capturedAt: Date
    public let channel: DistributionChannel

    public let thermalPressure: HistoryMetric<ThermalPressure>
    public let cpuTemperature: HistoryMetric<TemperatureCelsius>
    public let gpuTemperature: HistoryMetric<TemperatureCelsius>
    public let cpuUsage: HistoryMetric<Percent>
    public let memoryUsed: HistoryMetric<ByteCount>
    public let memoryTotal: HistoryMetric<ByteCount>
    public let memoryUsage: HistoryMetric<Percent>
    public let memoryPressure: HistoryMetric<MemoryPressure>
    public let storageTotal: HistoryMetric<ByteCount>
    public let storageAvailable: HistoryMetric<ByteCount>
    public let storageUsage: HistoryMetric<Percent>
    public let uploadRate: HistoryMetric<ByteRate>
    public let downloadRate: HistoryMetric<ByteRate>
    public let batteryCycleCount: HistoryMetric<UInt32>
    public let batteryMaximumCapacity: HistoryMetric<Percent>
    public let batteryCondition: HistoryMetric<BatteryCondition>
    public let fans: [HistoryFanRecord]

    public init?(snapshot: SystemSnapshot) {
        guard snapshot.schemaVersion == SystemSnapshot.currentSchemaVersion else {
            return nil
        }
        schemaVersion = Self.currentSchemaVersion
        sequence = snapshot.sequence
        capturedAt = snapshot.capturedAt
        channel = snapshot.channel
        thermalPressure = HistoryMetric(snapshot.thermal.pressure)
        cpuTemperature = HistoryMetric(snapshot.thermal.cpuTemperature)
        gpuTemperature = HistoryMetric(snapshot.thermal.gpuTemperature)
        cpuUsage = HistoryMetric(snapshot.cpu.usage)
        memoryUsed = HistoryMetric(snapshot.memory.used)
        memoryTotal = HistoryMetric(snapshot.memory.total)
        memoryUsage = HistoryMetric(snapshot.memory.usage)
        memoryPressure = HistoryMetric(snapshot.memory.pressure)
        storageTotal = HistoryMetric(snapshot.storage.total)
        storageAvailable = HistoryMetric(snapshot.storage.available)
        storageUsage = HistoryMetric(snapshot.storage.usage)
        uploadRate = HistoryMetric(snapshot.network.uploadRate)
        downloadRate = HistoryMetric(snapshot.network.downloadRate)
        batteryCycleCount = HistoryMetric(snapshot.battery.cycleCount)
        batteryMaximumCapacity = HistoryMetric(snapshot.battery.maximumCapacity)
        batteryCondition = HistoryMetric(snapshot.battery.condition)
        fans = snapshot.fans.map(HistoryFanRecord.init)
    }

    /// Used by the sampler to prefer the most complete real sample when two
    /// snapshots land in the same five-minute bucket.
    public func usableValueCount(maximumAge: TimeInterval = 90) -> Int {
        var count = 0
        if thermalPressure.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if cpuTemperature.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if gpuTemperature.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if cpuUsage.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if memoryUsed.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if memoryTotal.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if memoryUsage.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if memoryPressure.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if storageTotal.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if storageAvailable.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if storageUsage.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if uploadRate.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if downloadRate.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if batteryCycleCount.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if batteryMaximumCapacity.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        if batteryCondition.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        for fan in fans {
            if fan.speed.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
            if fan.mode.usableValue(at: capturedAt, maximumAge: maximumAge) != nil { count += 1 }
        }
        return count
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "v"
        case sequence = "q"
        case capturedAt = "t"
        case channel = "c"
        case thermalPressure = "tp"
        case cpuTemperature = "ct"
        case gpuTemperature = "gt"
        case cpuUsage = "cu"
        case memoryUsed = "mu"
        case memoryTotal = "mt"
        case memoryUsage = "mp"
        case memoryPressure = "mw"
        case storageTotal = "st"
        case storageAvailable = "sa"
        case storageUsage = "sp"
        case uploadRate = "nu"
        case downloadRate = "nd"
        case batteryCycleCount = "bc"
        case batteryMaximumCapacity = "bm"
        case batteryCondition = "bn"
        case fans = "f"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(UInt8.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported history record schema."
            )
        }
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        channel = try container.decode(DistributionChannel.self, forKey: .channel)
        thermalPressure = try container.decode(HistoryMetric<ThermalPressure>.self, forKey: .thermalPressure)
        cpuTemperature = try container.decode(HistoryMetric<TemperatureCelsius>.self, forKey: .cpuTemperature)
        gpuTemperature = try container.decode(HistoryMetric<TemperatureCelsius>.self, forKey: .gpuTemperature)
        cpuUsage = try container.decode(HistoryMetric<Percent>.self, forKey: .cpuUsage)
        memoryUsed = try container.decode(HistoryMetric<ByteCount>.self, forKey: .memoryUsed)
        memoryTotal = try container.decode(HistoryMetric<ByteCount>.self, forKey: .memoryTotal)
        memoryUsage = try container.decode(HistoryMetric<Percent>.self, forKey: .memoryUsage)
        memoryPressure = try container.decode(HistoryMetric<MemoryPressure>.self, forKey: .memoryPressure)
        storageTotal = try container.decode(HistoryMetric<ByteCount>.self, forKey: .storageTotal)
        storageAvailable = try container.decode(HistoryMetric<ByteCount>.self, forKey: .storageAvailable)
        storageUsage = try container.decode(HistoryMetric<Percent>.self, forKey: .storageUsage)
        uploadRate = try container.decode(HistoryMetric<ByteRate>.self, forKey: .uploadRate)
        downloadRate = try container.decode(HistoryMetric<ByteRate>.self, forKey: .downloadRate)
        batteryCycleCount = try container.decode(HistoryMetric<UInt32>.self, forKey: .batteryCycleCount)
        batteryMaximumCapacity = try container.decode(HistoryMetric<Percent>.self, forKey: .batteryMaximumCapacity)
        batteryCondition = try container.decode(HistoryMetric<BatteryCondition>.self, forKey: .batteryCondition)
        fans = try container.decode([HistoryFanRecord].self, forKey: .fans)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(channel, forKey: .channel)
        try container.encode(thermalPressure, forKey: .thermalPressure)
        try container.encode(cpuTemperature, forKey: .cpuTemperature)
        try container.encode(gpuTemperature, forKey: .gpuTemperature)
        try container.encode(cpuUsage, forKey: .cpuUsage)
        try container.encode(memoryUsed, forKey: .memoryUsed)
        try container.encode(memoryTotal, forKey: .memoryTotal)
        try container.encode(memoryUsage, forKey: .memoryUsage)
        try container.encode(memoryPressure, forKey: .memoryPressure)
        try container.encode(storageTotal, forKey: .storageTotal)
        try container.encode(storageAvailable, forKey: .storageAvailable)
        try container.encode(storageUsage, forKey: .storageUsage)
        try container.encode(uploadRate, forKey: .uploadRate)
        try container.encode(downloadRate, forKey: .downloadRate)
        try container.encode(batteryCycleCount, forKey: .batteryCycleCount)
        try container.encode(batteryMaximumCapacity, forKey: .batteryMaximumCapacity)
        try container.encode(batteryCondition, forKey: .batteryCondition)
        try container.encode(fans, forKey: .fans)
    }
}
