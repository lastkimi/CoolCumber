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

        switch trustedThermalPressure(
            from: snapshot,
            at: evaluationDate,
            maximumSampleAge: maximumSampleAge
        ) {
        case let .success(reading):
            trustedSignalCount += 1
            pressureValue = reading.value
            switch reading.value {
            case .serious:
                triggers.append(.thermalPressureSerious)
                identityComponents.append(reading.sampleIdentity)
                latestObservationDate = max(latestObservationDate, reading.observedAt)
            case .critical:
                triggers.append(.thermalPressureCritical)
                identityComponents.append(reading.sampleIdentity)
                latestObservationDate = max(latestObservationDate, reading.observedAt)
            case .nominal, .fair:
                break
            }
        case let .failure(reason):
            rejections.append(
                TrustedHealthSignalRejection(signal: .thermalPressure, reason: reason)
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

    private func trustedThermalPressure(
        from snapshot: SystemSnapshot,
        at evaluationDate: Date,
        maximumSampleAge: TimeInterval
    ) -> Result<TrustedReading<ThermalPressure>, TrustedHealthSignalRejectionReason> {
        guard snapshot.capabilities.allows(
            .thermalPressure,
            at: evaluationDate,
            maximumAge: maximumSampleAge
        ) else {
            return .failure(.capabilityUnavailable)
        }

        let sample = snapshot.thermal.pressure
        guard sample.availability == .available, let pressure = sample.value else {
            return .failure(.sampleUnavailable)
        }
        guard let rejection = temporalRejection(
            observedAt: sample.observedAt,
            evaluationDate: evaluationDate,
            maximumSampleAge: maximumSampleAge
        ) else {
            guard sample.provenance.quality == .systemReported,
                  sample.provenance.source == .processInfo,
                  sample.provenance.derivedFrom.isEmpty else {
                return .failure(.untrustedProvenance)
            }
            return .success(
                TrustedReading(
                    value: pressure,
                    observedAt: sample.observedAt,
                    sampleIdentity: "pressure:\(sample.observedAt.timeIntervalSinceReferenceDate.bitPattern):\(pressure.rawValue)"
                )
            )
        }
        return .failure(rejection)
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
