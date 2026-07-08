import Foundation
import AppKit
import Combine

class AppFreezerManager: ObservableObject {
    static let shared = AppFreezerManager()
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "app_freezer_enabled")
            if !isEnabled {
                unfreezeAll()
            } else {
                applyFreezerState()
            }
        }
    }
    
    @Published var config: [String: String] = [:] {
        didSet {
            if let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: "app_freezer_config")
            }
            if isEnabled {
                applyFreezerState()
            }
        }
    }
    
    // Track frozen pids to properly restore them
    private var managedPids: [String: Set<Int32>] = ["freeze": [], "throttle": []]
    private var workspaceObserver: Any?
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "app_freezer_enabled")
        if let data = UserDefaults.standard.data(forKey: "app_freezer_config"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            self.config = dict
        }
        
        startObserving()
    }
    
    private func startObserving() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isEnabled else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            
            // Unfreeze/unthrottle the newly active app
            self.restoreApp(app)
            
            // Re-evaluate background apps
            self.applyFreezerState()
        }
    }
    
    func applyFreezerState() {
        guard isEnabled else { return }
        
        let activeApp = NSWorkspace.shared.frontmostApplication
        
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleId = app.bundleIdentifier else { continue }
            guard app != activeApp else { continue }
            
            if let mode = config[bundleId] {
                suspendApp(app, mode: mode)
            }
        }
    }
    
    private func suspendApp(_ app: NSRunningApplication, mode: String) {
        let pid = app.processIdentifier
        
        if mode == "freeze" {
            if !(managedPids["freeze"]?.contains(pid) ?? false) {
                managedPids["freeze"]?.insert(pid)
                DaemonManager.shared.manageProcessState(pid: pid, action: "freeze") { _, _ in 
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                        DaemonManager.shared.runMaintenance(type: "compress") { _, _ in }
                    }
                }
            }
        } else if mode == "throttle" {
            if !(managedPids["throttle"]?.contains(pid) ?? false) {
                managedPids["throttle"]?.insert(pid)
                DaemonManager.shared.manageProcessState(pid: pid, action: "throttle") { _, _ in }
            }
        }
    }
    
    private func restoreApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        
        if managedPids["freeze"]?.contains(pid) == true {
            managedPids["freeze"]?.remove(pid)
            DaemonManager.shared.manageProcessState(pid: pid, action: "unfreeze") { _, _ in }
        }
        
        if managedPids["throttle"]?.contains(pid) == true {
            managedPids["throttle"]?.remove(pid)
            DaemonManager.shared.manageProcessState(pid: pid, action: "unthrottle") { _, _ in }
        }
    }
    
    func unfreezeAll() {
        for pid in managedPids["freeze"] ?? [] {
            DaemonManager.shared.manageProcessState(pid: pid, action: "unfreeze") { _, _ in }
        }
        managedPids["freeze"]?.removeAll()
        
        for pid in managedPids["throttle"] ?? [] {
            DaemonManager.shared.manageProcessState(pid: pid, action: "unthrottle") { _, _ in }
        }
        managedPids["throttle"]?.removeAll()
    }
}
