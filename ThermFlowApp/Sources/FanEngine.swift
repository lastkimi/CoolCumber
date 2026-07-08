import Foundation
import AppKit

class FanEngine: ObservableObject {
    static let shared = FanEngine()
    
    // Configurable keys for UserDefaults
    private let kManualModeEnabled = "fan_manual_mode_enabled"
    private let kManualFanRPM = "fan_manual_rpm"
    private let kProactiveModeEnabled = "fan_proactive_mode_enabled"
    
    @Published var isManualModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isManualModeEnabled, forKey: kManualModeEnabled)
            applyCurrentState()
        }
    }
    
    @Published var manualFanRPM: Double {
        didSet {
            UserDefaults.standard.set(manualFanRPM, forKey: kManualFanRPM)
            if isManualModeEnabled {
                applyCurrentState()
            }
        }
    }
    
    @Published var isProactiveModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isProactiveModeEnabled, forKey: kProactiveModeEnabled)
        }
    }
    
    // Current active automatic speed target (nil if system default)
    private var activeAutoRPM: Int? = nil
    private var lastEvaluatedTemp: Double = 0.0
    
    private var timer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    
    // Known heat-generating apps
    let heavyApps = ["Xcode", "Final Cut Pro", "Logic Pro", "Blender", "UnrealEditor", "Adobe Premiere Pro"]
    
    private init() {
        // Load settings from UserDefaults
        self.isManualModeEnabled = UserDefaults.standard.bool(forKey: kManualModeEnabled)
        let savedRPM = UserDefaults.standard.double(forKey: kManualFanRPM)
        self.manualFanRPM = savedRPM > 0 ? savedRPM : 2500
        
        // Default proactive mode to true if not set
        if UserDefaults.standard.object(forKey: kProactiveModeEnabled) == nil {
            self.isProactiveModeEnabled = true
        } else {
            self.isProactiveModeEnabled = UserDefaults.standard.bool(forKey: kProactiveModeEnabled)
        }
    }
    
    func start() {
        // 1. Observe app launches for proactive cooling
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let name = app.localizedName else { return }
            self?.handleAppLaunch(appName: name)
        }
        
        // 2. Periodic background temperature check (every 5 seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.evaluateThermalProfile()
        }
        
        // Initial state application
        applyCurrentState()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    
    private func handleAppLaunch(appName: String) {
        guard isProactiveModeEnabled && !isManualModeEnabled else { return }
        
        if heavyApps.contains(where: { appName.contains($0) }) {
            print("Proactive Cooling: Heavy app \(appName) launched. Ramping up fan.")
            setFanSpeedIfNeeded(rpm: 3500)
        }
    }
    
    private func setFanSpeedIfNeeded(rpm: Int) {
        guard !isManualModeEnabled else { return }
        activeAutoRPM = rpm
        applyCurrentState()
    }
    
    private func evaluateThermalProfile() {
        // Skip automatic cooling logic if manual mode is enabled
        guard !isManualModeEnabled else { return }
        
        let daemon = DaemonManager.shared
        let currentTemp = daemon.temperatures["CPU"] ?? 50.0
        
        DispatchQueue.main.async {
            var target: Int? = nil
            let tempDiff = abs(currentTemp - self.lastEvaluatedTemp)
            let isSignificantChange = tempDiff >= 3.0 || currentTemp < 50.0 || currentTemp >= 80.0
            
            // Only recalculate if temperature has changed significantly to prevent fan speed hunting (Hysteresis)
            if isSignificantChange || self.activeAutoRPM == nil {
                if currentTemp < 50.0 {
                    // Below 50°C: System Default (Silent)
                    target = nil
                } else if currentTemp >= 80.0 {
                    // Above 80°C: Maximum Cooling
                    target = 6000
                } else {
                    // 50°C - 80°C: Linear interpolation between 1800 RPM and 6000 RPM
                    let progress = (currentTemp - 50.0) / 30.0
                    let calculatedRPM = 1800.0 + (progress * (6000.0 - 1800.0))
                    target = Int(calculatedRPM)
                }
                
                self.lastEvaluatedTemp = currentTemp
                
                if target != self.activeAutoRPM {
                    self.activeAutoRPM = target
                    self.applyCurrentState()
                }
            }
        }
    }
    
    func applyCurrentState() {
        let daemon = DaemonManager.shared
        guard let proxy = daemon.connect() else { return }
        
        if isManualModeEnabled {
            let rpm = Int(manualFanRPM)
            print("FanEngine: Applying Manual Override: \(rpm) RPM")
            proxy.setFanSpeed(fanIndex: 0, rpm: rpm) { _, _ in }
        } else if let autoRPM = activeAutoRPM {
            print("FanEngine: Applying Auto Cooling: \(autoRPM) RPM")
            proxy.setFanSpeed(fanIndex: 0, rpm: autoRPM) { _, _ in }
        } else {
            print("FanEngine: Restoring System Automatic Control")
            proxy.resetFanToAutomatic { _ in }
        }
    }
}
