import Foundation

public enum WorkloadCheckPhase: String, Codable, Sendable {
    case baseline, comparison, completed, interrupted
}

public enum WorkloadCheckError: Error, Equatable {
    case invalidNote, invalidTime, invalidArchive, insufficientSamples, wrongPhase, limitReached
}

/// A real observation, not a benchmark score or a synthetic temperature. Values
/// remain optional when capabilities, provenance or freshness cannot be trusted.
public struct WorkloadCheckPoint: Codable, Equatable, Sendable, Identifiable {
    public let sequence: UInt64
    public let capturedAt: Date
    public let phase: WorkloadCheckPhase
    public let cpu: HistoryMetric<Percent>
    public let memory: HistoryMetric<Percent>
    public let thermal: HistoryMetric<ThermalPressure>

    public var id: UInt64 { sequence }
    public static let maximumMetricAge: TimeInterval = 30

    public var cpuValue: Double? { Self.kernelValue(cpu, at: capturedAt)?.value }
    public var memoryValue: Double? { Self.kernelValue(memory, at: capturedAt)?.value }
    public var thermalValue: ThermalPressure? {
        guard thermal.provenance.source == .processInfo,
              thermal.provenance.quality == .systemReported else { return nil }
        return thermal.usableValue(at: capturedAt, maximumAge: Self.maximumMetricAge)
    }
    public var hasUsableValue: Bool { cpuValue != nil || memoryValue != nil || thermalValue != nil }
    var usableObservationDates: [Date?] {
        [cpuValue == nil ? nil : cpu.observedAt, memoryValue == nil ? nil : memory.observedAt,
         thermalValue == nil ? nil : thermal.observedAt]
    }

    init(snapshot: SystemSnapshot, phase: WorkloadCheckPhase, phaseStartedAt: Date, at referenceDate: Date) {
        sequence = snapshot.sequence
        capturedAt = snapshot.capturedAt
        self.phase = phase
        cpu = Self.project(snapshot.cpu.usage, capability: .cpuUsage, snapshot: snapshot, phaseStartedAt: phaseStartedAt, at: referenceDate)
        memory = Self.project(snapshot.memory.usage, capability: .memoryUsage, snapshot: snapshot, phaseStartedAt: phaseStartedAt, at: referenceDate)
        thermal = Self.project(snapshot.thermal.pressure, capability: .thermalPressure, snapshot: snapshot, phaseStartedAt: phaseStartedAt, at: referenceDate)
    }

    private static func project<Value>(_ sample: MetricSample<Value>, capability: CapabilityID,
                                       snapshot: SystemSnapshot, phaseStartedAt: Date, at date: Date) -> HistoryMetric<Value>
    where Value: Codable & Equatable & Sendable {
        guard snapshot.capabilities.allows(capability, at: date, maximumAge: maximumMetricAge) else {
            return HistoryMetric(.unavailable(.temporarilyUnavailable, provenance: sample.provenance,
                observedAt: sample.observedAt, failure: MetricFailure(code: "capabilityUnavailable")))
        }
        if sample.availability == .available,
           sample.observedAt < phaseStartedAt || sample.freshness(at: date, maximumAge: maximumMetricAge) != .fresh {
            return HistoryMetric(.unavailable(.temporarilyUnavailable, provenance: sample.provenance,
                observedAt: sample.observedAt, failure: MetricFailure(code: "staleOrBeforePhase")))
        }
        return HistoryMetric(sample)
    }

    private static func kernelValue<Value>(_ sample: HistoryMetric<Value>, at date: Date) -> Value?
    where Value: Codable & Equatable & Sendable {
        let provenance = sample.provenance
        let measured = provenance.source == .machKernel
            && [.measured, .systemReported].contains(provenance.quality)
        let derived = provenance.source == .derived && provenance.quality == .derived
            && !provenance.derivedFrom.isEmpty && provenance.derivedFrom.allSatisfy { $0 == .machKernel }
        guard measured || derived else { return nil }
        return sample.usableValue(at: date, maximumAge: maximumMetricAge)
    }
}

public struct WorkloadPhaseSummary: Equatable, Sendable {
    public let pointCount: Int
    public let cpuSampleCount: Int
    public let memorySampleCount: Int
    public let thermalSampleCount: Int
    public let meanCPU: Double?
    public let meanMemory: Double?
    public let highestThermalPressure: ThermalPressure?

