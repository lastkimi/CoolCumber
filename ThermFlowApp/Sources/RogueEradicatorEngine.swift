import Foundation

struct RogueItem: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let path: String
    let program: String
    let type: String // "Daemon" | "Agent" | "UserAgent"
}

struct RunningProcessItem: Identifiable {
    let id = UUID()
    let pid: Int32
    let name: String
    let cpu: Double
    let memMB: Double
    let path: String
    var aiExplanation: String?
}

class RogueEradicatorEngine: ObservableObject {
    static let shared = RogueEradicatorEngine()
    
    @Published var items: [RogueItem] = []
    @Published var isScanning = false
    @Published var uninstallResult: String?
    
    @Published var runningProcesses: [RunningProcessItem] = []
    @Published var isScanningProcesses = false
    
    private init() {}
    
    func scan() {
        isScanning = true
        uninstallResult = nil
        
        guard let proxy = DaemonManager.shared.connect(errorHandler: { error in
            DispatchQueue.main.async {
                self.isScanning = false
                self.uninstallResult = "XPC Error: \(error.localizedDescription)"
            }
        }) else {
            self.isScanning = false
            self.uninstallResult = "Failed to connect to Daemon"
            return
        }
        
        proxy.listLaunchDaemons { results in
            let mapped = results.compactMap { dict -> RogueItem? in
                guard let label = dict["label"] as? String,
                      let path = dict["path"] as? String,
                      let program = dict["program"] as? String,
                      let type = dict["type"] as? String else {
                    return nil
                }
                return RogueItem(label: label, path: path, program: program, type: type)
            }
            
            DispatchQueue.main.async {
                self.items = mapped
                self.isScanning = false
            }
        }
    }
    
    func uninstall(item: RogueItem) {
        guard let proxy = DaemonManager.shared.connect() else {
            self.uninstallResult = "Failed to connect to Daemon"
            return
        }
        
        proxy.disableLaunchAgent(plistPath: item.path) { success, message in
            DispatchQueue.main.async {
                if success {
                    self.uninstallResult = message ?? "Successfully uninstalled \(item.label)"
                    self.scan() // refresh
                } else {
                    self.uninstallResult = "Error: \(message ?? "Unknown error")"
                }
            }
        }
    }
    
    func scanProcesses() {
        isScanningProcesses = true
        uninstallResult = nil
        
        DaemonManager.shared.readTopMemoryProcesses(count: 35) { results in
            let mapped = results.compactMap { dict -> RunningProcessItem? in
                guard let pidStr = dict["pid"] as? String, let pid = Int32(pidStr),
                      let cpu = dict["cpu"] as? Double,
                      let mem = dict["mem"] as? Double,
                      let name = dict["name"] as? String,
                      let path = dict["path"] as? String else {
                    return nil
                }
                return RunningProcessItem(pid: pid, name: name, cpu: cpu, memMB: mem, path: path)
            }
            
            DispatchQueue.main.async {
                self.runningProcesses = mapped
                self.isScanningProcesses = false
            }
        }
    }
    
    func killProcess(pid: Int32) {
        DaemonManager.shared.killProcess(pid: pid) { success, message in
            DispatchQueue.main.async {
                if success {
                    self.uninstallResult = "已成功强行关闭进程 (PID \(pid))。"
                    self.scanProcesses()
                } else {
                    self.uninstallResult = "无法关闭进程: \(message ?? "未提供错误原因")"
                }
            }
        }
    }
    
    func askAIAboutProcess(item: RunningProcessItem) {
        guard let index = self.runningProcesses.firstIndex(where: { $0.id == item.id }) else { return }
        
        self.runningProcesses[index].aiExplanation = "正在分析..."
        
        LLMEngine.shared.explainProcess(name: item.name, path: item.path) { explanation in
            DispatchQueue.main.async {
                if let idx = self.runningProcesses.firstIndex(where: { $0.id == item.id }) {
                    self.runningProcesses[idx].aiExplanation = explanation
                }
            }
        }
    }
}
