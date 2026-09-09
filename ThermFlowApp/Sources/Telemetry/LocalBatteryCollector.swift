import Foundation
import IOKit
import ThermFlowCore

struct LocalBatteryCollection {
    let snapshot: BatterySnapshot
    let availability: MetricAvailability
    let failureCode: String?
}

/// Reads the local AppleSmartBattery registry entry without spawning a process
/// or requiring the privileged helper. Missing properties remain unavailable;
/// charge percentage is never substituted for maximum capacity.
struct LocalBatteryCollector {
    func collect(at date: Date) -> LocalBatteryCollection {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            return unavailable(
                availability: .notPresent,
                code: "batteryNotPresent",
                at: date
            )
        }
        defer { IOObjectRelease(service) }

        var unmanagedProperties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(
            service,
            &unmanagedProperties,
            kCFAllocatorDefault,
            0
        )
        guard status == KERN_SUCCESS,
              let retainedProperties = unmanagedProperties?.takeRetainedValue(),
              let properties = retainedProperties as NSDictionary as? [String: Any] else {
            return unavailable(
                availability: .temporarilyUnavailable,
                code: "batteryRegistryReadFailed",
                at: date
            )
        }

        let batteryData = properties["BatteryData"] as? [String: Any] ?? [:]
        let reported = MetricProvenance.reported(
            by: .ioKit,
            collectorID: "AppleSmartBattery"
        )

        let cycleSample: MetricSample<UInt32>
        if let cycle = integerValue(properties["CycleCount"]),
           let value = UInt32(exactly: cycle),
           cycle >= 0 {
            cycleSample = .available(
                value,
                provenance: reported,
                observedAt: date
            )
        } else {
            cycleSample = missing(
                code: "cycleCountUnavailable",
                provenance: reported,
                at: date
            )
        }

        let capacitySample: MetricSample<Percent>
        if let stateOfHealth = numericValue(
            batteryData["StateOfHealth"] ?? properties["StateOfHealth"]
        ),
           let capacity = Percent(stateOfHealth) {
            capacitySample = .available(
                capacity,
                provenance: reported,
                observedAt: date
            )
        } else if let maximum = numericValue(
            properties["AppleRawMaxCapacity"]
                ?? properties["NominalChargeCapacity"]
                ?? properties["MaxCapacity"]
        ),
                  let design = numericValue(properties["DesignCapacity"]),
                  maximum >= 0,
                  design > 0,
                  let capacity = Percent(ratio: maximum / design) {
            capacitySample = .available(
                capacity,
                provenance: .derived(
                    collectorID: "BatteryMaximumCapacityRatio",
                    from: [.ioKit]
                ),
                observedAt: date
            )
        } else {
            capacitySample = missing(
                code: "maximumCapacityUnavailable",
                provenance: reported,
                at: date
            )
        }

        let conditionSample: MetricSample<BatteryCondition>
        if let failureStatus = integerValue(properties["PermanentFailureStatus"]),
           failureStatus > 0 {
            conditionSample = .available(
                .serviceRecommended,
                provenance: reported,
                observedAt: date
            )
        } else if let rawCondition = stringValue(
            properties["BatteryHealthCondition"]
                ?? properties["BatteryHealth"]
                ?? batteryData["BatteryHealth"]
        ),
                  let condition = condition(from: rawCondition) {
            conditionSample = .available(
                condition,
                provenance: reported,
                observedAt: date
            )
        } else {
            conditionSample = missing(
                code: "batteryConditionUnavailable",
                provenance: reported,
                at: date
            )
        }

        let snapshot = BatterySnapshot(
            cycleCount: cycleSample,
            maximumCapacity: capacitySample,
            condition: conditionSample
        )
        let hasValue = cycleSample.availability == .available
            || capacitySample.availability == .available
            || conditionSample.availability == .available
        return LocalBatteryCollection(
            snapshot: snapshot,
            availability: hasValue ? .available : .temporarilyUnavailable,
            failureCode: hasValue ? nil : "batteryTelemetryUnavailable"
        )
    }

    private func unavailable(
        availability: MetricAvailability,
        code: String,
        at date: Date
    ) -> LocalBatteryCollection {
        let provenance = MetricProvenance.reported(
            by: .ioKit,
            collectorID: "AppleSmartBattery"
        )
        let failure = MetricFailure(code: code)
        return LocalBatteryCollection(
            snapshot: BatterySnapshot(
                cycleCount: .unavailable(
                    availability,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                maximumCapacity: .unavailable(
                    availability,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                ),
                condition: .unavailable(
                    availability,
                    provenance: provenance,
                    observedAt: date,
                    failure: failure
                )
            ),
            availability: availability,
            failureCode: code
        )
    }

    private func missing<Value>(
        code: String,
        provenance: MetricProvenance,
        at date: Date
    ) -> MetricSample<Value>
    where Value: Codable & Equatable & Sendable {
        .unavailable(
            .temporarilyUnavailable,
            provenance: provenance,
            observedAt: date,
            failure: MetricFailure(code: code)
        )
    }

    private func numericValue(_ rawValue: Any?) -> Double? {
        guard let number = rawValue as? NSNumber else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    private func integerValue(_ rawValue: Any?) -> Int? {
        guard let number = rawValue as? NSNumber else { return nil }
        return Int(exactly: number.int64Value)
    }

    private func stringValue(_ rawValue: Any?) -> String? {
        guard let value = rawValue as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func condition(from rawValue: String) -> BatteryCondition? {
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        if ["good", "normal"].contains(normalized) {
            return .normal
        }
        if normalized.contains("service")
            || normalized.contains("replace")
            || normalized.contains("check")
            || normalized.contains("poor") {
            return .serviceRecommended
        }
        return nil
    }
}
