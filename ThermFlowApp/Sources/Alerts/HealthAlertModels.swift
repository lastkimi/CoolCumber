import Foundation
import ThermFlowCore

enum HealthAlertConfigurationError: Error, Equatable, Sendable {
    case temperatureThresholdOutsideAllowedRange
    case cooldownOutsideAllowedRange
}

struct HealthAlertConfiguration: Equatable, Sendable {
    static let minimumTemperatureThresholdCelsius = 60.0
    static let maximumTemperatureThresholdCelsius = 100.0
    static let minimumCooldown: TimeInterval = 15 * 60
    static let maximumCooldown: TimeInterval = 24 * 60 * 60
    static let defaultTemperatureThresholdCelsius = 85.0
    static let `default` = HealthAlertConfiguration(
        validatedIsEnabled: false,
        temperatureThresholdCelsius: defaultTemperatureThresholdCelsius,
        cooldown: minimumCooldown
    )

    let isEnabled: Bool
    let temperatureThresholdCelsius: Double
    let cooldown: TimeInterval

    init(
        isEnabled: Bool = false,
        temperatureThresholdCelsius: Double = Self.defaultTemperatureThresholdCelsius,
        cooldown: TimeInterval = Self.minimumCooldown
    ) throws {
        let allowedTemperatureRange = (
            Self.minimumTemperatureThresholdCelsius...Self.maximumTemperatureThresholdCelsius
        )
        guard temperatureThresholdCelsius.isFinite,
              allowedTemperatureRange.contains(temperatureThresholdCelsius) else {
            throw HealthAlertConfigurationError.temperatureThresholdOutsideAllowedRange
        }
        guard cooldown.isFinite,
              (Self.minimumCooldown...Self.maximumCooldown).contains(cooldown) else {
            throw HealthAlertConfigurationError.cooldownOutsideAllowedRange
        }

        self.init(
            validatedIsEnabled: isEnabled,
            temperatureThresholdCelsius: temperatureThresholdCelsius,
            cooldown: cooldown
        )
    }

    private init(
        validatedIsEnabled: Bool,
        temperatureThresholdCelsius: Double,
        cooldown: TimeInterval
    ) {
        isEnabled = validatedIsEnabled
        self.temperatureThresholdCelsius = temperatureThresholdCelsius
        self.cooldown = cooldown
    }
}

enum HealthAlertAuthorizationState: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case unavailable
}

enum HealthAlertEnablementResult: Equatable, Sendable {
    case enabled
    case disabled
    case denied
    case failed
}

enum HealthAlertSignal: String, Equatable, Sendable {
    case thermalPressure
    case cpuTemperature
}

enum TrustedHealthSignalRejectionReason: String, Error, Equatable, Sendable {
    case unsupportedSchema
    case capabilityUnavailable
    case sampleUnavailable
    case futureDated
    case stale
    case untrustedProvenance
    case implausibleValue
}

struct TrustedHealthSignalRejection: Equatable, Sendable {
    let signal: HealthAlertSignal
    let reason: TrustedHealthSignalRejectionReason
}

enum TrustedHealthAlertTrigger: String, Equatable, Sendable {
    case thermalPressureSerious
    case thermalPressureCritical
    case cpuTemperature
}

struct TrustedHealthAlertEvent: Equatable, Sendable {
    let triggers: [TrustedHealthAlertTrigger]
    let thermalPressure: ThermalPressure?
    let cpuTemperatureCelsius: Double?
    let temperatureThresholdCelsius: Double
    let observedAt: Date
    let sampleIdentity: String
}

enum TrustedHealthPolicyAssessment: Equatable, Sendable {
    case alert(TrustedHealthAlertEvent)
    case noAlert(rejectedSignals: [TrustedHealthSignalRejection])
    case rejected([TrustedHealthSignalRejection])
}

/// Produces an alert event only from fresh, typed, non-derived observations.
/// Thermal pressure is available in both channels; CPU temperature is evaluated
/// only for Direct, where trusted measured temperature collection is supported.
struct TrustedHealthAlertPolicy: Sendable {
    static let maximumSampleAge: TimeInterval = 15
    static let plausibleTemperatureRange = 10.0...120.0

