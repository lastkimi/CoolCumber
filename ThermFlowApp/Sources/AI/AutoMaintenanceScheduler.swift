import Foundation
import Combine

class AutoMaintenanceScheduler: ObservableObject {
    static let shared = AutoMaintenanceScheduler()
    
    private var timer: Timer?
    @Published var lastMaintenanceTime: Date?
    
    func start() {
        // Run check every 60 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkAndPerformMaintenance()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkAndPerformMaintenance() {
        let daemon = DaemonManager.shared
        
        let memTotal = daemon.memoryStats["total"] ?? 1.0
        let memUsed = daemon.memoryStats["used"] ?? 0.0
        let memPercent = memTotal > 0 ? (memUsed / memTotal * 100) : 0
        
        // Auto purge if memory used > 90%
        if memPercent > 90.0 {
            // Prevent spamming purge (only once every 5 minutes)
            if let last = lastMaintenanceTime, Date().timeIntervalSince(last) < 300 {
                return
            }
            
            print("AutoMaintenanceScheduler: Memory critically high (\(Int(memPercent))%). Triggering automatic purge.")
            daemon.purgeMemory { success, error in
                if success {
                    DispatchQueue.main.async {
                        self.lastMaintenanceTime = Date()
                    }
                } else {
                    print("AutoMaintenanceScheduler: Failed to purge memory: \(error ?? "Unknown Error")")
                }
            }
        }
    }
}
