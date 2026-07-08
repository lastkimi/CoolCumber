import Foundation
import AppKit

class DiagnosticEngine {
    static let shared = DiagnosticEngine()
    
    private var timer: Timer?
    
    func start() {
        // Run diagnostics every 5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.runDiagnostics()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func runDiagnostics() {
        DaemonManager.shared.connect()?.readThermalPressure { status in
            DispatchQueue.main.async {
                if status.contains("Throttled") || status.contains("Serious") || status.contains("Critical") {
                    self.triggerThermalWarning(status: status)
                }
            }
        }
    }
    
    private func triggerThermalWarning(status: String) {
        print("Diagnostic Warning: \(status). High thermal pressure detected.")
        // In a real app, this would use UserNotifications framework (UNUserNotificationCenter)
        // to present a notification: "检测到系统强制降频，建议将充电线换到机身右侧。"
    }
}
