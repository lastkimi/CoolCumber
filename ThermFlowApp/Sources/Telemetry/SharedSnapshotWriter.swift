import Foundation
import ThermFlowCore
import WidgetKit

final class SharedSnapshotWriter {
    static let appGroupIdentifier = "BSKR6CQ765.com.slmcamp.CoolCumber"
    static let relativeDirectory = "Library/Application Support/CoolCumber/Telemetry"
    static let fileName = "system-snapshot-v1.json"
    static let maximumEncodedSnapshotSize = 1_048_576
    static let maximumFanCount = 8

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
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) != nil
    }

    func write(_ snapshot: SystemSnapshot, at date: Date) throws {
        guard snapshot.schemaVersion == SystemSnapshot.currentSchemaVersion,
              snapshot.fans.count <= Self.maximumFanCount else {
            throw SharedSnapshotError.invalidSnapshot
        }
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            throw SharedSnapshotError.appGroupUnavailable
        }

        let directoryURL = containerURL.appendingPathComponent(
            Self.relativeDirectory,
            isDirectory: true
        )
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

        if lastWidgetReloadAt.map({ date.timeIntervalSince($0) >= 60 }) ?? true {
            lastWidgetReloadAt = date
            WidgetCenter.shared.reloadTimelines(ofKind: "CoolCumberWidget")
        }
    }
}

enum SharedSnapshotError: Error {
    case appGroupUnavailable
    case invalidSnapshot
}
