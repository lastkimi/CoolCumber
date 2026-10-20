import Foundation

public enum TrustedThermalPressureRejectionReason: String, Error, Equatable, Sendable {
    case unsupportedSchema
    case capabilityUnavailable
    case sampleUnavailable
    case futureDated
    case stale
    case untrustedProvenance
}

public enum TrustedThermalPressureAlertTrigger: String, Equatable, Sendable {
    case serious
    case critical
}

public struct TrustedThermalPressureAlertEvent: Equatable, Sendable {
    public let trigger: TrustedThermalPressureAlertTrigger
    public let value: ThermalPressure
    public let observedAt: Date
    public let sampleIdentity: String

    public init(
        trigger: TrustedThermalPressureAlertTrigger,
        value: ThermalPressure,
        observedAt: Date,
        sampleIdentity: String
    ) {
        self.trigger = trigger
        self.value = value
        self.observedAt = observedAt
        self.sampleIdentity = sampleIdentity
    }
}

public enum TrustedThermalPressureAssessment: Equatable, Sendable {
    case alert(TrustedThermalPressureAlertEvent)
    case noAlert(value: ThermalPressure)
    case rejected(TrustedThermalPressureRejectionReason)
}

/// Validates the only thermal signal available to the sandboxed Mac App Store
/// build. An alert is possible only from a fresh ProcessInfo system report and
/// an independently fresh capability observation.
public struct TrustedThermalPressurePolicy: Equatable, Sendable {
    public static let defaultMaximumSampleAge: TimeInterval = 15

    public init() {}

    public func assess(
        _ snapshot: SystemSnapshot,
        at evaluationDate: Date,
        maximumSampleAge: TimeInterval = Self.defaultMaximumSampleAge
    ) -> TrustedThermalPressureAssessment {
        guard snapshot.schemaVersion == SystemSnapshot.currentSchemaVersion else {
            return .rejected(.unsupportedSchema)
        }
        guard snapshot.capabilities.allows(
            .thermalPressure,
            at: evaluationDate,
            maximumAge: maximumSampleAge
        ) else {
            return .rejected(.capabilityUnavailable)
        }

        let sample = snapshot.thermal.pressure
        guard sample.availability == .available, let pressure = sample.value else {
            return .rejected(.sampleUnavailable)
        }
        let age = evaluationDate.timeIntervalSince(sample.observedAt)
        guard age.isFinite, age >= 0 else {
            return .rejected(.futureDated)
        }
        guard maximumSampleAge.isFinite,
              maximumSampleAge >= 0,
              age <= maximumSampleAge else {
            return .rejected(.stale)
        }
        guard sample.provenance.quality == .systemReported,
              sample.provenance.source == .processInfo,
              sample.provenance.derivedFrom.isEmpty else {
            return .rejected(.untrustedProvenance)
        }

        let sampleIdentity = "pressure:\(sample.observedAt.timeIntervalSinceReferenceDate.bitPattern):\(pressure.rawValue)"
        switch pressure {
        case .serious:
            return .alert(
                TrustedThermalPressureAlertEvent(
                    trigger: .serious,
                    value: pressure,
                    observedAt: sample.observedAt,
                    sampleIdentity: sampleIdentity
                )
            )
        case .critical:
            return .alert(
                TrustedThermalPressureAlertEvent(
                    trigger: .critical,
                    value: pressure,
                    observedAt: sample.observedAt,
                    sampleIdentity: sampleIdentity
                )
            )
        case .nominal, .fair:
            return .noAlert(value: pressure)
        }
    }
}