    init(points: [WorkloadCheckPoint]) {
        var cpuDates = Set<Date>()
        var memoryDates = Set<Date>()
        var thermalDates = Set<Date>()
        let cpu = points.compactMap { point in
            point.cpuValue.flatMap { cpuDates.insert(point.cpu.observedAt).inserted ? $0 : nil }
        }
        let memory = points.compactMap { point in
            point.memoryValue.flatMap { memoryDates.insert(point.memory.observedAt).inserted ? $0 : nil }
        }
        let thermal = points.compactMap { point in
            point.thermalValue.flatMap { thermalDates.insert(point.thermal.observedAt).inserted ? $0 : nil }
        }
        pointCount = points.count
        cpuSampleCount = cpu.count
        memorySampleCount = memory.count
        thermalSampleCount = thermal.count
        meanCPU = cpu.isEmpty ? nil : cpu.reduce(0, +) / Double(cpu.count)
        meanMemory = memory.isEmpty ? nil : memory.reduce(0, +) / Double(memory.count)
        highestThermalPressure = thermal.max { Self.rank($0) < Self.rank($1) }
    }

    private static func rank(_ value: ThermalPressure) -> Int {
        switch value { case .nominal: return 0; case .fair: return 1; case .serious: return 2; case .critical: return 3 }
    }
}

/// One explicit, on-device before/after observation. Its separate, bounded
/// document never changes the schema or retention of the existing v1 history.
/// A completion means sufficient real observations, never proof of causation.
public struct WorkloadCheck: Codable, Equatable, Sendable, Identifiable {
    public static let schemaVersion: UInt8 = 1
    public static let maximumPoints = 90
    public static let maximumDuration: TimeInterval = 300
    public static let minimumPhasePoints = 3
    public static let minimumPhaseDuration: TimeInterval = 20

    public let id: UUID
    public let note: String
    public let channel: DistributionChannel
    public let startedAt: Date
    public private(set) var comparisonStartedAt: Date?
    public private(set) var endedAt: Date?
    public private(set) var phase: WorkloadCheckPhase
    public private(set) var points: [WorkloadCheckPoint]

