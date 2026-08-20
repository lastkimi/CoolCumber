import Foundation
import ServiceManagement
import Darwin

class DaemonManager: ObservableObject {
    static let shared = DaemonManager()

    @Published var daemonStatus: String = "Not Installed"
    @Published var thermalStatus: String = "Unknown"
    @Published var fanSpeed: String = "Unavailable"
    @Published var temperatures: [String: Double] = [:]
    @Published var smartData: [String: Any] = [:]
    @Published var diskIO: [String: Double] = [:]

    // --- CoolCumber v2.0 Phase 1 Additions ---
    @Published var networkStats: [String: Double] = [:]
    @Published var memoryStats: [String: Double] = [:]
    @Published var cpuUsage: [String: Double] = [:]
    @Published var diskSpace: [String: Double] = [:]

    @Published var currentCpuPercent: Double = 0
    @Published var currentMemPercent: Double = 0

    private var lastCpuUser: Double = 0
    private var lastCpuSystem: Double = 0
    private var lastCpuIdle: Double = 0
    private var lastCpuNice: Double = 0
    private var isFirstCpuFetch = true
    private var lastNetworkUpload: Double?
    private var lastNetworkDownload: Double?
    private var lastNetworkSampleDate: Date?
    
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

        if service.status == .enabled {
            daemonStatus = "Helper Enabled"
            return
        }

