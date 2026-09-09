import Foundation

/// Read-only implementation of the complete v2 privileged interface.
///
/// This process runs as root, so its exported surface is intentionally limited
/// to two bounded SMC reads. CPU, memory, network, disk, battery, process and
/// thermal-pressure telemetry belongs in the unprivileged app. The v2 helper
/// contains no XPC selectors for mutation, paths, launchd, processes or shell
/// commands.
final class DaemonService: NSObject, CoolCumberMonitorV2Protocol {
    func connectionInvalidated() {
        // The helper is read-only and retains no per-client mutable state.
    }

    func readTemperatures(reply: @escaping ([String: Double]) -> Void) {
        let smc = SMCWrapper.shared

        func firstValidTemperature(keys: [String]) -> Double? {
            for key in keys {
                if let value = smc.readTemperature(key: key),
                   value.isFinite,
                   value > 15,
                   value < 120 {
                    return (value * 10).rounded() / 10
                }
            }
            return nil
        }

        // Select one real package/die/proximity sensor in stable priority
        // order. Averaging heterogeneous keys would create a derived value
        // that cannot truthfully be presented as a measured temperature.
        let cpuKeys = [
            "TC0D", "TC0P", "TC0E", "TC0F", "TC0C",
            "Tp0T", "Tp09", "Tp01", "Tp05", "Tp0D", "Tp0h", "Tp0j",
            "Te05", "Te0L", "Te0P", "Te0S"
        ]
        let gpuKeys = ["Tg05", "Tg0D", "Tg0L", "Tg0P", "TG0P", "TG0D"]

        var temperatures: [String: Double] = [:]
        if let cpu = firstValidTemperature(keys: cpuKeys) {
            temperatures["CPU"] = cpu
        }
        if let gpu = firstValidTemperature(keys: gpuKeys) {
            temperatures["GPU"] = gpu
        }
        reply(temperatures)
    }

    func readFanSpeeds(reply: @escaping ([Int]) -> Void) {
        let smc = SMCWrapper.shared
        guard let fanCount = smc.readFanCount(), (1...8).contains(fanCount) else {
            reply([])
            return
        }

        var speeds: [Int] = []
        speeds.reserveCapacity(fanCount)
        for index in 0..<fanCount {
            guard let rpm = smc.readFanSpeed(key: "F\(index)Ac"),
                  rpm.isFinite,
                  rpm >= 0,
                  rpm <= 10_000 else {
                reply([])
                return
            }
            speeds.append(Int(rpm.rounded()))
        }
        reply(speeds)
    }
}
