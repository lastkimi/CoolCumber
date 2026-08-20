import Foundation

struct SweeperItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let path: String
    let description: String
    var size: UInt64 // Bytes
    // Cleanup is always opt-in. A scan must never pre-authorize deletion.
    var isSelected: Bool = false
    
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

    private var allowedTargets: [(name: String, path: String, description: String)] {
        let home = getHomeDir()
        return [
            ("Xcode DerivedData", "\(home)/Library/Developer/Xcode/DerivedData", "Build products that Xcode can regenerate."),
            ("Docker Cache", "\(home)/Library/Caches/com.docker.docker", "Cached Docker Desktop data in the user cache directory."),
            ("npm Package Cache", "\(home)/.npm/_cacache", "Downloaded npm package cache."),
            ("Yarn Cache", "\(home)/Library/Caches/Yarn", "Downloaded Yarn package cache.")
        ]
    }
    
    func getHomeDir() -> String {
        return NSHomeDirectory()
    }
    
    func scan() {
        isScanning = true
        cleanResult = nil
        
        let scanTargets = allowedTargets
        
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
        let selected = items.filter { $0.isSelected }
        guard !selected.isEmpty else {
            cleanResult = "Select one or more regenerable caches to move to Trash."
            return
        }

        isCleaning = true
        let allowedPaths = Set(allowedTargets.map { canonicalPath($0.path) })
        
        DispatchQueue.global(qos: .userInitiated).async {
            var freedBytes: UInt64 = 0
            let fm = FileManager.default
            var failures: [String] = []
            
            for item in selected {
                let canonicalItemPath = self.canonicalPath(item.path)
                guard allowedPaths.contains(canonicalItemPath) else {
                    failures.append("\(item.name): path is not an approved cache target")
                    continue
                }

                do {
                    // FileManager chooses a collision-safe Trash destination. There is
                    // intentionally no permanent-delete fallback.
                    try fm.trashItem(at: URL(fileURLWithPath: canonicalItemPath), resultingItemURL: nil)
                    freedBytes += item.size
                } catch {
                    failures.append("\(item.name): \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.isCleaning = false
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let sizeStr = formatter.string(fromByteCount: Int64(freedBytes))
                if failures.isEmpty {
                    self.cleanResult = "Moved \(sizeStr) of regenerable caches to Trash."
                } else {
                    self.cleanResult = "Moved \(sizeStr) to Trash. Skipped \(failures.count) item(s): \(failures.joined(separator: "; "))"
                }
                self.scan() // rescanning to update sizes
            }
        }
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
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
