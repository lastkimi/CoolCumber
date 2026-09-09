import Foundation

public enum HistoryArchiveError: Error, Equatable, Sendable {
    case invalidArchive
    case unsupportedSchema
    case tooManyRecords
    case archiveTooLarge
}

public struct HistoryArchiveEncoding: Equatable, Sendable {
    public let records: [HistoryRecord]
    public let data: Data

    public init(records: [HistoryRecord], data: Data) {
        self.records = records
        self.data = data
    }
}

private struct HistoryArchive: Codable {
    static let currentSchemaVersion: UInt8 = 1

    let schemaVersion: UInt8
    let records: [HistoryRecord]

    init(records: [HistoryRecord]) {
        schemaVersion = Self.currentSchemaVersion
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "v"
        case records = "r"
    }
}

/// Strict codec shared by the App store and tests. It validates both the input
/// byte count and decoded entry count before data becomes trusted history.
public struct HistoryArchiveCodec: Equatable, Sendable {
    public static let defaultMaximumRecords = 9_000
    public static let defaultMaximumBytes = 32 * 1_024 * 1_024

    public let maximumRecords: Int
    public let maximumBytes: Int

    public init(
        maximumRecords: Int = HistoryArchiveCodec.defaultMaximumRecords,
        maximumBytes: Int = HistoryArchiveCodec.defaultMaximumBytes
    ) {
        self.maximumRecords = max(1, maximumRecords)
        self.maximumBytes = max(1, maximumBytes)
    }

    public func decode(_ data: Data) throws -> [HistoryRecord] {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw data.isEmpty
                ? HistoryArchiveError.invalidArchive
                : HistoryArchiveError.archiveTooLarge
        }

        let archive: HistoryArchive
        do {
            archive = try Self.decoder().decode(HistoryArchive.self, from: data)
        } catch {
            throw HistoryArchiveError.invalidArchive
        }
        guard archive.schemaVersion == HistoryArchive.currentSchemaVersion else {
            throw HistoryArchiveError.unsupportedSchema
        }
        guard archive.records.count <= maximumRecords else {
            throw HistoryArchiveError.tooManyRecords
        }
        return archive.records
    }

    public func encode(_ records: [HistoryRecord]) throws -> Data {
        guard records.count <= maximumRecords else {
            throw HistoryArchiveError.tooManyRecords
        }
        let data = try Self.encodeUnchecked(records)
        guard data.count <= maximumBytes else {
            throw HistoryArchiveError.archiveTooLarge
        }
        return data
    }

    /// Returns the longest newest suffix that fits both hard limits. It never
    /// mutates values or replaces missing metrics with defaults.
    public func encodeNewestRecordsFitting(
        _ records: [HistoryRecord]
    ) throws -> HistoryArchiveEncoding {
        let capped = Array(records.suffix(maximumRecords))
        if let data = try? encode(capped) {
            return HistoryArchiveEncoding(records: capped, data: data)
        }

        guard !capped.isEmpty else {
            throw HistoryArchiveError.archiveTooLarge
        }

        var lowerBound = 1
        var upperBound = capped.count
        var best: HistoryArchiveEncoding?
        while lowerBound <= upperBound {
            let count = lowerBound + (upperBound - lowerBound) / 2
            let candidate = Array(capped.suffix(count))
            let data = try Self.encodeUnchecked(candidate)
            if data.count <= maximumBytes {
                best = HistoryArchiveEncoding(records: candidate, data: data)
                lowerBound = count + 1
            } else {
                upperBound = count - 1
            }
        }

        guard let best else { throw HistoryArchiveError.archiveTooLarge }
        return best
    }

    private static func encodeUnchecked(_ records: [HistoryRecord]) throws -> Data {
        try encoder().encode(HistoryArchive(records: records))
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
