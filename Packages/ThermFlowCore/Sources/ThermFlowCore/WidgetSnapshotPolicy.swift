import Foundation

public enum WidgetSnapshotState: String, Codable, Equatable, Sendable {
    case current
    case stale
    case unavailable
}

/// Classifies the exact shared snapshot shown by the Widget. A recently written
/// file is not enough to claim current data: the snapshot and at least one
/// Widget-visible metric must both be fresh and valid.
public struct WidgetSnapshotPolicy: Equatable, Sendable {
    public static let defaultMaximumSnapshotAge: TimeInterval = 90
    public static let defaultMaximumFanCount = 8

    public let maximumSnapshotAge: TimeInterval
    public let maximumFanCount: Int

    public init(
        maximumSnapshotAge: TimeInterval = Self.defaultMaximumSnapshotAge,
        maximumFanCount: Int = Self.defaultMaximumFanCount
    ) {
        self.maximumSnapshotAge = maximumSnapshotAge.isFinite && maximumSnapshotAge >= 0
            ? maximumSnapshotAge
            : Self.defaultMaximumSnapshotAge
        self.maximumFanCount = max(0, maximumFanCount)
    }

    public func state(
        for snapshot: SystemSnapshot?,
        at evaluationDate: Date
    ) -> WidgetSnapshotState {
        guard let snapshot,
              snapshot.schemaVersion == SystemSnapshot.currentSchemaVersion,
              snapshot.fans.count <= maximumFanCount else {
            return .unavailable
        }

        let snapshotAge = evaluationDate.timeIntervalSince(snapshot.capturedAt)
        guard snapshotAge.isFinite, snapshotAge >= 0 else {
            return .unavailable
        }
        guard snapshotAge <= maximumSnapshotAge else {
            return .stale
        }

        return containsUsableMetric(snapshot, at: evaluationDate)
            ? .current
            : .unavailable
    }

    private func containsUsableMetric(
        _ snapshot: SystemSnapshot,
        at evaluationDate: Date
    ) -> Bool {
        if snapshot.thermal.cpuTemperature.usableValue(
            at: evaluationDate,
            maximumAge: maximumSnapshotAge
        ) != nil {
            return true
        }
        if snapshot.thermal.pressure.usableValue(
            at: evaluationDate,
            maximumAge: maximumSnapshotAge
        ) != nil {
            return true
        }
        if snapshot.memory.usage.usableValue(
            at: evaluationDate,
            maximumAge: maximumSnapshotAge
        ) != nil {
            return true
        }
        return snapshot.fans.first?.currentSpeed.usableValue(
            at: evaluationDate,
            maximumAge: maximumSnapshotAge
        ) != nil
    }
}
