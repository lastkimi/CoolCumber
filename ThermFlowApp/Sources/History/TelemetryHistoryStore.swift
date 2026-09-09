import Combine
import Foundation
import ThermFlowCore

enum TelemetryHistoryStoreStatus: String, Equatable {
    case ready
    case appGroupUnavailable
    case corruptArchive
    case readFailed
    case writeFailed
    case limitsExceeded
}

/// Local-only history persistence. Callers provide the current Pro entitlement;
/// this type deliberately has no StoreKit or UI dependency.
final class TelemetryHistoryStore {
    static let appGroupIdentifier = "BSKR6CQ765.com.slmcamp.CoolCumber"
    static let relativeDirectory = "Library/Application Support/CoolCumber/History"
    static let fileName = "telemetry-history-v1.json"

    private let fileManager: FileManager
    private let codec: HistoryArchiveCodec
    private let sampler: HistorySamplingPolicy
    private let csvEncoder: HistoryCSVEncoder
    private let workerQueue = DispatchQueue(
        label: "com.slmcamp.CoolCumber.telemetry-history",
        qos: .utility
    )
    private let stateLock = NSLock()

    private var snapshotCancellable: AnyCancellable?
    private var storedRecords: [HistoryRecord] = []
    private var storedStatus: TelemetryHistoryStoreStatus = .ready
    private var requestedAccess: HistoryEntitlementAccess
    private let stateDidChange = PassthroughSubject<Void, Never>()

    init(
        daemonManager: DaemonManager = .shared,
        initialAccess: HistoryEntitlementAccess = .undetermined,
        fileManager: FileManager = .default,
        maximumRecords: Int = HistoryArchiveCodec.defaultMaximumRecords,
        maximumBytes: Int = HistoryArchiveCodec.defaultMaximumBytes
    ) {
        self.fileManager = fileManager
        requestedAccess = initialAccess
        codec = HistoryArchiveCodec(
            maximumRecords: maximumRecords,
            maximumBytes: maximumBytes
        )
        sampler = HistorySamplingPolicy()
        csvEncoder = HistoryCSVEncoder()

        loadExistingHistory(referenceDate: Date())

        snapshotCancellable = daemonManager.$systemSnapshot
            .receive(on: workerQueue)
            .throttle(
                for: .seconds(Int(HistorySamplingPolicy.bucketDuration)),
                scheduler: workerQueue,
                latest: true
            )
            .sink { [weak self] snapshot in
                guard let record = HistoryRecord(snapshot: snapshot) else { return }
                self?.ingest(record, referenceDate: Date())
            }
    }

    deinit {
        snapshotCancellable?.cancel()
    }

    var status: TelemetryHistoryStoreStatus {
        withStateLock { storedStatus }
    }

    var records: [HistoryRecord] {
        withStateLock { storedRecords }
    }

    var stateChanges: AnyPublisher<Void, Never> {
        stateDidChange.eraseToAnyPublisher()
    }

    /// Re-evaluates retention after a definitive entitlement change. An
    /// undetermined state preserves the existing access decision and archive.
    /// A confirmed Free decision trims and persists immediately.
    func updateAccess(
        _ access: HistoryEntitlementAccess,
        referenceDate: Date = Date()
    ) {
        workerQueue.async { [weak self] in
            guard let self else { return }
            guard access != .undetermined else { return }
            self.requestedAccess = access
            let retained = self.retentionPolicy.applying(
                to: self.records,
                referenceDate: referenceDate
            )
            guard retained != self.records else { return }
            self.persist(retained)
        }
    }

    /// UTF-8 RFC 4180 data. Unavailable or stale measurements are blank; no
    /// default values are introduced during export.
    func csvData() -> Data {
        csvEncoder.data(from: records)
    }

    /// Removes the local archive and in-memory records. The operation is
    /// serialized with ingestion so a concurrent snapshot cannot resurrect an
    /// older copy of the file.
    func removeAllHistory() {
        workerQueue.async { [weak self] in
            guard let self else { return }
            guard let fileURL = self.historyFileURL else {
                self.setState(records: [], status: .appGroupUnavailable)
                return
            }

            do {
                if self.fileManager.fileExists(atPath: fileURL.path) {
                    try self.fileManager.removeItem(at: fileURL)
                }
                self.setState(records: [], status: .ready)
            } catch {
                self.setState(records: self.records, status: .writeFailed)
            }
        }
    }

    private var retentionPolicy: HistoryRetentionPolicy {
        HistoryRetentionPolicy(access: requestedAccess.retentionAccess)
    }

    private func loadExistingHistory(referenceDate: Date) {
        guard let fileURL = historyFileURL else {
            setState(records: [], status: .appGroupUnavailable)
            return
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            setState(records: [], status: .ready)
            return
        }

        do {
            let data = try readBoundedArchive(from: fileURL)
            let decoded = try codec.decode(data)
            let retained = retentionPolicy.applying(
                to: decoded,
                referenceDate: referenceDate
            )
            setState(records: retained, status: .ready)
        } catch let error as HistoryArchiveError {
            let status: TelemetryHistoryStoreStatus = error == .archiveTooLarge
                || error == .tooManyRecords
                ? .limitsExceeded
                : .corruptArchive
            setState(records: [], status: status)
        } catch {
            setState(records: [], status: .readFailed)
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

    private func ingest(_ record: HistoryRecord, referenceDate: Date) {
        guard record.usableValueCount(maximumAge: sampler.maximumMetricAge) > 0 else {
            return
        }
        let previous = records
        let insertion = sampler.inserting(record, into: previous)
        let retained = retentionPolicy.applying(
            to: insertion.records,
            referenceDate: referenceDate
        )
        guard retained != previous else { return }
        persist(retained)
    }

    private func persist(_ records: [HistoryRecord]) {
        guard let fileURL = historyFileURL else {
            setState(records: records, status: .appGroupUnavailable)
            return
        }

        do {
            let encoding = try codec.encodeNewestRecordsFitting(records)
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try encoding.data.write(to: fileURL, options: .atomic)
            setState(records: encoding.records, status: .ready)
        } catch let error as HistoryArchiveError {
            let status: TelemetryHistoryStoreStatus = error == .archiveTooLarge
                || error == .tooManyRecords
                ? .limitsExceeded
                : .writeFailed
            setState(records: records, status: status)
        } catch {
            setState(records: records, status: .writeFailed)
        }
    }

    private var historyFileURL: URL? {
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        )?
        .appendingPathComponent(Self.relativeDirectory, isDirectory: true)
        .appendingPathComponent(Self.fileName, isDirectory: false)
    }

    private func setState(
        records: [HistoryRecord],
        status: TelemetryHistoryStoreStatus
    ) {
        withStateLock {
            storedRecords = records
            storedStatus = status
        }
        stateDidChange.send(())
    }

    @discardableResult
    private func withStateLock<Result>(_ operation: () -> Result) -> Result {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operation()
    }
}
