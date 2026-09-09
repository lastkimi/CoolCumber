import Foundation
import ThermFlowCore
import UserNotifications

actor TrustedHealthAlertController {
    static let shared = TrustedHealthAlertController()

    private enum DefaultsKey {
        static let enabled = "com.slmcamp.CoolCumber.healthAlerts.v1.enabled"
        static let temperatureThreshold =
            "com.slmcamp.CoolCumber.healthAlerts.v1.temperatureThresholdCelsius"
        static let cooldown = "com.slmcamp.CoolCumber.healthAlerts.v1.cooldownSeconds"
        static let lastSampleIdentity =
            "com.slmcamp.CoolCumber.healthAlerts.v1.lastSampleIdentity"
        static let lastNotificationDate =
            "com.slmcamp.CoolCumber.healthAlerts.v1.lastNotificationDate"
    }

    private static let notificationThreadIdentifier =
        "com.slmcamp.CoolCumber.healthAlerts"

    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let policy: TrustedHealthAlertPolicy
    private var configuration: HealthAlertConfiguration
    private var deliveryInProgress = false

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        policy: TrustedHealthAlertPolicy = TrustedHealthAlertPolicy()
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.policy = policy
        configuration = Self.loadConfiguration(from: defaults)
    }

    func currentConfiguration() -> HealthAlertConfiguration {
        configuration
    }

    /// The only API that can request notification authorization. Call it only
    /// in response to an explicit user action. Evaluation never prompts.
    func setEnabled(_ enabled: Bool) async -> HealthAlertEnablementResult {
        guard enabled else {
            persist(
                configuration: makeConfiguration(
                    enabled: false,
                    temperatureThreshold: configuration.temperatureThresholdCelsius,
                    cooldown: configuration.cooldown
                )
            )
            defaults.removeObject(forKey: DefaultsKey.lastSampleIdentity)
            return .disabled
        }

        let status = await notificationCenter.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            persistEnabled()
            return .enabled
        case .denied:
            persistDisabled()
            return .denied
        case .notDetermined:
            do {
                let granted = try await notificationCenter.requestAuthorization(
                    options: [.alert, .sound]
                )
                guard granted else {
                    persistDisabled()
                    return .denied
                }
                persistEnabled()
                return .enabled
            } catch {
                persistDisabled()
                return .failed
            }
        @unknown default:
            persistDisabled()
            return .failed
        }
    }

    func authorizationState() async -> HealthAlertAuthorizationState {
        let status = await notificationCenter.notificationSettings().authorizationStatus
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unavailable
        }
    }

    @discardableResult
    func setTemperatureThreshold(
        _ thresholdCelsius: Double
    ) throws -> HealthAlertConfiguration {
        let updated = try HealthAlertConfiguration(
            isEnabled: configuration.isEnabled,
            temperatureThresholdCelsius: thresholdCelsius,
            cooldown: configuration.cooldown
        )
        persist(configuration: updated)
        return updated
    }

    @discardableResult
    func setCooldown(_ cooldown: TimeInterval) throws -> HealthAlertConfiguration {
        let updated = try HealthAlertConfiguration(
            isEnabled: configuration.isEnabled,
            temperatureThresholdCelsius: configuration.temperatureThresholdCelsius,
            cooldown: cooldown
        )
        persist(configuration: updated)
        return updated
    }

    /// Evaluates trusted snapshot data and may schedule one immediate local
    /// notification. Direct temperature and cross-channel thermal pressure are
    /// merged into a single event and share one persisted cooldown.
    func evaluate(
        _ snapshot: SystemSnapshot,
        at evaluationDate: Date = Date()
    ) async -> HealthAlertEvaluation {
        guard configuration.isEnabled else {
            return .disabled
        }

        let assessment = policy.assess(
            snapshot,
            temperatureThresholdCelsius: configuration.temperatureThresholdCelsius,
            at: evaluationDate
        )
        let event: TrustedHealthAlertEvent
        switch assessment {
        case let .noAlert(rejections):
            return .noAlert(rejectedSignals: rejections)
        case let .rejected(rejections):
            return .rejected(rejections)
        case let .alert(trustedEvent):
            event = trustedEvent
        }

        if defaults.string(forKey: DefaultsKey.lastSampleIdentity) == event.sampleIdentity {
            return .duplicateSample
        }

        if let lastNotificationDate = defaults.object(
            forKey: DefaultsKey.lastNotificationDate
        ) as? Date {
            let nextAllowedDate = lastNotificationDate.addingTimeInterval(
                configuration.cooldown
            )
            if evaluationDate < nextAllowedDate {
                defaults.set(event.sampleIdentity, forKey: DefaultsKey.lastSampleIdentity)
                return .coolingDown(until: nextAllowedDate)
            }
        }

        guard !deliveryInProgress else {
            return .deliveryInProgress
        }
        deliveryInProgress = true
        defer { deliveryInProgress = false }

        let authorization = await authorizationState()
        guard authorization == .authorized else {
            defaults.set(event.sampleIdentity, forKey: DefaultsKey.lastSampleIdentity)
            return .notificationPermissionUnavailable
        }
        guard configuration.isEnabled else {
            return .disabled
        }

        // Re-evaluate after the authorization await so a threshold change made
        // during actor re-entry cannot emit an obsolete temperature alert.
        let currentAssessment = policy.assess(
            snapshot,
            temperatureThresholdCelsius: configuration.temperatureThresholdCelsius,
            at: evaluationDate
        )
        let currentEvent: TrustedHealthAlertEvent
        switch currentAssessment {
        case let .alert(trustedEvent):
            currentEvent = trustedEvent
        case let .noAlert(rejections):
            return .noAlert(rejectedSignals: rejections)
        case let .rejected(rejections):
            return .rejected(rejections)
        }

        let content = notificationContent(for: currentEvent)
        let identifier = "\(Self.notificationThreadIdentifier).\(currentEvent.sampleIdentity)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
            guard configuration.isEnabled else {
                notificationCenter.removePendingNotificationRequests(
                    withIdentifiers: [identifier]
                )
                return .disabled
            }
            defaults.set(currentEvent.sampleIdentity, forKey: DefaultsKey.lastSampleIdentity)
            defaults.set(evaluationDate, forKey: DefaultsKey.lastNotificationDate)
            return .scheduled(currentEvent)
        } catch {
            return .deliveryFailed
        }
    }

    private func notificationContent(
        for event: TrustedHealthAlertEvent
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        if event.triggers.contains(.thermalPressureCritical) {
            content.title = isChinese ? "严重热压力" : "Critical thermal pressure"
            content.body = combinedBody(
                pressureText: isChinese
                    ? "macOS 报告当前热压力为危急。"
                    : "macOS reports critical thermal pressure.",
                event: event,
                isChinese: isChinese
            )
        } else if event.triggers.contains(.thermalPressureSerious) {
            content.title = isChinese ? "热压力较高" : "High thermal pressure"
            content.body = combinedBody(
                pressureText: isChinese
                    ? "macOS 报告当前热压力较高。"
                    : "macOS reports serious thermal pressure.",
                event: event,
                isChinese: isChinese
            )
        } else {
            content.title = isChinese ? "CPU 温度较高" : "High CPU temperature"
            content.body = temperatureBody(for: event, isChinese: isChinese)
        }

        content.sound = .default
        content.threadIdentifier = Self.notificationThreadIdentifier
        var userInfo: [String: Any] = [
            "triggers": event.triggers.map(\.rawValue),
            "observedAt": event.observedAt.timeIntervalSince1970
        ]
        if let pressure = event.thermalPressure {
            userInfo["thermalPressure"] = pressure.rawValue
        }
        if let temperature = event.cpuTemperatureCelsius {
            userInfo["cpuTemperatureCelsius"] = temperature
            userInfo["temperatureThresholdCelsius"] = event.temperatureThresholdCelsius
        }
        content.userInfo = userInfo
        return content
    }

    private func combinedBody(
        pressureText: String,
        event: TrustedHealthAlertEvent,
        isChinese: Bool
    ) -> String {
        guard event.triggers.contains(.cpuTemperature) else {
            return pressureText
        }
        return "\(pressureText) \(temperatureBody(for: event, isChinese: isChinese))"
    }

    private func temperatureBody(
        for event: TrustedHealthAlertEvent,
        isChinese: Bool
    ) -> String {
        guard let temperature = event.cpuTemperatureCelsius else {
            return isChinese
                ? "可信温度读数已超过你的阈值。"
                : "A trusted temperature reading exceeded your threshold."
        }
        return String(
            format: isChinese
                ? "CPU 温度为 %.0f°C，已超过 %.0f°C 阈值。"
                : "CPU temperature is %.0f°C, above your %.0f°C threshold.",
            locale: Locale(identifier: isChinese ? "zh_CN" : "en_US_POSIX"),
            temperature,
            event.temperatureThresholdCelsius
        )
    }

    private static func loadConfiguration(
        from defaults: UserDefaults
    ) -> HealthAlertConfiguration {
        let enabled = defaults.object(forKey: DefaultsKey.enabled) as? Bool ?? false
        let threshold = defaults.object(forKey: DefaultsKey.temperatureThreshold) as? Double
            ?? HealthAlertConfiguration.defaultTemperatureThresholdCelsius
        let cooldown = defaults.object(forKey: DefaultsKey.cooldown) as? Double
            ?? HealthAlertConfiguration.minimumCooldown

        return (try? HealthAlertConfiguration(
            isEnabled: enabled,
            temperatureThresholdCelsius: threshold,
            cooldown: cooldown
        )) ?? .default
    }

    private func makeConfiguration(
        enabled: Bool,
        temperatureThreshold: Double,
        cooldown: TimeInterval
    ) -> HealthAlertConfiguration {
        (try? HealthAlertConfiguration(
            isEnabled: enabled,
            temperatureThresholdCelsius: temperatureThreshold,
            cooldown: cooldown
        )) ?? .default
    }

    private func persistEnabled() {
        persist(
            configuration: makeConfiguration(
                enabled: true,
                temperatureThreshold: configuration.temperatureThresholdCelsius,
                cooldown: configuration.cooldown
            )
        )
    }

    private func persistDisabled() {
        persist(
            configuration: makeConfiguration(
                enabled: false,
                temperatureThreshold: configuration.temperatureThresholdCelsius,
                cooldown: configuration.cooldown
            )
        )
    }

    private func persist(configuration: HealthAlertConfiguration) {
        self.configuration = configuration
        defaults.set(configuration.isEnabled, forKey: DefaultsKey.enabled)
        defaults.set(
            configuration.temperatureThresholdCelsius,
            forKey: DefaultsKey.temperatureThreshold
        )
        defaults.set(configuration.cooldown, forKey: DefaultsKey.cooldown)
    }
}
