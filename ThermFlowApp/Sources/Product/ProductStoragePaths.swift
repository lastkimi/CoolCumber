import Foundation

/// Capture/test isolation changes storage only, never readings or access. An
/// invalid requested scope fails closed instead of falling back to user data.
enum ProductStoragePaths {
    static let groupIdentifier = "BSKR6CQ765.com.slmcamp.CoolCumber"
    private static let ephemeralScope = UUID()
    private static var requestedScopes: [String] {
        ProcessInfo.processInfo.arguments.filter { $0.hasPrefix("--qa-storage-scope") }
    }
    static var usesIsolatedStorage: Bool { !requestedScopes.isEmpty }

    static var preferences: UserDefaults {
        guard usesIsolatedStorage else { return .standard }
        let scope = validatedScope ?? ephemeralScope
        guard let defaults = UserDefaults(suiteName: "com.slmcamp.CoolCumber.QA." + scope.uuidString) else {
            preconditionFailure("Isolated preferences unavailable; refusing to fall back to user preferences")
        }
        return defaults
    }

    private static var validatedScope: UUID? {
        let requested = requestedScopes
        guard requested.count == 1, requested[0].hasPrefix("--qa-storage-scope="),
              let raw = requested[0].split(separator: "=", maxSplits: 1).last else { return nil }
        return UUID(uuidString: String(raw))
    }

    static func historyFile(_ name: String, using fileManager: FileManager = .default) -> URL? {
        directory("History", using: fileManager)?.appendingPathComponent(name)
    }

    static func directory(_ component: String, using fileManager: FileManager = .default) -> URL? {
        guard let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else { return nil }
        var directory = group.appendingPathComponent("Library/Application Support/CoolCumber", isDirectory: true)
        if usesIsolatedStorage {
            guard let scope = validatedScope else { return nil }
            directory = directory.appendingPathComponent("QA", isDirectory: true)
                .appendingPathComponent(scope.uuidString, isDirectory: true)
        }
        return directory.appendingPathComponent(component, isDirectory: true)
    }
}
