import Foundation

public enum HistoryAccess: String, Codable, CaseIterable, Sendable {
    case free
    case pro
}

/// Retention is deliberately tri-state. Until commerce produces definitive
/// evidence, callers preserve the longest supported archive so a transient
/// entitlement failure cannot destroy previously paid history.
public enum HistoryEntitlementAccess: String, Codable, CaseIterable, Sendable {
    case undetermined
    case free
    case pro

    public var retentionAccess: HistoryAccess {
        self == .free ? .free : .pro
    }
}

public struct HistoryRetentionPolicy: Equatable, Sendable {
    public static let freeDuration: TimeInterval = 24 * 60 * 60
    public static let proDuration: TimeInterval = 30 * 24 * 60 * 60

    public let access: HistoryAccess

    public init(access: HistoryAccess) {
        self.access = access
    }

    public var duration: TimeInterval {
        switch access {
        case .free: return Self.freeDuration
        case .pro: return Self.proDuration
        }
    }

    /// Includes both exact retention endpoints. This is a safety bound; the
    /// file codec applies its own independent hard limit as well.
    public var maximumExpectedRecordCount: Int {
        Int(duration / HistorySamplingPolicy.bucketDuration) + 1
    }

    public func applying(
        to records: [HistoryRecord],
        referenceDate: Date
    ) -> [HistoryRecord] {
        let cutoff = referenceDate.addingTimeInterval(-duration)
        let inWindow = records.filter {
            $0.capturedAt >= cutoff && $0.capturedAt <= referenceDate
        }
        let retained = HistorySamplingPolicy().normalized(inWindow)
        return Array(retained.suffix(maximumExpectedRecordCount))
    }
}

public enum HistoryInsertionAction: String, Codable, Sendable {
    case appended
    case replaced
    case ignored
}

public struct HistoryInsertionResult: Equatable, Sendable {
    public let records: [HistoryRecord]
    public let action: HistoryInsertionAction

    public init(records: [HistoryRecord], action: HistoryInsertionAction) {
        self.records = records
        self.action = action
    }
}

/// Deduplicates snapshots into fixed UTC epoch buckets, so daylight-saving and
/// locale changes never alter the five-minute cadence.
public struct HistorySamplingPolicy: Equatable, Sendable {
    public static let bucketDuration: TimeInterval = 5 * 60
    public let maximumMetricAge: TimeInterval

    public init(maximumMetricAge: TimeInterval = 90) {
        self.maximumMetricAge = maximumMetricAge.isFinite && maximumMetricAge >= 0
            ? maximumMetricAge
            : 90
    }

    public func bucketID(for date: Date) -> Int64? {
        let quotient = date.timeIntervalSince1970 / Self.bucketDuration
        guard quotient.isFinite else { return nil }
        let floored = floor(quotient)
        guard floored >= Double(Int64.min), floored <= Double(Int64.max) else {
            return nil
        }
        return Int64(floored)
    }

    public func inserting(
        _ record: HistoryRecord,
        into existingRecords: [HistoryRecord]
    ) -> HistoryInsertionResult {
        var records = normalized(existingRecords)
        guard let candidateBucket = bucketID(for: record.capturedAt) else {
            return HistoryInsertionResult(records: records, action: .ignored)
        }

        if let index = records.firstIndex(where: {
            bucketID(for: $0.capturedAt) == candidateBucket
        }) {
            let existing = records[index]
            guard prefers(record, over: existing) else {
                return HistoryInsertionResult(records: records, action: .ignored)
            }
            records[index] = record
            records.sort(by: Self.sortOrder)
            return HistoryInsertionResult(records: records, action: .replaced)
        }

        records.append(record)
        records.sort(by: Self.sortOrder)
        return HistoryInsertionResult(records: records, action: .appended)
    }

    public func normalized(_ records: [HistoryRecord]) -> [HistoryRecord] {
        let sorted = records.sorted(by: Self.sortOrder)
        var buckets: [Int64: HistoryRecord] = [:]
        for record in sorted {
            guard let bucket = bucketID(for: record.capturedAt) else { continue }
            if let current = buckets[bucket] {
                if prefers(record, over: current) {
                    buckets[bucket] = record
                }
            } else {
                buckets[bucket] = record
            }
        }
        return buckets.values.sorted(by: Self.sortOrder)
    }

    private func prefers(_ candidate: HistoryRecord, over current: HistoryRecord) -> Bool {
        let candidateCount = candidate.usableValueCount(maximumAge: maximumMetricAge)
        let currentCount = current.usableValueCount(maximumAge: maximumMetricAge)
        if candidateCount != currentCount {
            return candidateCount > currentCount
        }
        if candidate.capturedAt != current.capturedAt {
            return candidate.capturedAt > current.capturedAt
        }
        if candidate.sequence != current.sequence {
            return candidate.sequence > current.sequence
        }
        return false
    }

    private static func sortOrder(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        if lhs.capturedAt != rhs.capturedAt {
            return lhs.capturedAt < rhs.capturedAt
        }
        return lhs.sequence < rhs.sequence
    }
}