    func assess(
        _ snapshot: SystemSnapshot,
        temperatureThresholdCelsius: Double,
        at evaluationDate: Date,
        maximumSampleAge: TimeInterval = Self.maximumSampleAge
    ) -> TrustedHealthPolicyAssessment {
        guard snapshot.schemaVersion == SystemSnapshot.currentSchemaVersion else {
            return .rejected([
                TrustedHealthSignalRejection(
                    signal: .thermalPressure,
                    reason: .unsupportedSchema
                )
            ])
        }

        var triggers: [TrustedHealthAlertTrigger] = []
        var rejections: [TrustedHealthSignalRejection] = []
        var trustedSignalCount = 0
        var pressureValue: ThermalPressure?
        var temperatureValue: Double?
        var identityComponents: [String] = []
        var latestObservationDate = Date.distantPast

        switch TrustedThermalPressurePolicy().assess(
            snapshot,
            at: evaluationDate,
            maximumSampleAge: maximumSampleAge
        ) {
        case let .alert(event):
            trustedSignalCount += 1
            pressureValue = event.value
            switch event.trigger {
            case .serious:
                triggers.append(.thermalPressureSerious)
            case .critical:
                triggers.append(.thermalPressureCritical)
            }
            identityComponents.append(event.sampleIdentity)
            latestObservationDate = max(latestObservationDate, event.observedAt)
        case let .noAlert(value):
            trustedSignalCount += 1
            pressureValue = value
        case let .rejected(reason):
            rejections.append(
                TrustedHealthSignalRejection(
                    signal: .thermalPressure,
                    reason: healthRejectionReason(for: reason)
                )
            )
        }

        if snapshot.channel == .direct {
            switch trustedCPUTemperature(
                from: snapshot,
                at: evaluationDate,
                maximumSampleAge: maximumSampleAge
            ) {
            case let .success(reading):
                trustedSignalCount += 1
                temperatureValue = reading.value
                if reading.value >= temperatureThresholdCelsius {
                    triggers.append(.cpuTemperature)
                    identityComponents.append(reading.sampleIdentity)
                    latestObservationDate = max(latestObservationDate, reading.observedAt)
                }
            case let .failure(reason):
                rejections.append(
                    TrustedHealthSignalRejection(signal: .cpuTemperature, reason: reason)
                )
            }
        }

        guard !triggers.isEmpty else {
            return trustedSignalCount > 0
                ? .noAlert(rejectedSignals: rejections)
                : .rejected(rejections)
        }

        return .alert(
            TrustedHealthAlertEvent(
                triggers: triggers,
                thermalPressure: pressureValue,
                cpuTemperatureCelsius: temperatureValue,
                temperatureThresholdCelsius: temperatureThresholdCelsius,
                observedAt: latestObservationDate,
                sampleIdentity: identityComponents.joined(separator: "|")
            )
        )
    }

    private func healthRejectionReason(
        for reason: TrustedThermalPressureRejectionReason
    ) -> TrustedHealthSignalRejectionReason {
        switch reason {
        case .unsupportedSchema: return .unsupportedSchema
        case .capabilityUnavailable: return .capabilityUnavailable
        case .sampleUnavailable: return .sampleUnavailable
        case .futureDated: return .futureDated
        case .stale: return .stale
        case .untrustedProvenance: return .untrustedProvenance
        }
    }

    private func trustedCPUTemperature(
        from snapshot: SystemSnapshot,
        at evaluationDate: Date,
        maximumSampleAge: TimeInterval
    ) -> Result<TrustedReading<Double>, TrustedHealthSignalRejectionReason> {
        guard snapshot.capabilities.allows(
            .cpuTemperature,
            at: evaluationDate,
            maximumAge: maximumSampleAge
        ) else {
            return .failure(.capabilityUnavailable)
        }

        let sample = snapshot.thermal.cpuTemperature
        guard sample.availability == .available, let temperature = sample.value else {
            return .failure(.sampleUnavailable)
        }
        if let rejection = temporalRejection(
            observedAt: sample.observedAt,
            evaluationDate: evaluationDate,
            maximumSampleAge: maximumSampleAge
        ) {
            return .failure(rejection)
        }
        guard sample.provenance.quality == .measured,
              isTrustedMeasuredTemperatureSource(sample.provenance) else {
            return .failure(.untrustedProvenance)
        }
        guard Self.plausibleTemperatureRange.contains(temperature.value) else {
            return .failure(.implausibleValue)
        }

        return .success(
            TrustedReading(
                value: temperature.value,
                observedAt: sample.observedAt,
                sampleIdentity: "temperature:\(sample.observedAt.timeIntervalSinceReferenceDate.bitPattern):\(temperature.value.bitPattern)"
            )
        )
    }

    private func temporalRejection(
        observedAt: Date,
        evaluationDate: Date,
        maximumSampleAge: TimeInterval
    ) -> TrustedHealthSignalRejectionReason? {
        let age = evaluationDate.timeIntervalSince(observedAt)
        guard age >= 0 else { return .futureDated }
        guard maximumSampleAge.isFinite,
              maximumSampleAge >= 0,
              age <= maximumSampleAge else {
            return .stale
        }
        return nil
    }

    private func isTrustedMeasuredTemperatureSource(
        _ provenance: MetricProvenance
    ) -> Bool {
        if isDirectTemperatureSource(provenance.source) {
            return true
        }

        // The helper currently represents its SMC/powermetrics fan-in with an
        // unknown direct source but enumerates the concrete measured collectors.
        guard provenance.source == .unknown,
              !provenance.derivedFrom.isEmpty else {
            return false
        }
        return provenance.derivedFrom.allSatisfy(isDirectTemperatureSource)
    }

    private func isDirectTemperatureSource(_ source: MetricSource) -> Bool {
        switch source {
        case .smc, .ioKit, .systemProfiler, .powermetrics:
            return true
        case .processInfo, .machKernel, .fileSystem, .networkInterface,
             .derived, .fixture, .unknown:
            return false
        }
    }
}

private struct TrustedReading<Value>: Sendable
where Value: Equatable & Sendable {
    let value: Value
    let observedAt: Date
    let sampleIdentity: String
}

enum HealthAlertEvaluation: Equatable, Sendable {
    case disabled
    case noAlert(rejectedSignals: [TrustedHealthSignalRejection])
    case rejected([TrustedHealthSignalRejection])
    case duplicateSample
    case deliveryInProgress
    case coolingDown(until: Date)
    case notificationPermissionUnavailable
    case scheduled(TrustedHealthAlertEvent)
    case deliveryFailed
}
