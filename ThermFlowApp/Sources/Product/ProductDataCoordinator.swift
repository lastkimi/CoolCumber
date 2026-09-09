import Combine
import Foundation
import ThermFlowCore

/// Connects trusted snapshots to local history and opt-in health alerts. It is
/// intentionally UI-facing: the persistence and alert engines remain free of
/// StoreKit dependencies and receive entitlement decisions from here.
@MainActor
final class ProductDataCoordinator: ObservableObject {
    static let shared = ProductDataCoordinator()

    @Published private(set) var records: [HistoryRecord]
    @Published private(set) var historyStatus: TelemetryHistoryStoreStatus
    @Published private(set) var alertConfiguration: HealthAlertConfiguration = .default
    @Published private(set) var alertAuthorization: HealthAlertAuthorizationState = .notDetermined
    @Published private(set) var alertMessage: String?

    private let commerce = PurchaseController.shared
    private let historyStore: TelemetryHistoryStore
    private let alertController = TrustedHealthAlertController.shared
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {
        // Loading/unavailable commerce state must never destructively collapse
        // a previously paid 30-day archive to the Free window.
        historyStore = TelemetryHistoryStore(initialAccess: .undetermined)
        records = historyStore.records
        historyStatus = historyStore.status
    }

    var historyAccess: HistoryAccess {
        commerce.isProUnlocked ? .pro : .free
    }

    var canExport: Bool {
        commerce.allows(.historyExport)
    }

    var canConfigureAlerts: Bool {
        commerce.allows(.advancedAlerts)
    }

    /// The persisted opt-in reflects the user's choice. Entitlement controls
    /// whether that choice is effective without overwriting it.
    var alertsAreDesired: Bool {
        alertConfiguration.isEnabled
    }

    var alertsAreEffectivelyEnabled: Bool {
        canConfigureAlerts && alertsAreDesired
    }

    var isDirectEdition: Bool {
        DistributionEdition.current == .direct
    }

    func start() {
        guard !started else { return }
        started = true

        commerce.$entitlement
            .receive(on: RunLoop.main)
            .sink { [weak self] entitlement in
                guard let self else { return }
                switch entitlement {
                case .betaUnlocked, .pro:
                    self.historyStore.updateAccess(.pro)
                case .free:
                    self.historyStore.updateAccess(.free)
                case .loading, .unavailable:
                    // Hide paid features while evidence is unresolved, but do
                    // not erase paid history or the user's alert preference.
                    self.historyStore.updateAccess(.undetermined)
                }
            }
            .store(in: &cancellables)

        historyStore.stateChanges
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.refreshHistoryState()
            }
            .store(in: &cancellables)

        DaemonManager.shared.$systemSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                guard self.alertsAreEffectivelyEnabled else { return }

                Task {
                    _ = await self.alertController.evaluate(snapshot)
                }
            }
            .store(in: &cancellables)

        Task {
            await refreshAlertState()
        }
        refreshHistoryState()
    }

    func setAlertsEnabled(_ enabled: Bool) {
        guard !enabled || canConfigureAlerts else {
            alertMessage = productLocalized(
                "Health alerts are included with Pro.",
                "健康提醒包含在 Pro 中。"
            )
            return
        }

        Task {
            let result = await alertController.setEnabled(enabled)
            await refreshAlertState()
            switch result {
            case .enabled:
                alertMessage = productLocalized(
                    "Local health alerts are enabled.",
                    "本地健康提醒已启用。"
                )
            case .disabled:
                alertMessage = productLocalized(
                    "Local health alerts are off.",
                    "本地健康提醒已关闭。"
                )
            case .denied:
                alertMessage = productLocalized(
                    "Notifications are denied in System Settings.",
                    "系统设置已拒绝通知权限。"
                )
            case .failed:
                alertMessage = productLocalized(
                    "Notification permission could not be updated.",
                    "无法更新通知权限。"
                )
            }
        }
    }

    func setTemperatureThreshold(_ threshold: Double) {
        guard canConfigureAlerts else { return }
        Task {
            do {
                _ = try await alertController.setTemperatureThreshold(threshold)
                await refreshAlertState()
                alertMessage = productLocalized(
                    "Temperature threshold updated.",
                    "温度阈值已更新。"
                )
            } catch {
                alertMessage = productLocalized(
                    "Choose a threshold between 60°C and 100°C.",
                    "请选择 60°C 到 100°C 之间的阈值。"
                )
            }
        }
    }

    func csvDataForExport() -> Data? {
        guard canExport else { return nil }
        return historyStore.csvData()
    }

    func removeAllHistory() {
        historyStore.removeAllHistory()
    }

    func clearAlertMessage() {
        alertMessage = nil
    }

    private func refreshHistoryState() {
        records = historyStore.records
        historyStatus = historyStore.status
    }

    private func refreshAlertState() async {
        alertConfiguration = await alertController.currentConfiguration()
        alertAuthorization = await alertController.authorizationState()
    }
}
