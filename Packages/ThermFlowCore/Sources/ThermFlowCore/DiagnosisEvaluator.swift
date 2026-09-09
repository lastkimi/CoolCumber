import Foundation

public enum DiagnosisStatus: String, Codable, CaseIterable, Sendable {
    case healthy
    case warning
    case critical
    case insufficientData
}

public enum DiagnosisCode: String, Codable, CaseIterable, Sendable {
    case noAlertsInAvailableMetrics
    case insufficientData
    case thermalPressureFair
    case thermalPressureSerious
    case thermalPressureCritical
    case highCPUTemperature
    case criticalCPUTemperature
    case highMemoryUsage
    case highCPUUsage
    case lowDiskSpace
}

public enum RecommendedActionKind: String, Codable, CaseIterable, Sendable {
    case increaseFan
    case inspectProcesses
    case reviewStorage
}

public struct DiagnosticRecommendation: Codable, Equatable, Sendable {
    public let kind: RecommendedActionKind
    public let requiredCapability: CapabilityID
    public let targetFanSpeed: FanRPM?

    public init(
        kind: RecommendedActionKind,
        requiredCapability: CapabilityID,
        targetFanSpeed: FanRPM? = nil
    ) {
        self.kind = kind
        self.requiredCapability = requiredCapability
        self.targetFanSpeed = targetFanSpeed
    }
}

public struct Diagnosis: Codable, Equatable, Sendable {
    public let status: DiagnosisStatus
    public let code: DiagnosisCode
    public let recommendation: DiagnosticRecommendation?
    public let blockedCapability: CapabilityID?
    public let evaluatedMetricCount: Int
    public let evaluatedAt: Date

    public init(
        status: DiagnosisStatus,
        code: DiagnosisCode,
        recommendation: DiagnosticRecommendation?,
        blockedCapability: CapabilityID?,
        evaluatedMetricCount: Int,
        evaluatedAt: Date
    ) {
        self.status = status
        self.code = code
        self.recommendation = recommendation
        self.blockedCapability = blockedCapability
        self.evaluatedMetricCount = evaluatedMetricCount
        self.evaluatedAt = evaluatedAt
    }
}

public struct DiagnosticThresholds: Codable, Equatable, Sendable {
    public let highCPUTemperature: TemperatureCelsius
    public let criticalCPUTemperature: TemperatureCelsius
    public let highMemoryUsage: Percent
    public let highCPUUsage: Percent
    public let lowDiskAvailable: ByteCount
    public let maximumMetricAge: DurationSeconds

    public init(
        highCPUTemperature: TemperatureCelsius,
        criticalCPUTemperature: TemperatureCelsius,
        highMemoryUsage: Percent,
        highCPUUsage: Percent,
        lowDiskAvailable: ByteCount,
        maximumMetricAge: DurationSeconds
    ) {
        precondition(
            criticalCPUTemperature.value >= highCPUTemperature.value,
            "Critical temperature must be at least the high-temperature threshold."
        )
        self.highCPUTemperature = highCPUTemperature
        self.criticalCPUTemperature = criticalCPUTemperature
        self.highMemoryUsage = highMemoryUsage
        self.highCPUUsage = highCPUUsage
        self.lowDiskAvailable = lowDiskAvailable
        self.maximumMetricAge = maximumMetricAge
    }

    public static let `default` = DiagnosticThresholds(
        highCPUTemperature: TemperatureCelsius(85)!,
        criticalCPUTemperature: TemperatureCelsius(95)!,
        highMemoryUsage: Percent(90)!,
        highCPUUsage: Percent(95)!,
        lowDiskAvailable: ByteCount(15 * 1_073_741_824),
        maximumMetricAge: DurationSeconds(15)!
    )
}

public struct DiagnosisEvaluator: Sendable {
    public let thresholds: DiagnosticThresholds

    public init(thresholds: DiagnosticThresholds = .default) {
        self.thresholds = thresholds
    }

