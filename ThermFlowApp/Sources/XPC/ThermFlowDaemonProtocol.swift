import Foundation

@objc protocol CoolCumberDaemonProtocol {
    // --- SMC ---
    func readTemperatures(reply: @escaping ([String: Double]) -> Void)
    func setFanSpeed(fanIndex: Int, rpm: Int, reply: @escaping (Bool, String?) -> Void)
    func resetFanToAutomatic(reply: @escaping (Bool) -> Void)
    func readFanSpeeds(reply: @escaping ([Int]) -> Void)
    
    // --- Thermal ---
    func readThermalPressure(reply: @escaping (String) -> Void)
    func readCPUPowerMetrics(reply: @escaping ([String: Any]) -> Void)
    
    // --- LaunchDaemon ---
    func listLaunchDaemons(reply: @escaping ([[String: Any]]) -> Void)
    func bootoutDaemon(label: String, reply: @escaping (Bool, String?) -> Void)
    func disableLaunchAgent(plistPath: String, reply: @escaping (Bool, String?) -> Void)
    func readSMARTData(reply: @escaping ([String: Any]) -> Void)
    func readDiskIOStats(reply: @escaping ([String: Double]) -> Void)
    
    // Hardware Guardians
    func readBatteryHealth(reply: @escaping ([String: Any]) -> Void)
    func setBatteryChargeLimit(percent: Int, reply: @escaping (Bool, String?) -> Void)
    
    // System Maintenance
    func runMaintenance(type: String, reply: @escaping (Bool, String?) -> Void)
    
    // --- CoolCumber v2.0 Phase 1 Additions ---
    func readNetworkStats(reply: @escaping ([String: Double]) -> Void)
    func readMemoryStats(reply: @escaping ([String: Double]) -> Void)
    func readCPUUsage(reply: @escaping ([String: Double]) -> Void)
    func readDiskSpace(reply: @escaping ([String: Any]) -> Void)
    func purgeMemory(reply: @escaping (Bool, String?) -> Void)
    
    // Process Analysis
    func readTopProcesses(count: Int, reply: @escaping ([[String: Any]]) -> Void)
    func readTopMemoryProcesses(count: Int, reply: @escaping ([[String: Any]]) -> Void)
    func killProcess(pid: Int32, reply: @escaping (Bool, String?) -> Void)
    func setEcoMode(enabled: Bool, reply: @escaping (Bool, String?) -> Void)
    func manageProcessState(pid: Int32, action: String, reply: @escaping (Bool, String?) -> Void)
}