    public init(note: String = "", channel: DistributionChannel, startedAt: Date) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 80, trimmed.utf8.count <= 320,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw WorkloadCheckError.invalidNote
        }
        guard startedAt.timeIntervalSinceReferenceDate.isFinite else { throw WorkloadCheckError.invalidTime }
        id = UUID()
        self.note = trimmed
        self.channel = channel
        self.startedAt = startedAt
        comparisonStartedAt = nil
        endedAt = nil
        phase = .baseline
        points = []
    }

    public var isRecording: Bool { phase == .baseline || phase == .comparison }
    public var baselineSummary: WorkloadPhaseSummary { WorkloadPhaseSummary(points: points.filter { $0.phase == .baseline }) }
    public var comparisonSummary: WorkloadPhaseSummary { WorkloadPhaseSummary(points: points.filter { $0.phase == .comparison }) }
    public var canAdvance: Bool { isRecording && phaseIsSufficient(phase) }
    public var usablePointCount: Int { points.filter(\.hasUsableValue).count }

    @discardableResult
    public mutating func ingest(_ snapshot: SystemSnapshot, at referenceDate: Date) -> Bool {
        guard isRecording else { return false }
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite,
              snapshot.schemaVersion == SystemSnapshot.currentSchemaVersion,
              snapshot.channel == channel else { return false }
        let age = referenceDate.timeIntervalSince(snapshot.capturedAt)
        guard age.isFinite, age >= 0, age <= WorkloadCheckPoint.maximumMetricAge,
              snapshot.capturedAt >= (comparisonStartedAt ?? startedAt) else { return false }
        if referenceDate.timeIntervalSince(startedAt) > Self.maximumDuration || points.count >= Self.maximumPoints {
            interrupt()
            return false
        }
        if let previous = points.last,
           snapshot.capturedAt <= previous.capturedAt || snapshot.sequence <= previous.sequence { return false }
        let point = WorkloadCheckPoint(snapshot: snapshot, phase: phase,
            phaseStartedAt: comparisonStartedAt ?? startedAt, at: referenceDate)
        if let previous = points.last, previous.phase == phase,
           previous.usableObservationDates == point.usableObservationDates { return false }
        points.append(point)
        return true
    }

    public mutating func beginComparison(at date: Date) throws {
        guard phase == .baseline else { throw WorkloadCheckError.wrongPhase }
        try validateTransition(at: date)
        guard phaseIsSufficient(.baseline) else { throw WorkloadCheckError.insufficientSamples }
        comparisonStartedAt = date
        phase = .comparison
    }

    public mutating func finish(at date: Date) throws {
        guard phase == .comparison else { throw WorkloadCheckError.wrongPhase }
        try validateTransition(at: date)
        guard phaseIsSufficient(.comparison) else { throw WorkloadCheckError.insufficientSamples }
        endedAt = date
        phase = .completed
    }

    public mutating func interrupt() {
        guard isRecording else { return }
        endedAt = points.last?.capturedAt ?? startedAt
        phase = .interrupted
    }

    public func validate(at referenceDate: Date) throws {
        guard note.count <= 80, note.utf8.count <= 320,
              !note.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              points.count <= Self.maximumPoints,
              startedAt.timeIntervalSinceReferenceDate.isFinite,
              startedAt <= referenceDate else { throw WorkloadCheckError.invalidArchive }
        var previous: WorkloadCheckPoint?
        for point in points {
            guard [.baseline, .comparison].contains(point.phase), point.capturedAt >= startedAt,
                  point.capturedAt <= referenceDate,
                  point.capturedAt.timeIntervalSince(startedAt) <= Self.maximumDuration else {
                throw WorkloadCheckError.invalidArchive
            }
            if let previous, point.capturedAt <= previous.capturedAt || point.sequence <= previous.sequence {
                throw WorkloadCheckError.invalidArchive
            }
            if point.phase == .comparison {
                guard let comparisonStartedAt, point.capturedAt >= comparisonStartedAt else { throw WorkloadCheckError.invalidArchive }
            } else if let comparisonStartedAt, point.capturedAt > comparisonStartedAt { throw WorkloadCheckError.invalidArchive }
            previous = point
        }
        if let boundary = comparisonStartedAt {
            guard boundary >= startedAt, boundary <= referenceDate,
                  boundary.timeIntervalSince(startedAt) <= Self.maximumDuration else { throw WorkloadCheckError.invalidArchive }
        }
        if let end = endedAt {
            guard end >= (points.last?.capturedAt ?? startedAt), end <= referenceDate,
                  end.timeIntervalSince(startedAt) <= Self.maximumDuration else { throw WorkloadCheckError.invalidArchive }
        }
        switch phase {
        case .baseline:
            guard comparisonStartedAt == nil, endedAt == nil else { throw WorkloadCheckError.invalidArchive }
        case .comparison:
            guard comparisonStartedAt != nil, endedAt == nil, phaseIsSufficient(.baseline) else { throw WorkloadCheckError.invalidArchive }
        case .completed:
            guard endedAt != nil, comparisonStartedAt != nil, phaseIsSufficient(.baseline), phaseIsSufficient(.comparison) else {
                throw WorkloadCheckError.invalidArchive
            }
        case .interrupted:
            guard endedAt != nil else { throw WorkloadCheckError.invalidArchive }
        }
    }

    private func phaseIsSufficient(_ phase: WorkloadCheckPhase) -> Bool {
        let usable = points.filter { $0.phase == phase && $0.hasUsableValue }
        guard usable.count >= Self.minimumPhasePoints,
              let first = usable.first?.usableObservationDates.compactMap({ $0 }).max(),
              let last = usable.last?.usableObservationDates.compactMap({ $0 }).max() else { return false }
        return last.timeIntervalSince(first) >= Self.minimumPhaseDuration
    }

    private func validateTransition(at date: Date) throws {
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed.isFinite, elapsed >= 0, date >= (points.last?.capturedAt ?? startedAt) else {
            throw WorkloadCheckError.invalidTime
        }
        guard elapsed <= Self.maximumDuration else { throw WorkloadCheckError.limitReached }
    }
}