    public func evaluate(
        _ snapshot: SystemSnapshot,
        at evaluationDate: Date
    ) -> Diagnosis {
        let maximumAge = thresholds.maximumMetricAge.value
        let pressure = snapshot.thermal.pressure.usableValue(
            at: evaluationDate,
            maximumAge: maximumAge
        )
        let cpuTemperature = snapshot.thermal.cpuTemperature.usableValue(
            at: evaluationDate,
            maximumAge: maximumAge
        )
        let cpuUsage = snapshot.cpu.usage.usableValue(
            at: evaluationDate,
            maximumAge: maximumAge
        )
        let memoryUsage = snapshot.memory.usage.usableValue(
            at: evaluationDate,
            maximumAge: maximumAge
        )
        let diskAvailable = snapshot.storage.available.usableValue(
            at: evaluationDate,
            maximumAge: maximumAge
        )

        let evaluatedMetricCount = [
            pressure != nil,
            cpuTemperature != nil,
            cpuUsage != nil,
            memoryUsage != nil,
            diskAvailable != nil
        ].filter { $0 }.count

        guard evaluatedMetricCount > 0 else {
            return Diagnosis(
                status: .insufficientData,
                code: .insufficientData,
                recommendation: nil,
                blockedCapability: nil,
                evaluatedMetricCount: 0,
                evaluatedAt: evaluationDate
            )
        }

        if pressure == .critical {
            return controlledCoolingDiagnosis(
                status: .critical,
                code: .thermalPressureCritical,
                targetFanSpeed: 4_500,
                capabilities: snapshot.capabilities,
                metricCount: evaluatedMetricCount,
                evaluatedAt: evaluationDate
            )
        }

        if let cpuTemperature,
           cpuTemperature.value >= thresholds.criticalCPUTemperature.value {
            return controlledCoolingDiagnosis(
                status: .critical,
                code: .criticalCPUTemperature,
                targetFanSpeed: 4_500,
                capabilities: snapshot.capabilities,
                metricCount: evaluatedMetricCount,
                evaluatedAt: evaluationDate
            )
        }

        if pressure == .serious {
            return controlledCoolingDiagnosis(
                status: .warning,
                code: .thermalPressureSerious,
                targetFanSpeed: 3_500,
                capabilities: snapshot.capabilities,
                metricCount: evaluatedMetricCount,
                evaluatedAt: evaluationDate
            )
        }

        if let cpuTemperature,
           cpuTemperature.value >= thresholds.highCPUTemperature.value {
            return controlledCoolingDiagnosis(
                status: .warning,
                code: .highCPUTemperature,
                targetFanSpeed: 3_500,
                capabilities: snapshot.capabilities,
                metricCount: evaluatedMetricCount,
                evaluatedAt: evaluationDate
            )
        }

        if let memoryUsage,
           memoryUsage.value >= thresholds.highMemoryUsage.value {
            return capabilityGatedDiagnosis(
                status: .warning,
                code: .highMemoryUsage,
                action: .inspectProcesses,
                requiredCapability: .processRead,
                targetFanSpeed: nil,
                capabilities: snapshot.capabilities,
                metricCount: evaluatedMetricCount,
                evaluatedAt: evaluationDate
            )
        }

        if let cpuUsage,
           cpuUsage.value >= thresholds.highCPUUsage.value {
            return capabilityGatedDiagnosis(
                status: .warning,
                code: .highCPUUsage,
                action: .inspectProcesses,
                requiredCapability: .processRead,
                targetFanSpeed: nil,
                capabilities: snapshot.capabilities,
                metricCount: evaluatedMetricCount,
                evaluatedAt: evaluationDate
            )
        }

        if let diskAvailable,
           diskAvailable.value < thresholds.lowDiskAvailable.value {
            return capabilityGatedDiagnosis(
                status: .warning,
                code: .lowDiskSpace,
                action: .reviewStorage,
                requiredCapability: .diskSpace,
                targetFanSpeed: nil,
                capabilities: snapshot.capabilities,
                metricCount: evaluatedMetricCount,
                evaluatedAt: evaluationDate
            )
        }

        if pressure == .fair {
            return Diagnosis(
                status: .warning,
                code: .thermalPressureFair,
                recommendation: nil,
                blockedCapability: nil,
                evaluatedMetricCount: evaluatedMetricCount,
                evaluatedAt: evaluationDate
            )
        }

        return Diagnosis(
            status: .healthy,
            code: .noAlertsInAvailableMetrics,
            recommendation: nil,
            blockedCapability: nil,
            evaluatedMetricCount: evaluatedMetricCount,
            evaluatedAt: evaluationDate
        )
    }

    private func controlledCoolingDiagnosis(
        status: DiagnosisStatus,
        code: DiagnosisCode,
        targetFanSpeed: Int,
        capabilities: CapabilitySet,
        metricCount: Int,
        evaluatedAt: Date
    ) -> Diagnosis {
        capabilityGatedDiagnosis(
            status: status,
            code: code,
            action: .increaseFan,
            requiredCapability: .fanControl,
            targetFanSpeed: FanRPM(targetFanSpeed),
            capabilities: capabilities,
            metricCount: metricCount,
            evaluatedAt: evaluatedAt
        )
    }

    private func capabilityGatedDiagnosis(
        status: DiagnosisStatus,
        code: DiagnosisCode,
        action: RecommendedActionKind,
        requiredCapability: CapabilityID,
        targetFanSpeed: FanRPM?,
        capabilities: CapabilitySet,
        metricCount: Int,
        evaluatedAt: Date
    ) -> Diagnosis {
        let isAllowed = capabilities.allows(
            requiredCapability,
            at: evaluatedAt,
            maximumAge: thresholds.maximumMetricAge.value
        )
        let recommendation = isAllowed
            ? DiagnosticRecommendation(
                kind: action,
                requiredCapability: requiredCapability,
                targetFanSpeed: targetFanSpeed
            )
            : nil
        return Diagnosis(
            status: status,
            code: code,
            recommendation: recommendation,
            blockedCapability: isAllowed ? nil : requiredCapability,
            evaluatedMetricCount: metricCount,
            evaluatedAt: evaluatedAt
        )
    }
}
