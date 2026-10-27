import Combine
import Foundation
import ThermFlowCore

/// Owns one explicit, read-only comparison document. It does not change the
/// existing telemetry history, receipts, helper, process or hardware state.
@MainActor
final class WorkloadCheckController: ObservableObject {
    static let shared = WorkloadCheckController()
    static let fileName = "workload-check-v1.json"
    static let retentionDuration: TimeInterval = 24 * 60 * 60

    @Published private(set) var check: WorkloadCheck?
    @Published private(set) var persistenceStatus: WorkloadCheckPersistenceStatus = .ready
    @Published private(set) var message: String?
    @Published private(set) var now = Date()
    @Published private(set) var isSaving = false

    private let repository: WorkloadCheckFileRepository
    private let worker = DispatchQueue(label: "com.slmcamp.CoolCumber.workload-check", qos: .utility)
    private var cancellable: AnyCancellable?
    private var timer: Timer?
    private var started = false
    private var saveGeneration: UInt64 = 0

    private init() {
        repository = WorkloadCheckFileRepository(fileURL: ProductStoragePaths.historyFile(Self.fileName))
        let result = repository.load(at: Date())
        persistenceStatus = result.status
        check = result.check
        if var interrupted = check, interrupted.isRecording {
            interrupted.interrupt()
            check = interrupted
            message = productLocalized("The last check was interrupted; its real observations were kept.", "上次检查已中断，真实观察数据已保留。")
            persist(interrupted)
        }
        expireSavedCheckIfNeeded()
    }

    func start() {
        guard !started else { return }
        started = true
        cancellable = DaemonManager.shared.$systemSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in self?.accept(snapshot) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit { timer?.invalidate() }

    var elapsed: TimeInterval { check.map { max(0, ( $0.endedAt ?? now ).timeIntervalSince($0.startedAt)) } ?? 0 }
    var currentPhaseSampleCount: Int {
        guard let check else { return 0 }
        return check.points.filter { $0.phase == check.phase && $0.hasUsableValue }.count
    }

    func begin(note: String, replacingConfirmed: Bool) {
        guard check == nil || replacingConfirmed else {
            message = productLocalized("Confirm before replacing the latest check.", "替换最近检查前需要确认。")
            return
        }
        do {
            start()
            let new = try WorkloadCheck(note: note, channel: DaemonManager.shared.systemSnapshot.channel, startedAt: Date())
            check = new
            now = Date()
            message = nil
            persist(new)
        } catch { show(error) }
    }

    func advance() {
        guard var updated = check else { return }
        do {
            if updated.phase == .baseline { try updated.beginComparison(at: Date()) }
            else if updated.phase == .comparison { try updated.finish(at: Date()) }
            else { return }
            check = updated
            message = nil
            persist(updated)
        } catch { show(error) }
    }

    func stop() {
        guard var updated = check, updated.isRecording else { return }
        updated.interrupt()
        check = updated
        message = productLocalized("Stopped without inventing missing observations.", "已停止；不会补造缺失的观察数据。")
        persist(updated)
    }

    /// Called only after the user confirms this named document's removal.
    func clearConfirmed() {
        saveGeneration &+= 1
        let generation = saveGeneration
        isSaving = false
        check = nil
        message = nil
        let repository = repository
        worker.async { [weak self] in
            let result = repository.remove()
            Task { @MainActor in
                guard self?.saveGeneration == generation, self?.check == nil else { return }
                self?.persistenceStatus = result
            }
        }
    }

    /// Explicitly completed documents must finish their bounded local write
    /// before normal app termination. No network operation is queued here.
    func flushPendingWrites() { worker.sync {} }

    func csvDataIfAllowed() -> Data? {
        guard PurchaseController.shared.allows(.historyExport), let check, !check.points.isEmpty else { return nil }
        return WorkloadCheckCSVEncoder().data(from: check)
    }

    private func accept(_ snapshot: SystemSnapshot) {
        guard var updated = check, updated.isRecording else { return }
        let before = updated
        _ = updated.ingest(snapshot, at: Date())
        guard updated != before else { return }
        check = updated
        persist(updated)
    }

    private func tick() {
        now = Date()
        if let check, check.isRecording,
           now < check.startedAt || check.points.last.map({ now < $0.capturedAt }) == true {
            stop()
            message = productLocalized("The system clock moved backwards. The check stopped; previous saved evidence is preserved.",
                                       "系统时间向后变化，检查已停止；原有保存数据保留。")
        }
        if let check, check.isRecording, now.timeIntervalSince(check.startedAt) > WorkloadCheck.maximumDuration {
            stop()
            message = productLocalized("The five-minute limit was reached. Only collected readings were kept.", "已达到五分钟上限，仅保留实际采集的读数。")
        }
        expireSavedCheckIfNeeded()
    }

    private func expireSavedCheckIfNeeded() {
        guard let saved = check, !saved.isRecording,
              Date().timeIntervalSince(saved.startedAt) > Self.retentionDuration else { return }
        if persistenceStatus == .ready && !isSaving {
            clearConfirmed()
        } else {
            // A memory-only check expiring cannot authorize deletion of an
            // older unreadable or unsuccessfully replaced saved document.
            check = nil
        }
        message = productLocalized("The latest check's 24-hour retention window ended. Continuous history is managed separately.",
                                   "最近检查的 24 小时保留期已结束；连续历史在“历史”中单独管理。")
    }

    private func persist(_ value: WorkloadCheck) {
        saveGeneration &+= 1
        let generation = saveGeneration
        isSaving = true
        let repository = repository
        worker.async { [weak self] in
            let result = repository.persist(value, at: Date())
            Task { @MainActor in
                guard self?.check?.id == value.id, self?.saveGeneration == generation else { return }
                self?.persistenceStatus = result.status
                self?.isSaving = false
            }
        }
    }

    private func show(_ error: Error) {
        if error as? WorkloadCheckError == .invalidNote {
            message = productLocalized("Use up to 80 characters without line breaks for the optional note.", "背景说明请使用最多 80 字符，且不要换行。")
        } else if error as? WorkloadCheckError == .insufficientSamples {
            message = productLocalized("Each phase needs three fresh observations spanning at least 20 seconds.", "每阶段至少需要三个新鲜观察样本，并覆盖至少 20 秒。")
        } else {
            message = productLocalized("The check could not change phase. Keep the existing data and try a new check.", "无法切换检查阶段；现有数据保留，可重新开始检查。")
        }
    }
}
