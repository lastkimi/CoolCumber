import Foundation
import ServiceManagement

class DaemonManager: ObservableObject {
    static let shared = DaemonManager()
    
    @Published var daemonStatus: String = "Not Installed"
    @Published var thermalStatus: String = "Unknown"
    @Published var fanSpeed: String = "1800 RPM"
    @Published var temperatures: [String: Double] = [:]
    @Published var smartData: [String: Any] = [:]
    @Published var diskIO: [String: Double] = [:]
    
    // --- CoolCumber v2.0 Phase 1 Additions ---
    @Published var networkStats: [String: Double] = ["upload": 0, "download": 0]
    @Published var memoryStats: [String: Double] = ["used": 0, "total": 0]
    @Published var cpuUsage: [String: Double] = ["user": 0, "system": 0, "idle": 0, "nice": 0]
    @Published var diskSpace: [String: Double] = ["total": 0, "used": 0, "available": 0]
    
    @Published var currentCpuPercent: Double = 0
    @Published var currentMemPercent: Double = 0
    
    private var lastCpuUser: Double = 0
    private var lastCpuSystem: Double = 0
    private var lastCpuIdle: Double = 0
    private var lastCpuNice: Double = 0
    private var isFirstCpuFetch = true
    
    private var connection: NSXPCConnection?
    private var pollingTimer: Timer?
    
    init() {}
    
    func installDaemonIfNeeded() {
        #if APPSTORE
        DispatchQueue.main.async {
            self.daemonStatus = "App Sandbox Safe Mode"
        }
        #else
        let service = SMAppService.daemon(plistName: "com.coolcumber.helper.plist")
        
        // Unregister first to clear cached launchd configuration
        try? service.unregister()
        
        do {
            try service.register()
            DispatchQueue.main.async {
                self.daemonStatus = "Registered via SMAppService"
            }
            print("Daemon registered successfully.")
        } catch {
            print("SMAppService failed: \(error). Attempting fallback...")
            fallbackInstallWithAppleScript()
        }
        #endif
    }
    
    private func fallbackInstallWithAppleScript() {
        let bundleURL = Bundle.main.bundleURL
        let helperURL = bundleURL.appendingPathComponent("Contents/Library/LaunchServices/com.coolcumber.helper")
        let plistURL = bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/com.coolcumber.helper-fallback.plist")
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: helperURL.path), fm.fileExists(atPath: plistURL.path) else {
            DispatchQueue.main.async { self.daemonStatus = "Failed: Could not find daemon in bundle." }
            return
        }
        
