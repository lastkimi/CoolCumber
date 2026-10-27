import Foundation

public enum HistoryPersistenceStatus: String, Equatable, Sendable {
    case ready
    case appGroupUnavailable
    case corruptArchive
    case readFailed
    case writeFailed
    case limitsExceeded
}

public struct HistoryPersistenceResult: Equatable, Sendable {
    public let records: [HistoryRecord]
    public let status: HistoryPersistenceStatus

    public init(records: [HistoryRecord], status: HistoryPersistenceStatus) {
        self.records = records
        self.status = status
    }
}

/// Synchronous bounded file adapter. The app owns serialization; this type owns
/// the invariant that no unbounded read or unvalidated archive reaches memory.
public struct HistoryFileRepository {
    public let fileURL: URL?
    public let codec: HistoryArchiveCodec

    private let fileManager: FileManager

    public init(
        fileURL: URL?,
        fileManager: FileManager = .default,
        maximumRecords: Int = HistoryArchiveCodec.defaultMaximumRecords,
        maximumBytes: Int = HistoryArchiveCodec.defaultMaximumBytes
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        codec = HistoryArchiveCodec(
            maximumRecords: maximumRecords,
            maximumBytes: maximumBytes
        )
    }

    public func load(
        access: HistoryEntitlementAccess,
        referenceDate: Date
    ) -> HistoryPersistenceResult {
        guard let fileURL else {
            return HistoryPersistenceResult(records: [], status: .appGroupUnavailable)
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return HistoryPersistenceResult(records: [], status: .ready)
        }

        do {
            let decoded = try codec.decode(readBoundedArchive(from: fileURL))
            let retained = HistoryRetentionPolicy(
                access: access.retentionAccess
            ).applying(to: decoded, referenceDate: referenceDate)
            return HistoryPersistenceResult(records: retained, status: .ready)
        } catch let error as HistoryArchiveError {
            let status: HistoryPersistenceStatus = error == .archiveTooLarge
                || error == .tooManyRecords
                ? .limitsExceeded
                : .corruptArchive
            return HistoryPersistenceResult(records: [], status: status)
        } catch {
            return HistoryPersistenceResult(records: [], status: .readFailed)
        }
    }

    public func persist(_ records: [HistoryRecord]) -> HistoryPersistenceResult {
        guard let fileURL else {
            return HistoryPersistenceResult(
                records: records,
                status: .appGroupUnavailable
            )
        }

        do {
            // A failed load must not be followed by a successful-looking write
            // that silently destroys the original unsupported/corrupt archive.
            // Explicit remove remains available as the user's recovery action.
            if fileManager.fileExists(atPath: fileURL.path) {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    return HistoryPersistenceResult(records: records, status: .corruptArchive)
                }
                do {
                    _ = try codec.decode(readBoundedArchive(from: fileURL))
                } catch let error as HistoryArchiveError {
                    let status: HistoryPersistenceStatus = error == .archiveTooLarge || error == .tooManyRecords ? .limitsExceeded : .corruptArchive
                    return HistoryPersistenceResult(records: records, status: status)
                } catch {
                    return HistoryPersistenceResult(records: records, status: .readFailed)
                }
            }
            let encoding = try codec.encodeNewestRecordsFitting(records)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoding.data.write(to: fileURL, options: .atomic)
            return HistoryPersistenceResult(records: encoding.records, status: .ready)
        } catch let error as HistoryArchiveError {
            let status: HistoryPersistenceStatus = error == .archiveTooLarge
                || error == .tooManyRecords
                ? .limitsExceeded
                : .writeFailed
            return HistoryPersistenceResult(records: records, status: status)
        } catch {
            return HistoryPersistenceResult(records: records, status: .writeFailed)
        }
    }

    public func remove(existingRecords: [HistoryRecord]) -> HistoryPersistenceResult {
        guard let fileURL else {
            return HistoryPersistenceResult(records: [], status: .appGroupUnavailable)
        }
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            return HistoryPersistenceResult(records: [], status: .ready)
        } catch {
            return HistoryPersistenceResult(
                records: existingRecords,
                status: .writeFailed
            )
        }
    }

    private func readBoundedArchive(from fileURL: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: codec.maximumBytes + 1),
              !data.isEmpty else {
            throw HistoryArchiveError.invalidArchive
        }
        guard data.count <= codec.maximumBytes else {
            throw HistoryArchiveError.archiveTooLarge
        }
        return data
    }
}
