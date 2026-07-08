import Foundation

class PowermetricsReader {
    static let shared = PowermetricsReader()
    
    /// Reads the current thermal pressure from `powermetrics`.
    /// E.g., Nominal, Fair, Serious, Critical
    func readThermalPressure() -> String {
        let task = Process()
        task.launchPath = "/usr/bin/pmset" // using pmset -g therm is much faster and simpler than powermetrics for thermal pressure
        task.arguments = ["-g", "therm"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Example output:
                // Note: No thermal warning level has been recorded
                // CPU_Speed_Limit      = 100
                if output.contains("CPU_Speed_Limit") {
                    let lines = output.components(separatedBy: "\n")
                    for line in lines {
                        if line.contains("CPU_Speed_Limit") {
                            // Extract the number
                            let parts = line.components(separatedBy: "=")
                            if parts.count > 1 {
                                let val = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                                if let speed = Int(val), speed < 100 {
                                    return "Throttled (\(speed)%)"
                                }
                            }
                        }
                    }
                    return "Nominal (100%)"
                }
                return "Nominal"
            }
        } catch {
            print("Failed to run pmset: \(error)")
        }
        
        return "Unknown"
    }
}
