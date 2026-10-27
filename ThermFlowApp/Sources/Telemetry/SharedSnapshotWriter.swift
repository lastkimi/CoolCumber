import Foundation
import ThermFlowCore
import WidgetKit

final class SharedSnapshotWriter {
    static let appGroupIdentifier = "BSKR6CQ765.com.slmcamp.CoolCumber"
    static let relativeDirectory = "Library/Application Support/CoolCumber/Telemetry"
    static let fileName = "system-snapshot-v1.json"
    static let maximumEncodedSnapshotSize = 1_048_576
    static let maximumFanCount = WidgetSnapshotPolicy.defaultMaximumFanCount

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private var lastWidgetReloadAt: Date?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    var canAccessContainer: Bool {
        ProductStoragePaths.directory("Telemetry", using: fileManager) != nil
    }

    func write(_ snapshot: SystemSnapshot, at date: Date) throws {
        guard snapshot.schemaVersion == SystemSnapshot.currentSchemaVersion,
              snapshot.fans.count <= Self.maximumFanCount else {
            throw SharedSnapshotError.invalidSnapshot
        }
        guard let directoryURL = ProductStoragePaths.directory("Telemetry", using: fileManager) else {
            throw SharedSnapshotError.appGroupUnavailable
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let destinationURL = directoryURL.appendingPathComponent(Self.fileName)
        let data = try encoder.encode(snapshot)
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedSnapshotSize else {
            throw SharedSnapshotError.invalidSnapshot
        }
        try data.write(to: destinationURL, options: .atomic)

        if !ProductStoragePaths.usesIsolatedStorage,
           lastWidgetReloadAt.map({ date.timeIntervalSince($0) >= 60 }) ?? true {
            lastWidgetReloadAt = date
            WidgetCenter.shared.reloadTimelines(ofKind: "CoolCumberWidget")
        }
    }
}

enum SharedSnapshotError: Error {
    case appGroupUnavailable
    case invalidSnapshot
}