        do {
            try service.register()
            DispatchQueue.main.async {
                self.daemonStatus = service.status == .requiresApproval
                    ? "Approval Required in System Settings"
                    : "Helper Registered"
            }
        } catch {
            DispatchQueue.main.async {
                self.daemonStatus = "Helper Registration Failed: \(error.localizedDescription)"
            }
        }
        #endif
    }

    func connect(errorHandler: ((Error) -> Void)? = nil) -> CoolCumberDaemonProtocol? {
        #if APPSTORE
        return nil
        #else
        if connection == nil {
            let newConnection = NSXPCConnection(machServiceName: "com.coolcumber.helper", options: .privileged)
            #if DEBUG
            newConnection.setCodeSigningRequirement("identifier \"com.coolcumber.helper\"")
            #else
            newConnection.setCodeSigningRequirement("identifier \"com.coolcumber.helper\" and anchor apple generic and certificate leaf[subject.OU] = \"BSKR6CQ765\"")
            #endif
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
        #endif
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
        @unknown default: self.thermalStatus = "Unknown"
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
            let appPages = max(0, Double(stats.internal_page_count) - Double(stats.purgeable_count))
            let used = (appPages + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            self.memoryStats = ["used": used, "total": total]
            self.currentMemPercent = total > 0 ? (used / total) * 100 : 0
        } else {
            self.memoryStats = [:]
        }
        
        // Disk Space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            let total = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            self.diskSpace = ["total": total, "used": max(0, total - free), "available": free]
        } else {
            self.diskSpace = [:]
        }

        if let usage = sampleLocalCPUTicks() {
            updateCPUUsage(with: usage)
        } else {
            self.cpuUsage = [:]
        }
        if let counters = sampleLocalNetworkCounters() {
            updateNetworkCounters(counters)
        } else {
            self.networkStats = [:]
        }

        // The sandbox exposes thermal pressure, not sensor temperatures or fan RPM.
        self.temperatures = [:]
        self.fanSpeed = "Unavailable in App Store edition"
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
                    self.fanSpeed = "Unavailable"
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
                self.updateNetworkCounters(stats)
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
                self.updateCPUUsage(with: usage)
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

    private func updateCPUUsage(with usage: [String: Double]) {
        guard let user = usage["user"],
              let system = usage["system"],
              let idle = usage["idle"],
              let nice = usage["nice"] else {
            cpuUsage = [:]
            return
        }

        cpuUsage = usage
        if isFirstCpuFetch || user < lastCpuUser || system < lastCpuSystem || idle < lastCpuIdle || nice < lastCpuNice {
            lastCpuUser = user
            lastCpuSystem = system
            lastCpuIdle = idle
            lastCpuNice = nice
            isFirstCpuFetch = false
            return
        }

        let deltaUser = user - lastCpuUser
        let deltaSystem = system - lastCpuSystem
        let deltaIdle = idle - lastCpuIdle
        let deltaNice = nice - lastCpuNice
        lastCpuUser = user
        lastCpuSystem = system
        lastCpuIdle = idle
        lastCpuNice = nice

        let total = deltaUser + deltaSystem + deltaIdle + deltaNice
        if total > 0 {
            currentCpuPercent = min(100, max(0, ((deltaUser + deltaSystem + deltaNice) / total) * 100))
        }
    }

    private func updateNetworkCounters(_ counters: [String: Double]) {
        guard let upload = counters["upload"],
              let download = counters["download"],
              upload >= 0, download >= 0 else {
            networkStats = [:]
            return
        }

        let now = Date()
        defer {
            lastNetworkUpload = upload
            lastNetworkDownload = download
            lastNetworkSampleDate = now
        }

        guard let previousUpload = lastNetworkUpload,
              let previousDownload = lastNetworkDownload,
              let previousDate = lastNetworkSampleDate,
              upload >= previousUpload,
              download >= previousDownload else {
            networkStats = [:]
            return
        }

        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0 else {
            networkStats = [:]
            return
        }
        networkStats = [
            "upload": (upload - previousUpload) / elapsed,
            "download": (download - previousDownload) / elapsed
        ]
    }

    private func sampleLocalCPUTicks() -> [String: Double]? {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var user = 0.0
        var system = 0.0
        var idle = 0.0
        var nice = 0.0
        for cpu in 0..<Int(numCPUs) {
            let index = cpu * Int(CPU_STATE_MAX)
            user += Double(cpuInfo[index + Int(CPU_STATE_USER)])
            system += Double(cpuInfo[index + Int(CPU_STATE_SYSTEM)])
            idle += Double(cpuInfo[index + Int(CPU_STATE_IDLE)])
            nice += Double(cpuInfo[index + Int(CPU_STATE_NICE)])
        }
        return ["user": user, "system": system, "idle": idle, "nice": nice]
    }

    private func sampleLocalNetworkCounters() -> [String: Double]? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return nil }
        defer { freeifaddrs(firstAddress) }

        var upload = 0.0
        var download = 0.0
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = pointer {
            let interface = current.pointee
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let rawData = interface.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                upload += Double(data.ifi_obytes)
                download += Double(data.ifi_ibytes)
            }
            pointer = interface.ifa_next
        }
        return ["upload": upload, "download": download]
    }

    func purgeMemory(completion: @escaping (Bool, String?) -> Void) {
        completion(false, "Memory purge was removed because macOS manages memory pressure automatically.")
    }

    func manageProcessState(pid: Int32, action: String, completion: @escaping (Bool, String?) -> Void) {
        completion(false, "Process freezing and throttling are disabled pending a non-root safety redesign.")
    }
    
    func setBatteryChargeLimit(_ percent: Int, completion: @escaping (Bool, String?) -> Void) {
        #if APPSTORE
        completion(false, "Charge limits are unavailable in the App Store edition.")
        #else
        guard let proxy = connect() else {
            completion(false, "Daemon Offline")
            return
        }
        proxy.setBatteryChargeLimit(percent: percent, reply: completion)
        #endif
    }
    
    func readBatteryHealth(completion: @escaping ([String: Any]) -> Void) {
        #if APPSTORE
        completion([:])
        #else
        guard let proxy = connect() else {
            completion([:])
            return
        }
        proxy.readBatteryHealth(reply: completion)
        #endif
    }
    
    func runMaintenance(type: String, completion: @escaping (Bool, String?) -> Void) {
        completion(false, "Privileged maintenance actions are disabled for safety.")
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
        #if APPSTORE
        completion([])
        #else
        guard let proxy = connect() else {
            completion([])
            return
        }
        
        proxy.readTopProcesses(count: count) { processes in
            completion(processes)
        }
        #endif
    }
    
    func readTopMemoryProcesses(count: Int, completion: @escaping ([[String: Any]]) -> Void) {
        #if APPSTORE
        completion([])
        #else
        guard let proxy = connect() else {
            completion([])
            return
        }
        
        proxy.readTopMemoryProcesses(count: count) { processes in
            completion(processes)
        }
        #endif
    }
    
    func killProcess(pid: Int32, completion: @escaping (Bool, String?) -> Void) {
        completion(false, "Root-level process termination is disabled for safety.")
    }
    
    func setEcoMode(enabled: Bool, completion: @escaping (Bool, String?) -> Void) {
        #if APPSTORE
        completion(false, "Eco mode control is unavailable in the App Store edition.")
        #else
        guard let proxy = connect() else {
            completion(false, "Daemon Offline")
            return
        }
        
        proxy.setEcoMode(enabled: enabled, reply: completion)
        #endif
    }
}
