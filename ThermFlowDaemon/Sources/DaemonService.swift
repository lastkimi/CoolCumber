import Foundation
import OSLog

final class DaemonService: NSObject, CoolCumberDaemonProtocol {
    private static let disabledForSecurity = "disabled for security"
    private static let absoluteFanRPMRange = 1_000...8_000

    private let logger = Logger(subsystem: "com.slmcamp.CoolCumber.helper", category: "service")
    private let fanControlLock = NSLock()
    private var didManuallyControlFan = false

    private func log(_ message: String) {
        logger.info("\(message, privacy: .private)")
    }

    func connectionInvalidated() {
        fanControlLock.lock()
        defer { fanControlLock.unlock() }

        guard didManuallyControlFan else { return }
        let restored = resetFansToAutomatic()
        if restored {
            didManuallyControlFan = false
            logger.notice("Restored automatic fan control after XPC invalidation")
        } else {
            logger.fault("Failed to restore automatic fan control after XPC invalidation")
        }
    }
    
    func readTemperatures(reply: @escaping ([String : Double]) -> Void) {
        var temps: [String: Double] = [:]
        let smc = SMCWrapper.shared
        
        // 1. Direct Apple Silicon & Intel SMC Thermal Keys Scan
        let cpuKeys = [
            "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0h", "Tp0j", // P-Cores
            "Te05", "Te0L", "Te0P", "Te0S",                         // E-Cores
            "TC0P", "TC0E", "TC0D", "TC0F", "TC0C"                  // CPU Package/Die
        ]
        var cpuTemps: [Double] = []
        for key in cpuKeys {
            if let t = smc.readTemperature(key: key), t > 15.0 && t < 120.0 {
                cpuTemps.append(t)
            }
        }
        if !cpuTemps.isEmpty {
            let avgCpu = cpuTemps.reduce(0, +) / Double(cpuTemps.count)
            temps["CPU"] = round(avgCpu * 10) / 10
        }
        
        let gpuKeys = ["Tg05", "Tg0D", "Tg0L", "Tg0P", "TG0P", "TG0D"]
        var gpuTemps: [Double] = []
        for key in gpuKeys {
            if let t = smc.readTemperature(key: key), t > 15.0 && t < 120.0 {
                gpuTemps.append(t)
            }
        }
        if !gpuTemps.isEmpty {
            let avgGpu = gpuTemps.reduce(0, +) / Double(gpuTemps.count)
            temps["GPU"] = round(avgGpu * 10) / 10
        }
        
        // 2. Try Powermetrics if SMC keys didn't return values
        if temps["CPU"] == nil {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
            task.arguments = ["-n", "1", "-i", "100", "--samplers", "thermal,smc"]
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                if let output = String(data: data, encoding: .utf8) {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("CPU die temperature:") || line.contains("CPU die temp:") {
                            let valStr = line.components(separatedBy: ":").last?.replacingOccurrences(of: "C", with: "").trimmingCharacters(in: .whitespaces) ?? ""
                            if let val = Double(valStr), val > 10.0 { temps["CPU"] = val }
                        } else if line.contains("GPU die temperature:") || line.contains("GPU die temp:") {
                            let valStr = line.components(separatedBy: ":").last?.replacingOccurrences(of: "C", with: "").trimmingCharacters(in: .whitespaces) ?? ""
                            if let val = Double(valStr), val > 10.0 { temps["GPU"] = val }
                        }
                    }
                }
            } catch {
                log("Powermetrics error: \(error.localizedDescription)")
            }
        }

        reply(temps)
    }
    
    func setFanSpeed(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void) {
        fanControlLock.lock()
        defer { fanControlLock.unlock() }

        let smc = SMCWrapper.shared
        guard let fanCount = smc.readFanCount() else {
            reply(false, "Fan hardware is unavailable")
            return
        }
        guard fanIndex >= 0, fanIndex < fanCount else {
            reply(false, "Invalid fan index")
            return
        }
        guard Self.absoluteFanRPMRange.contains(rpm) else {
            reply(false, "Requested RPM is outside the absolute safety range")
            return
        }

        // Preserve the existing API convention: index 0 targets all fans on a
        // multi-fan Mac, while every other valid index targets one fan.
        let targetFans = (fanIndex == 0 && fanCount > 1) ? Array(0..<fanCount) : [fanIndex]
        for idx in targetFans {
            guard let minimum = smc.readFanSpeed(key: "F\(idx)Mn"),
                  let maximum = smc.readFanSpeed(key: "F\(idx)Mx"),
                  minimum.isFinite,
                  maximum.isFinite,
                  minimum >= 0,
                  maximum > minimum,
                  maximum <= 10_000,
                  Double(rpm) >= minimum,
                  Double(rpm) <= maximum else {
                reply(false, "Requested RPM is outside the fan's reported hardware range")
                return
            }
        }

        var allWritesSucceeded = true
        var madeManualChanges = false
        for idx in targetFans {
            let mdSuccess = smc.writeValue(key: "F\(idx)Md", bytes: [1])
            let tgSuccess = smc.writeFanSpeed(key: "F\(idx)Tg", rpm: Double(rpm))
            let readback = smc.readFanSpeed(key: "F\(idx)Tg")
            let readbackMatches = readback.map { abs($0 - Double(rpm)) <= 25.0 } ?? false
            madeManualChanges = madeManualChanges || mdSuccess || tgSuccess
            allWritesSucceeded = allWritesSucceeded && mdSuccess && tgSuccess && readbackMatches
            log("SetFanSpeed fan=\(idx), mode=\(mdSuccess), target=\(tgSuccess), readback=\(readbackMatches)")
        }

        let mask = targetFans.reduce(UInt16(0)) { partial, idx in
            partial | (UInt16(1) << UInt16(idx))
        }
        let maskBytes: [UInt8] = [UInt8(mask >> 8), UInt8(mask & 0xFF)]
        let maskSuccess = smc.writeValue(key: "FS! ", bytes: maskBytes)
        madeManualChanges = madeManualChanges || maskSuccess
        allWritesSucceeded = allWritesSucceeded && maskSuccess

        if allWritesSucceeded {
            didManuallyControlFan = true
            reply(true, nil)
        } else {
            didManuallyControlFan = madeManualChanges
            let rollbackSucceeded = resetFansToAutomatic()
            if rollbackSucceeded {
                didManuallyControlFan = false
            }
            logger.error("Fan control transaction failed; automatic rollback success=\(rollbackSucceeded, privacy: .public)")
            reply(false, "Failed to apply and verify fan speed")
        }
    }
    
    func resetFanToAutomatic(reply: @escaping (Bool) -> Void) {
        fanControlLock.lock()
        defer { fanControlLock.unlock() }

        let success = resetFansToAutomatic()
        if success {
            didManuallyControlFan = false
        }
        reply(success)
    }
    
    func readFanSpeeds(reply: @escaping ([Int]) -> Void) {
        let smc = SMCWrapper.shared
        guard let fanCount = smc.readFanCount() else {
            reply([])
            return
        }
        var speeds: [Int] = []

        for idx in 0..<fanCount {
            guard let rpm = smc.readFanSpeed(key: "F\(idx)Ac"),
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

    private func resetFansToAutomatic() -> Bool {
        let smc = SMCWrapper.shared
        guard let fanCount = smc.readFanCount() else {
            return false
        }

        var allWritesSucceeded = true
        for idx in 0..<fanCount {
            allWritesSucceeded = smc.writeValue(key: "F\(idx)Md", bytes: [0]) && allWritesSucceeded
        }
        allWritesSucceeded = smc.writeValue(key: "FS! ", bytes: [0, 0]) && allWritesSucceeded
        log("ResetFanToAutomatic fanCount=\(fanCount), success=\(allWritesSucceeded)")
        return allWritesSucceeded
    }
    
    func readThermalPressure(reply: @escaping (String) -> Void) {
        log("readThermalPressure called")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        task.arguments = ["-n", "1", "-i", "100", "--samplers", "smc"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if let output = String(data: data, encoding: .utf8) {
                if let range = output.range(of: "CPU Thermal level: ") {
                    let substring = output[range.upperBound...]
                    if let end = substring.firstIndex(of: "\n") {
                        let level = String(substring[..<end]).trimmingCharacters(in: .whitespaces)
                        reply("Level \(level)")
                        return
                    }
                }
            }
        } catch {
            log("Failed to run powermetrics for thermal pressure: \(error.localizedDescription)")
        }
        
        // Fallback to unified thermal pressure if powermetrics smc isn't complete
        let status = PowermetricsReader.shared.readThermalPressure()
        reply(status)
    }
    
    func readCPUPowerMetrics(reply: @escaping ([String : Any]) -> Void) {
        reply([:])
    }
    
    private func getConsoleUserHome() -> String? {
        var statInfo = stat()
        if stat("/dev/console", &statInfo) == 0 {
            if let pw = getpwuid(statInfo.st_uid) {
                return String(cString: pw.pointee.pw_dir)
            }
        }
        return nil
    }
    
    func listLaunchDaemons(reply: @escaping ([[String : Any]]) -> Void) {
        var results: [[String: Any]] = []
        let fm = FileManager.default
        
        let paths: [(String, String)] = [
            ("/Library/LaunchDaemons", "Daemon"),
            ("/Library/LaunchAgents", "Agent")
        ]
        
        var allPaths = paths
        if let consoleHome = getConsoleUserHome() {
            allPaths.append(("\(consoleHome)/Library/LaunchAgents", "UserAgent"))
        }
        
        for (dirPath, type) in allPaths {
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            for file in files {
                if file.hasSuffix(".plist") {
                    let plistPath = "\(dirPath)/\(file)"
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
                          let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                        continue
                    }
                    
                    let label = dict["Label"] as? String ?? file.replacingOccurrences(of: ".plist", with: "")
                    
                    // Whitelist checks
                    if label.hasPrefix("com.apple.") || label.hasPrefix("com.coolcumber.") {
                        continue
                    }
                    
                    var program = dict["Program"] as? String
                    if program == nil, let args = dict["ProgramArguments"] as? [String], !args.isEmpty {
                        program = args[0]
                    }
                    
                    results.append([
                        "label": label,
                        "path": plistPath,
                        "program": program ?? "",
                        "type": type
                    ])
                }
            }
        }
        reply(results)
    }
    
    func bootoutDaemon(label: String, reply: @escaping (Bool, String?) -> Void) {
        logger.warning("Blocked bootoutDaemon request")
        reply(false, Self.disabledForSecurity)
    }
    
    func disableLaunchAgent(plistPath: String, reply: @escaping (Bool, String?) -> Void) {
        logger.warning("Blocked disableLaunchAgent request")
        reply(false, Self.disabledForSecurity)
    }
    
    func readSMARTData(reply: @escaping ([String : Any]) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPStorageDataType"]
        let pipe = Pipe()
        p.standardOutput = pipe
        
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            var result: [String: Any] = [:]
            
            // Very basic parsing for Free, Capacity, and SMART
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("Capacity:") && result["capacity"] == nil {
                    result["capacity"] = line.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if line.contains("Free:") && result["free"] == nil {
                    result["free"] = line.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if line.contains("S.M.A.R.T. Status:") && result["smartStatus"] == nil {
                    result["smartStatus"] = line.replacingOccurrences(of: "S.M.A.R.T. Status:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            reply(result)
        } catch {
            reply(["error": "Failed to read storage data"])
        }
    }
    
    func readDiskIOStats(reply: @escaping ([String : Double]) -> Void) {
        log("readDiskIOStats called")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/iostat")
        p.arguments = ["-d", "-c", "2", "-w", "1"]
        let pipe = Pipe()
        p.standardOutput = pipe
        
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            log("readDiskIOStats finished, output length: \(output.count)")
            
            var result: [String: Double] = [:]
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if let lastLine = lines.last {
                let values = lastLine.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if values.count >= 3 {
                    // third value is MB/s for disk0
                    if let mbps = Double(values[2]) {
                        result["disk0_mbps"] = mbps
                    }
                }
            }
            reply(result)
        } catch {
            log("readDiskIOStats error: \(error.localizedDescription)")
            reply([:])
        }
    }
    
    func readBatteryHealth(reply: @escaping ([String : Any]) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                var stats: [String: Any] = [:]
                
                // Parse cycle count and maximum capacity (state of health)
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("Cycle Count:") {
                        let parts = trimmed.components(separatedBy: ":")
                        if parts.count > 1, let count = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                            stats["cycleCount"] = count
                        }
                    } else if trimmed.contains("State of Charge:") || trimmed.contains("State of Health:") || trimmed.contains("Maximum Capacity:") {
                        let parts = trimmed.components(separatedBy: ":")
                        if parts.count > 1 {
                            let valStr = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
                            if let cap = Int(valStr) {
                                stats["maxCapacityPercent"] = cap
                            }
                        }
                    } else if trimmed.contains("Condition:") {
                        let parts = trimmed.components(separatedBy: ":")
                        if parts.count > 1 {
                            stats["condition"] = parts[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
                
                reply(stats)
                return
            }
        } catch {
            log("readBatteryHealth error: \(error.localizedDescription)")
        }

        reply([:])
    }
    
    func setBatteryChargeLimit(percent: Int, reply: @escaping (Bool, String?) -> Void) {
        guard (20...100).contains(percent), let limit = UInt8(exactly: percent) else {
            reply(false, "Battery charge limit must be between 20 and 100 percent")
            return
        }

        let smc = SMCWrapper.shared
        // BCLM is typically a 1-byte value (ui8) representing the percentage
        let success = smc.writeValue(key: "BCLM", bytes: [limit])
        log("setBatteryChargeLimit success=\(success)")
        if success {
            reply(true, nil)
        } else {
            reply(false, "Failed to write BCLM to SMC")
        }
    }
    
    func runMaintenance(type: String, reply: @escaping (Bool, String?) -> Void) {
        logger.warning("Blocked runMaintenance request")
        reply(false, Self.disabledForSecurity)
    }
    
    // --- CoolCumber v2.0 Phase 1 Additions ---
    func readNetworkStats(reply: @escaping ([String: Double]) -> Void) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            reply(["upload": 0, "download": 0])
            return
        }
        
        var upload: Double = 0
        var download: Double = 0
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_LINK) {
                if let data = interface?.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    upload += Double(networkData.ifi_obytes)
                    download += Double(networkData.ifi_ibytes)
                }
            }
        }
        freeifaddrs(ifaddr)
        
        // This returns raw total bytes since boot. The App layer will calculate the delta.
        reply(["upload": upload, "download": download])
    }
    
    func readMemoryStats(reply: @escaping ([String: Double]) -> Void) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            reply(["used": 0, "total": 0])
            return
        }
        
        // Page size
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        
        let appMemory = Double(stats.internal_page_count - stats.purgeable_count) * Double(pageSize)
        let wired = Double(stats.wire_count) * Double(pageSize)
        let compressed = Double(stats.compressor_page_count) * Double(pageSize)
        
        // Match Activity Monitor "Used Memory" precisely
        let used = appMemory + wired + compressed
        
        let processInfo = ProcessInfo.processInfo
        let total = Double(processInfo.physicalMemory)
        
        reply(["used": used, "total": total])
    }
    
    func readCPUUsage(reply: @escaping ([String: Double]) -> Void) {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS else {
            reply(["user": 0, "system": 0, "idle": 0])
            return
        }
        
        var user: Double = 0
        var system: Double = 0
        var idle: Double = 0
        var nice: Double = 0
        
        let cpuLoadInfo = cpuInfo.withMemoryRebound(to: integer_t.self, capacity: Int(numCpuInfo)) { $0 }
        
        for i in 0 ..< Int(numCPUs) {
            let index = i * Int(CPU_STATE_MAX)
            user += Double(cpuLoadInfo[index + Int(CPU_STATE_USER)])
            system += Double(cpuLoadInfo[index + Int(CPU_STATE_SYSTEM)])
            idle += Double(cpuLoadInfo[index + Int(CPU_STATE_IDLE)])
            nice += Double(cpuLoadInfo[index + Int(CPU_STATE_NICE)])
        }
        
        let allocSize = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), allocSize)
        
        // Raw ticks returned. App layer will calculate delta for percentage.
        reply(["user": user, "system": system, "idle": idle, "nice": nice])
    }
    
    func readDiskSpace(reply: @escaping ([String: Any]) -> Void) {
        let url = URL(fileURLWithPath: "/")
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            let total = Double(values.volumeTotalCapacity ?? 0)
            let available = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            let used = total - available
            
            reply([
                "total": total,
                "used": used,
                "available": available
            ])
        } catch {
            reply(["total": 0.0, "used": 0.0, "available": 0.0])
        }
    }
    
    func purgeMemory(reply: @escaping (Bool, String?) -> Void) {
        logger.warning("Blocked purgeMemory request")
        reply(false, Self.disabledForSecurity)
    }

    // --- Process Analysis ---
    func readTopProcesses(count: Int, reply: @escaping ([[String: Any]]) -> Void) {
        guard (1...100).contains(count) else {
            logger.warning("Rejected readTopProcesses request with invalid count")
            reply([])
            return
        }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-axo", "pid,pcpu,pmem,comm", "-r"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                reply([])
                return
            }
            
            let lines = output.components(separatedBy: .newlines)
            var processes: [[String: Any]] = []
            
            // Skip header (line 0)
            for i in 1..<min(lines.count, count + 1) {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                
                // Format: PID %CPU %MEM COMM
                // We split by max 3 spaces because COMM might have spaces
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4 {
                    let pid = parts[0]
                    let pcpu = Double(parts[1]) ?? 0.0
                    let pmem = Double(parts[2]) ?? 0.0
                    let comm = parts[3...].joined(separator: " ")
                    let name = (comm as NSString).lastPathComponent
                    
                    processes.append([
                        "pid": pid,
                        "cpu": pcpu,
                        "mem": pmem,
                        "name": name,
                        "path": comm
                    ])
                }
            }
            reply(processes)
        } catch {
            print("Failed to run ps: \(error)")
            reply([])
        }
    }
    
    func readTopMemoryProcesses(count: Int, reply: @escaping ([[String: Any]]) -> Void) {
        guard (1...100).contains(count) else {
            logger.warning("Rejected readTopMemoryProcesses request with invalid count")
            reply([])
            return
        }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-axo", "pid,pcpu,rss,comm", "-m"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                reply([])
                return
            }
            
            let lines = output.components(separatedBy: .newlines)
            var processes: [[String: Any]] = []
            
            // Skip header (line 0)
            for i in 1..<min(lines.count, count + 1) {
                let line = lines[i].trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                
                // Format: PID %CPU RSS COMM
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4 {
                    let pid = parts[0]
                    let pcpu = Double(parts[1]) ?? 0.0
                    let rss = Double(parts[2]) ?? 0.0
                    let memMB = rss / 1024.0
                    let comm = parts[3...].joined(separator: " ")
                    let name = (comm as NSString).lastPathComponent
                    
                    processes.append([
                        "pid": pid,
                        "cpu": pcpu,
                        "mem": memMB,
                        "name": name,
                        "path": comm
                    ])
                }
            }
            reply(processes)
        } catch {
            print("Failed to run ps for memory: \(error)")
            reply([])
        }
    }
    
    func killProcess(pid: Int32, reply: @escaping (Bool, String?) -> Void) {
        logger.warning("Blocked killProcess request")
        reply(false, Self.disabledForSecurity)
    }
    
    func setEcoMode(enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        logger.warning("Blocked setEcoMode request")
        reply(false, Self.disabledForSecurity)
    }
    
    func manageProcessState(pid: Int32, action: String, reply: @escaping (Bool, String?) -> Void) {
        logger.warning("Blocked manageProcessState request")
        reply(false, Self.disabledForSecurity)
    }
}
