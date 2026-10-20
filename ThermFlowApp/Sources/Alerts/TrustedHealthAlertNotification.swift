import Foundation

struct TrustedHealthAlertNotificationPayload: Equatable, Sendable {
    let title: String
    let body: String
}

/// Pure presentation mapping for a trusted alert event. Keeping the serious
/// and critical branches outside UserNotifications makes the exact Mac App
/// Store message independently testable.
struct TrustedHealthAlertNotificationBuilder: Equatable, Sendable {
    func payload(
        for event: TrustedHealthAlertEvent,
        isChinese: Bool
    ) -> TrustedHealthAlertNotificationPayload {
        if event.triggers.contains(.thermalPressureCritical) {
            return TrustedHealthAlertNotificationPayload(
                title: isChinese ? "严重热压力" : "Critical thermal pressure",
                body: combinedBody(
                    pressureText: isChinese
                        ? "macOS 报告当前热压力为危急。"
                        : "macOS reports critical thermal pressure.",
                    event: event,
                    isChinese: isChinese
                )
            )
        }
        if event.triggers.contains(.thermalPressureSerious) {
            return TrustedHealthAlertNotificationPayload(
                title: isChinese ? "热压力较高" : "High thermal pressure",
                body: combinedBody(
                    pressureText: isChinese
                        ? "macOS 报告当前热压力较高。"
                        : "macOS reports serious thermal pressure.",
                    event: event,
                    isChinese: isChinese
                )
            )
        }
        return TrustedHealthAlertNotificationPayload(
            title: isChinese ? "CPU 温度较高" : "High CPU temperature",
            body: temperatureBody(for: event, isChinese: isChinese)
        )
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
}
