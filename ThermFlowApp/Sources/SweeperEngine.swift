import Foundation

struct SweeperItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let description: String
    var size: UInt64 // Bytes
    var isSelected: Bool = true
    
    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

class SweeperEngine: ObservableObject {
    static let shared = SweeperEngine()
    
    @Published var items: [SweeperItem] = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var cleanResult: String?
    @Published var hasScanned = false
    
    private init() {}
    
    func getHomeDir() -> String {
        return NSHomeDirectory()
    }
    
    func scan() {
        isScanning = true
        cleanResult = nil
        
        let home = getHomeDir()
        let scanTargets = [
            ("Xcode DerivedData", "\(home)/Library/Developer/Xcode/DerivedData", "DerivedData files created during Xcode builds."),
            ("iOS Simulators", "\(home)/Library/Developer/CoreSimulator/Devices", "iOS emulator caches and simulated device storage."),
            ("Docker Cache", "\(home)/Library/Caches/com.docker.docker", "Docker container images and system cache."),
            ("npm Cache", "\(home)/.npm", "Cache directory for npm packages."),
            ("Yarn Cache", "\(home)/Library/Caches/Yarn", "Yarn global package cache."),
            ("Claude Desktop Cache", "\(home)/Library/Application Support/Claude", "Claude for Mac app caches and databases."),
            ("Cursor History Cache", "\(home)/Library/Application Support/Cursor", "Cursor editor auto-save snapshots and indexing metadata.")
        ]
        
        DispatchQueue.global(qos: .userInitiated).async {
            var scannedItems: [SweeperItem] = []
            
            for (name, path, desc) in scanTargets {
                let fm = FileManager.default
                guard fm.fileExists(atPath: path) else { continue }
                
                let size = self.getDirectorySize(atPath: path)
                if size > 0 {
                    scannedItems.append(SweeperItem(name: name, path: path, description: desc, size: size))
                }
            }
            
            DispatchQueue.main.async {
                self.items = scannedItems
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }
    
    func cleanSelected() {
        isCleaning = true
        let selected = items.filter { $0.isSelected }
        
        DispatchQueue.global(qos: .userInitiated).async {
            var freedBytes: UInt64 = 0
            let fm = FileManager.default
            
            for item in selected {
                // Safely move to Trash instead of rm -rf
                let trashURL = try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: item.path), create: true)
                
                // Let's resolve the actual User's Trash folder
                let home = self.getHomeDir()
                let trashDir = "\(home)/.Trash"
                let targetTrashPath = "\(trashDir)/\(URL(fileURLWithPath: item.path).lastPathComponent)"
                
                try? fm.removeItem(atPath: targetTrashPath) // remove collision
                do {
                    // Try to move to Trash, if fails, try to delete directly
                    try fm.moveItem(atPath: item.path, toPath: targetTrashPath)
                    freedBytes += item.size
                } catch {
                    // Fallback to direct deletion if moving to Trash fails
                    do {
                        try fm.removeItem(atPath: item.path)
                        freedBytes += item.size
                    } catch {
                        print("Failed to delete \(item.path): \(error)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let sizeStr = formatter.string(fromByteCount: Int64(freedBytes))
                self.cleanResult = "Successfully cleaned \(sizeStr) of developer caches."
                self.scan() // rescanning to update sizes
            }
        }
    }
    
    private func getDirectorySize(atPath path: String) -> UInt64 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = nil
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let parts = output.components(separatedBy: "\t")
            if let kbStr = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
               let kb = UInt64(kbStr) {
                return kb * 1024 // Convert KB to Bytes
            }
        } catch {
            print("Failed to run du: \(error)")
        }
        return 0
    }
}
