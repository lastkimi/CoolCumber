import Foundation
import Combine

struct DiagnosticResult {
    let message: String
    let status: DiagnosticStatus
    let recommendedAction: RecommendedAction?
}

enum DiagnosticStatus {
    case healthy, warning, critical
}

enum RecommendedAction {
    case increaseFan(rpm: Int)
    case purgeMemory
    case killProcess(pid: String)
}

class DiagnosticRuleEngine: ObservableObject {
    static let shared = DiagnosticRuleEngine()
    
    @Published var currentDiagnosis: DiagnosticResult = DiagnosticResult(message: "System is healthy. No issues detected.", status: .healthy, recommendedAction: nil)
    
    private var timer: Timer?
    
    // Thresholds
    private let highTempThreshold = 85.0
    private let criticalTempThreshold = 95.0
    private let highMemoryThreshold = 85.0 // percent
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.evaluateRules()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func evaluateRules() {
        let daemon = DaemonManager.shared
        let cpuTemp = daemon.temperatures["CPU"] ?? 50.0
        
        // 1. Check Storage Rule (Rule 1-2)
        let totalDisk = daemon.diskSpace["total"] ?? 1.0
        let availDisk = daemon.diskSpace["available"] ?? 0.0
        let freeGB = availDisk / 1_000_000_000
        let diskPercent = totalDisk > 0 ? ((totalDisk - availDisk) / totalDisk) * 100 : 0
        
        if totalDisk > 1.0 && freeGB < 15.0 {
            DispatchQueue.main.async {
                self.currentDiagnosis = DiagnosticResult(
                    message: "Disk space is critically low (only \(Int(freeGB))GB free). System performance may severely degrade.",
                    status: .critical,
                    recommendedAction: nil
                )
            }
            return
        }
        
        // 2. Check Network Rule (Rule 3-4)
        let downRate = (daemon.networkStats["down"] ?? 0) / 1024 / 1024
        if downRate > 50.0 && cpuTemp > 75.0 {
            DispatchQueue.main.async {
                self.currentDiagnosis = DiagnosticResult(
                    message: "Heavy network download (\(String(format: "%.1f", downRate)) MB/s) is causing network stack overhead and heating.",
                    status: .warning,
                    recommendedAction: .increaseFan(rpm: 3500)
                )
            }
            return
        }
        
        // 3. Check memory (Rule 5-6)
        let memTotal = daemon.memoryStats["total"] ?? 1.0
        let memUsed = daemon.memoryStats["used"] ?? 0.0
        let memPercent = memTotal > 0 ? (memUsed / memTotal * 100) : 0
        
        if memPercent > highMemoryThreshold {
            DispatchQueue.main.async {
                self.currentDiagnosis = DiagnosticResult(
                    message: "Memory usage is very high (\(Int(memPercent))%). Consider purging inactive memory to free up space.",
                    status: .warning,
                    recommendedAction: .purgeMemory
                )
            }
            return
        }
        
        // 4. Check temperature and processes (Rules 7-50+)
        if cpuTemp > highTempThreshold {
            daemon.readTopProcesses(count: 3) { processes in
                DispatchQueue.main.async {
                    if let topProcess = processes.first, let name = topProcess["name"] as? String, let cpu = topProcess["cpu"] as? Double, cpu > 30.0 {
                        
                        var action: RecommendedAction? = nil
                        let status: DiagnosticStatus = cpuTemp > self.criticalTempThreshold ? .critical : .warning
                        if cpuTemp > 90 { action = .increaseFan(rpm: 4500) } else { action = .increaseFan(rpm: 3500) }
                        
                        let (appName, specificAdvice) = self.analyzeAppProfile(for: name)
                        
                        self.currentDiagnosis = DiagnosticResult(
                            message: "\(appName) is using \(Int(cpu))% CPU, pushing temp to \(Int(cpuTemp))°C. \(specificAdvice)",
                            status: status,
                            recommendedAction: action
                        )
                    } else {
                        self.currentDiagnosis = DiagnosticResult(
                            message: "CPU Temperature is high (\(Int(cpuTemp))°C), but load is distributed. Ambient heat or background tasks?",
                            status: cpuTemp > self.criticalTempThreshold ? .critical : .warning,
                            recommendedAction: .increaseFan(rpm: 4500)
                        )
                    }
                }
            }
            return
        }
        
        // 5. Default healthy (Rule 50+)
        DispatchQueue.main.async {
            self.currentDiagnosis = DiagnosticResult(
                message: "System is healthy. CPU at \(Int(cpuTemp))°C and Memory at \(Int(memPercent))%.",
                status: .healthy,
                recommendedAction: nil
            )
        }
    }
    