        let script = """
        do shell script "launchctl bootout system /Library/LaunchDaemons/com.coolcumber.helper.plist || true; sleep 1; rm -f /Library/PrivilegedHelperTools/com.coolcumber.helper; rm -f /Library/LaunchDaemons/com.coolcumber.helper.plist; mkdir -p /Library/PrivilegedHelperTools && cp '\(helperURL.path)' /Library/PrivilegedHelperTools/com.coolcumber.helper && cp '\(plistURL.path)' /Library/LaunchDaemons/com.coolcumber.helper.plist && launchctl bootstrap system /Library/LaunchDaemons/com.coolcumber.helper.plist" with administrator privileges
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary? = nil
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&errorInfo)
                DispatchQueue.main.async {
                    if let err = errorInfo {
                        self.daemonStatus = "Admin Auth Failed: \(err)"
                    } else {
                        self.daemonStatus = "Installed via Admin Auth"
                    }
                }
            }
        }
    }
    
    func connect(errorHandler: ((Error) -> Void)? = nil) -> CoolCumberDaemonProtocol? {
        if connection == nil {
            let newConnection = NSXPCConnection(machServiceName: "com.coolcumber.helper", options: .privileged)
            newConnection.remoteObjectInterface = NSXPCInterface(with: CoolCumberDaemonProtocol.self)
            newConnection.invalidationHandler = {
                print("XPC Connection Invalidated. Setting to nil.")
                self.connection = nil
            }
            newConnection.interruptionHandler = {
                print("XPC Connection Interrupted. Setting to nil.")
                self.connection = nil
            }
            newConnection.resume()
            self.connection = newConnection
        }
        
        return connection?.remoteObjectProxyWithErrorHandler { error in
            print("XPC Error: \(error)")
            DispatchQueue.main.async {
                self.thermalStatus = "XPC Error: \(error.localizedDescription)"
            }
            if let customHandler = errorHandler {
                customHandler(error)
            }
        } as? CoolCumberDaemonProtocol
    }
    
    func verifyAndInstallHelper() {
        // Use SMAppService for modern, silent installation.
        installDaemonIfNeeded()
    }
    
    func checkThermalStatus() {
        #if APPSTORE
        // App Sandbox Native User-Space Telemetry
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal: self.thermalStatus = "Level Nominal"
        case .fair: self.thermalStatus = "Level Fair"
        case .serious: self.thermalStatus = "Level Serious"
        case .critical: self.thermalStatus = "Level Critical"
        @unknown default: self.thermalStatus = "Level Nominal"
        }
        
        // Host Memory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let active = Double(stats.active_count) * pageSize / 1024.0 / 1024.0
            let wired = Double(stats.wire_count) * pageSize / 1024.0 / 1024.0
            let compressed = Double(stats.compressor_page_count) * pageSize / 1024.0 / 1024.0
            let used = active + wired + compressed
            let total = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0
            self.memoryStats = ["used": used, "total": total]
            self.currentMemPercent = (used / total) * 100
        }
        
        // Disk Space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            let total = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            let totalGB = total / (1024 * 1024 * 1024)
            let usedGB = (total - free) / (1024 * 1024 * 1024)
            let freeGB = free / (1024 * 1024 * 1024)
            self.diskSpace = ["total": totalGB, "used": usedGB, "available": freeGB]
        }
        
        // Simulated Thermal Curves
        let baseTemp = 41.0 + (self.currentCpuPercent * 0.35)
        self.temperatures = ["CPU": round(baseTemp * 10) / 10, "GPU": round((baseTemp - 3.0) * 10) / 10]
        self.fanSpeed = "Auto (Controlled by macOS)"
        #else
        guard let proxy = connect() else {
            DispatchQueue.main.async {
                self.thermalStatus = "Daemon Connection Failed"
            }
            return
        }
        proxy.readThermalPressure { status in
            DispatchQueue.main.async {
                self.thermalStatus = status
            }
        }
        proxy.readFanSpeeds { speeds in
            DispatchQueue.main.async {
                if let speed = speeds.first {
                    self.fanSpeed = "\(speed) RPM"
                } else {
                    self.fanSpeed = "0 RPM"
                }
            }
        }
        proxy.readTemperatures { temps in
            DispatchQueue.main.async {
                self.temperatures = temps
            }
        }
        proxy.readSMARTData { data in
            DispatchQueue.main.async {
                self.smartData = data
            }
        }
        proxy.readDiskIOStats { io in
            DispatchQueue.main.async {
                self.diskIO = io
            }
        }
        
        // --- CoolCumber v2.0 Phase 1 Fetching ---
        proxy.readNetworkStats { stats in
            DispatchQueue.main.async {
                self.networkStats = stats
            }
        }
        proxy.readMemoryStats { stats in
            DispatchQueue.main.async {
                self.memoryStats = stats
                let used = stats["used"] ?? 0
                let total = stats["total"] ?? 1
                if total > 0 {
                    self.currentMemPercent = (used / total) * 100
                }
            }
        }
        proxy.readCPUUsage { usage in
            DispatchQueue.main.async {
                self.cpuUsage = usage
                
                let user = usage["user"] ?? 0
                let system = usage["system"] ?? 0
                let idle = usage["idle"] ?? 0
                let nice = usage["nice"] ?? 0
                
                if self.isFirstCpuFetch {
                    self.lastCpuUser = user
                    self.lastCpuSystem = system
                    self.lastCpuIdle = idle
                    self.lastCpuNice = nice
                    self.isFirstCpuFetch = false
                    self.currentCpuPercent = 0
                    return
                }
                
                let deltaUser = user - self.lastCpuUser
                let deltaSystem = system - self.lastCpuSystem
                let deltaIdle = idle - self.lastCpuIdle
                let deltaNice = nice - self.lastCpuNice
                
                self.lastCpuUser = user
                self.lastCpuSystem = system
                self.lastCpuIdle = idle
                self.lastCpuNice = nice
                
                let total = deltaUser + deltaSystem + deltaIdle + deltaNice
                if total > 0 {
                    self.currentCpuPercent = ((deltaUser + deltaSystem + deltaNice) / total) * 100
                }
            }
        }
        proxy.readDiskSpace { space in
            DispatchQueue.main.async {
                if let t = space["total"] as? Double, let u = space["used"] as? Double, let a = space["available"] as? Double {
                    self.diskSpace = ["total": t, "used": u, "available": a]
                }
            }
        }
        #endif
    }
    
    func purgeMemory(completion: @escaping (Bool, String?) -> Void) {
        guard let proxy = connect(errorHandler: { error in completion(false, error.localizedDescription) }) else {
            completion(false, "Daemon Offline")
            return
        }
        proxy.purgeMemory(reply: completion)
    }
    
    func manageProcessState(pid: Int32, action: String, completion: @escaping (Bool, String?) -> Void) {
        guard let proxy = connect() else {
            completion(false, "Daemon Offline")
            return
        }
        proxy.manageProcessState(pid: pid, action: action, reply: completion)
    }
    
    func setBatteryChargeLimit(_ percent: Int, completion: @escaping (Bool, String?) -> Void) {
        guard let proxy = connect() else {
            completion(false, "Daemon Offline")
            return
        }
        proxy.setBatteryChargeLimit(percent: percent, reply: completion)
    }
    
    func readBatteryHealth(completion: @escaping ([String: Any]) -> Void) {
        guard let proxy = connect() else {
            completion([:])
            return
        }
        proxy.readBatteryHealth(reply: completion)
    }
    
    func runMaintenance(type: String, completion: @escaping (Bool, String?) -> Void) {
        guard let proxy = connect(errorHandler: { error in completion(false, error.localizedDescription) }) else {
            completion(false, "Daemon Offline")
            return
        }
        proxy.runMaintenance(type: type, reply: completion)
    }
    
    func startPolling() {
        stopPolling()
        // Immediately fetch once
        checkThermalStatus()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkThermalStatus()
        }
    }
    
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    // Process Analysis
    func readTopProcesses(count: Int, completion: @escaping ([[String: Any]]) -> Void) {
        guard let proxy = connect() else {
            completion([])
            return
        }
        
        proxy.readTopProcesses(count: count) { processes in
            completion(processes)
        }
    }
    
    func readTopMemoryProcesses(count: Int, completion: @escaping ([[String: Any]]) -> Void) {
        guard let proxy = connect() else {
            completion([])
            return
        }
        
        proxy.readTopMemoryProcesses(count: count) { processes in
            completion(processes)
        }
    }
    
    func killProcess(pid: Int32, completion: @escaping (Bool, String?) -> Void) {
        guard let proxy = connect() else {
            completion(false, "Daemon Offline")
            return
        }
        
        proxy.killProcess(pid: pid, reply: completion)
    }
    
    func setEcoMode(enabled: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard let proxy = connect() else {
            completion(false, "Daemon Offline")
            return
        }
        
        proxy.setEcoMode(enabled: enabled, reply: completion)
    }
}
