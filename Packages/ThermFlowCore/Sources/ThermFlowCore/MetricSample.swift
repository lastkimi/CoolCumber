import Foundation

public enum MetricAvailability: String, Codable, CaseIterable, Sendable {
    case available
    case unsupported
    case notPresent
    case permissionRequired
    case temporarilyUnavailable
    case failed
    case unknown
}

public enum MetricSource: String, Codable, CaseIterable, Sendable {
    case smc
    case processInfo
    case machKernel
    case ioKit
    case fileSystem
    case networkInterface
    case systemProfiler
    case powermetrics
    case derived
    case fixture
    case unknown
}

public enum MetricQuality: String, Codable, CaseIterable, Sendable {
    case measured
    case systemReported
    case derived
    case fixture
    case unknown
}

public struct MetricProvenance: Codable, Equatable, Sendable {
    public let source: MetricSource
    public let quality: MetricQuality
    public let collectorID: String?
    public let derivedFrom: [MetricSource]

    public init(
        source: MetricSource,
        quality: MetricQuality,
        collectorID: String? = nil,
        derivedFrom: [MetricSource] = []
    ) {
        self.source = source
        self.quality = quality
        self.collectorID = collectorID
        self.derivedFrom = derivedFrom
    }

    public static func measured(
        by source: MetricSource,
        collectorID: String? = nil
    ) -> MetricProvenance {
        MetricProvenance(
            source: source,
            quality: .measured,
            collectorID: collectorID
        )
    }

    public static func reported(
        by source: MetricSource,
        collectorID: String? = nil
    ) -> MetricProvenance {
        MetricProvenance(
            source: source,
            quality: .systemReported,
            collectorID: collectorID
        )
    }

    public static func derived(
        collectorID: String,
        from sources: [MetricSource]
    ) -> MetricProvenance {
        MetricProvenance(
            source: .derived,
            quality: .derived,
            collectorID: collectorID,
            derivedFrom: sources
        )
    }

    public static let unknown = MetricProvenance(
        source: .unknown,
        quality: .unknown
    )
}

public struct MetricFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String?

    public init(code: String, message: String? = nil) {
        self.code = code
        self.message = message
    }
}

public enum MetricFreshness: String, Codable, Sendable {
    case fresh
    case stale
}

public struct MetricSample<Value>: Codable, Equatable, Sendable
where Value: Codable & Equatable & Sendable {
    public let value: Value?
    public let availability: MetricAvailability
    public let provenance: MetricProvenance
    public let observedAt: Date
    public let failure: MetricFailure?

    private init(
        value: Value?,
        availability: MetricAvailability,
        provenance: MetricProvenance,
        observedAt: Date,
        failure: MetricFailure?
    ) {
        self.value = value
        self.availability = availability
        self.provenance = provenance
        self.observedAt = observedAt
        self.failure = failure
    }

    public static func available(
        _ value: Value,
        provenance: MetricProvenance,
        observedAt: Date
    ) -> MetricSample<Value> {
        MetricSample(
            value: value,
            availability: .available,
            provenance: provenance,
            observedAt: observedAt,
            failure: nil
        )
    }

    public static func unavailable(
        _ availability: MetricAvailability,
        provenance: MetricProvenance = .unknown,
        observedAt: Date,
        failure: MetricFailure? = nil
    ) -> MetricSample<Value> {
        precondition(
            availability != .available,
            "Use MetricSample.available(_:provenance:observedAt:) for available values."
        )
        return MetricSample(
            value: nil,
            availability: availability,
            provenance: provenance,
            observedAt: observedAt,
            failure: failure
        )
    }

    public static func unknown(observedAt: Date) -> MetricSample<Value> {
        .unavailable(.unknown, observedAt: observedAt)
    }

    public static func failed(
        code: String,
        message: String? = nil,
        provenance: MetricProvenance = .unknown,
        observedAt: Date
    ) -> MetricSample<Value> {
        .unavailable(
            .failed,
            provenance: provenance,
            observedAt: observedAt,
            failure: MetricFailure(code: code, message: message)
        )
    }

    public func freshness(
        at referenceDate: Date,
        maximumAge: TimeInterval
    ) -> MetricFreshness {
        guard maximumAge.isFinite, maximumAge >= 0 else { return .stale }
        let age = referenceDate.timeIntervalSince(observedAt)
        guard age.isFinite, age >= 0 else { return .stale }
        return age <= maximumAge ? .fresh : .stale
    }

    public func usableValue(
        at referenceDate: Date,
        maximumAge: TimeInterval
    ) -> Value? {
        guard availability == .available,
              freshness(at: referenceDate, maximumAge: maximumAge) == .fresh else {
            return nil
        }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case value
        case availability
        case provenance
        case observedAt
        case failure
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = try container.decodeIfPresent(Value.self, forKey: .value)
        let availability = try container.decode(MetricAvailability.self, forKey: .availability)
        let provenance = try container.decode(MetricProvenance.self, forKey: .provenance)
        let observedAt = try container.decode(Date.self, forKey: .observedAt)
        let failure = try container.decodeIfPresent(MetricFailure.self, forKey: .failure)

        if availability == .available {
            guard value != nil, failure == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .availability,
                    in: container,
                    debugDescription: "Available samples require a value and cannot contain a failure."
                )
            }
        } else if value != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Unavailable samples cannot contain a value."
            )
        }

        if availability == .failed, failure == nil {
            throw DecodingError.dataCorruptedError(
                forKey: .failure,
                in: container,
                debugDescription: "Failed samples require structured failure details."
            )
        }

        self.init(
            value: value,
            availability: availability,
            provenance: provenance,
            observedAt: observedAt,
            failure: failure
        )
    }
}