    private func analyzeAppProfile(for executableName: String) -> (String, String) {
        let name = executableName.lowercased()
        
        // Development Tools (Rules 7-15)
        if name.contains("xcode") { return ("Xcode", "Large compilations can cause thermal throttling.") }
        if name.contains("simulator") { return ("iOS Simulator", "Virtualization overhead detected.") }
        if name.contains("docker") || name.contains("com.docker") { return ("Docker", "Container engine is heavily active.") }
        if name.contains("java") { return ("Java VM", "JVM garbage collection or heavy threads active.") }
        if name.contains("node") { return ("Node.js", "V8 engine processing heavy JS workloads.") }
        if name.contains("python") { return ("Python", "Data processing or ML script running.") }
        if name.contains("rustc") || name.contains("cargo") { return ("Rust Compiler", "Maxing out CPU cores for compilation.") }
        if name.contains("goland") || name.contains("intellij") { return ("JetBrains IDE", "Code indexing or analysis in progress.") }
        
        // Browsers & Web (Rules 16-22)
        if name.contains("chrome") { return ("Google Chrome", "Check for runaway tabs or WebGL tasks.") }
        if name.contains("safari") { return ("Safari", "Heavy DOM rendering or media playback.") }
        if name.contains("firefox") { return ("Firefox", "Active browser rendering detected.") }
        if name.contains("edge") { return ("Microsoft Edge", "Chromium engine under load.") }
        if name.contains("arc") { return ("Arc Browser", "Browser is executing heavy tasks.") }
        if name.contains("windowserver") { return ("WindowServer", "macOS UI compositor is stressed by many windows or external displays.") }
        
        // Media & Creativity (Rules 23-30)
        if name.contains("final cut") { return ("Final Cut Pro", "Video rendering or exporting active.") }
        if name.contains("logic") { return ("Logic Pro", "Heavy audio plugin processing.") }
        if name.contains("premiere") { return ("Adobe Premiere", "Video timeline rendering.") }
        if name.contains("after effects") || name.contains("aerendercore") { return ("Adobe After Effects", "RAM preview or export active.") }
        if name.contains("photoshop") { return ("Adobe Photoshop", "Large canvas or complex filters applied.") }
        if name.contains("lightroom") { return ("Adobe Lightroom", "Batch photo exporting.") }
        if name.contains("blender") { return ("Blender", "3D scene rendering in progress.") }
        if name.contains("obs") { return ("OBS Studio", "Live streaming or recording active.") }
        
        // Communication & Office (Rules 31-38)
        if name.contains("zoom") { return ("Zoom", "Video conferencing encoding.") }
        if name.contains("teams") { return ("Microsoft Teams", "Electron wrapper consuming resources.") }
        if name.contains("slack") { return ("Slack", "Electron app background activity.") }
        if name.contains("discord") { return ("Discord", "Voice/video chat encoding active.") }
        if name.contains("wechat") { return ("WeChat", "App background sync or mini-program load.") }
        if name.contains("excel") { return ("Microsoft Excel", "Calculating large spreadsheets.") }
        if name.contains("powerpoint") { return ("Microsoft PowerPoint", "Handling complex presentations.") }
        
        // Games (Rules 39-43)
        if name.contains("steam") { return ("Steam", "Game downloading or background task.") }
        if name.contains("leagueoflegends") { return ("League of Legends", "Game engine is actively rendering.") }
        if name.contains("minecraft") { return ("Minecraft", "Chunk generation or heavy mods active.") }
        if name.contains("crossover") { return ("CrossOver", "Windows compatibility layer active.") }
        
        // System Daemons (Rules 44-50+)
        if name.contains("mdworker") || name.contains("mds") { return ("Spotlight", "File indexing active. This is normal after an update.") }
        if name.contains("kernel_task") { return ("macOS Kernel", "System is protecting CPU from overheating.") }
        if name.contains("sysmond") { return ("System Monitor", "Activity Monitor or similar tool is running.") }
        if name.contains("backupd") { return ("Time Machine", "Creating system backups.") }
        if name.contains("softwareupdated") { return ("Software Update", "Downloading/Installing macOS update.") }
        if name.contains("trustd") { return ("Trust Daemon", "Validating certificates.") }
        if name.contains("bird") { return ("iCloud Drive", "Syncing files to iCloud.") }
        
        return (executableName, "Consider closing this app if you don't need it.")
    }
}
