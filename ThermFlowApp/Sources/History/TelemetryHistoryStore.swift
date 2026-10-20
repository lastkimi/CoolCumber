import Combine
import Foundation
import ThermFlowCore

typealias TelemetryHistoryStoreStatus = HistoryPersistenceStatus

/// Local-only history persistence. Callers provide the current Pro entitlement;
/// this type deliberately has no StoreKit or UI dependency.
final class TelemetryHistoryStore {
    static let appGroupIdentifier = "BSKR6CQ765.com.slmcamp.CoolCumber"
    static let relativeDirectory = "Library/Application Support/CoolCumber/History"
    static let fileName = "telemetry-history-v1.json"

    private let repository: HistoryFileRepository
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

    convenience init(
        daemonManager: DaemonManager = .shared,
        initialAccess: HistoryEntitlementAccess = .undetermined,
        fileManager: FileManager = .default,
        maximumRecords: Int = HistoryArchiveCodec.defaultMaximumRecords,
        maximumBytes: Int = HistoryArchiveCodec.defaultMaximumBytes
    ) {
        self.init(
            snapshotPublisher: daemonManager.$systemSnapshot.eraseToAnyPublisher(),
            initialAccess: initialAccess,
            fileManager: fileManager,
            historyFileURL: Self.defaultHistoryFileURL(using: fileManager),
            referenceDate: Date(),
            maximumRecords: maximumRecords,
            maximumBytes: maximumBytes
        )
    }

    /// Explicit persistence and publisher injection keeps disk boundaries and
    /// retention transitions deterministic in unit tests while production uses
    /// the App Group convenience initializer above.
    init(
        snapshotPublisher: AnyPublisher<SystemSnapshot, Never>,
        initialAccess: HistoryEntitlementAccess,
        fileManager: FileManager,
        historyFileURL: URL?,
        referenceDate: Date,
        maximumRecords: Int = HistoryArchiveCodec.defaultMaximumRecords,
        maximumBytes: Int = HistoryArchiveCodec.defaultMaximumBytes
    ) {
        requestedAccess = initialAccess
        repository = HistoryFileRepository(
            fileURL: historyFileURL,
            fileManager: fileManager,
            maximumRecords: maximumRecords,
            maximumBytes: maximumBytes
        )
        sampler = HistorySamplingPolicy()
        csvEncoder = HistoryCSVEncoder()

        loadExistingHistory(referenceDate: referenceDate)

        snapshotCancellable = snapshotPublisher
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
            let result = self.repository.remove(existingRecords: self.records)
            self.setState(records: result.records, status: result.status)
        }
    }

    private var retentionPolicy: HistoryRetentionPolicy {
        HistoryRetentionPolicy(access: requestedAccess.retentionAccess)
    }

    private func loadExistingHistory(referenceDate: Date) {
        let result = repository.load(
            access: requestedAccess,
            referenceDate: referenceDate
        )
        setState(records: result.records, status: result.status)
    }

    private func ingest(_ record: HistoryRecord, referenceDate: Date) {
        dispatchPrecondition(condition: .onQueue(workerQueue))
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
        dispatchPrecondition(condition: .onQueue(workerQueue))
        let result = repository.persist(records)
        setState(records: result.records, status: result.status)
    }

    private static func defaultHistoryFileURL(using fileManager: FileManager) -> URL? {
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
