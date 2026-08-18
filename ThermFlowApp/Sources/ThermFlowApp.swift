import SwiftUI
import AppKit

@main
struct CoolCumberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?
    var dashboardWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // 1. Install or connect to the privileged helper daemon
        DaemonManager.shared.installDaemonIfNeeded()
        
        // 2. Setup menu bar and Smart Bar
        MenuBarManager.shared.setup()
        SmartBarManager.shared.setup()
        
        // 3. Start proactive cooling engine
        FanEngine.shared.start()
        
        // 4. Start diagnostics
        DiagnosticEngine.shared.start()
        
        // 5. Initialize App Freezer Manager
        _ = AppFreezerManager.shared
        
        // 6. (Optional) Run initial diagnostic
        DaemonManager.shared.checkThermalStatus()
        
        // Auto open dashboard on launch
        showDashboard()
        
        // 7. Cleanup Installation DMG
        #if !DEBUG
        cleanupDMG()
        #endif
    }
    
    private func cleanupDMG() {
        #if !DEBUG
        DispatchQueue.global(qos: .background).async {
            // Find if we are running from /Applications
            let bundlePath = Bundle.main.bundlePath
            guard bundlePath.hasPrefix("/Applications") else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = ["info", "-plist"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let images = plist["images"] as? [[String: Any]] {
                    
                    for image in images {
                        if let imagePath = image["image-path"] as? String,
                           (imagePath.contains("CoolCumber") || imagePath.contains("ThermFlow")),
                           imagePath.hasSuffix(".dmg") {
                            
                            // Detach mounts
                            if let systemEntities = image["system-entities"] as? [[String: Any]] {
                                for entity in systemEntities {
                                    if let mountPoint = entity["mount-point"] as? String {
                                        print("Detaching DMG at mount point: \(mountPoint)")
                                        let detachProcess = Process()
                                        detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                                        detachProcess.arguments = ["detach", mountPoint, "-force"]
                                        try? detachProcess.run()
                                        detachProcess.waitUntilExit()
                                    }
                                }
                            }
                            
                            // Move DMG to trash
                            let fileURL = URL(fileURLWithPath: imagePath)
                            print("Trashing DMG at: \(imagePath)")
                            try? FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                        }
                    }
                }
            } catch {
                print("Error cleaning up DMG: \(error)")
            }
        }
        #endif
    }
    
    func showDashboard() {
        // Delegate to MenuBarManager's popover
        MenuBarManager.shared.openDashboard()
    }
    
    func windowWillClose(_ notification: Notification) {
        // No longer managing dashboardWindow
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        FanEngine.shared.stop()
        DiagnosticEngine.shared.stop()
    }
    
    // Prevent the app from quitting when the main window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
