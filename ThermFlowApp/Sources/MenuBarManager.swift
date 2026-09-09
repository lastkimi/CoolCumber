import AppKit
import SwiftUI
import Combine
import ThermFlowCore

// MARK: - Product UI state

/// A presentation-safe metric state. The UI never substitutes a fabricated
/// number when a source is loading, stale, unsupported, or disconnected.
enum ProductMetricState: Equatable {
    case loading
    case available(value: String, source: String, sampledAt: Date)
    case stale(value: String, source: String, sampledAt: Date)
    case unavailable(
        reason: String,
        source: String,
        observedAt: Date,
        isStale: Bool
    )

    var displayedValue: String {
        switch self {
        case .loading:
            return "…"
        case let .available(value, _, _), let .stale(value, _, _):
            return value
        case .unavailable:
            return "—"
        }
    }

    var sampledAt: Date? {
        switch self {
        case let .available(_, _, sampledAt), let .stale(_, _, sampledAt):
            return sampledAt
        case let .unavailable(_, _, observedAt, _):
            return observedAt
        case .loading:
            return nil
        }
    }

    var availableSampleDate: Date? {
        switch self {
        case let .available(_, _, sampledAt), let .stale(_, _, sampledAt):
            return sampledAt
        case .loading, .unavailable:
            return nil
        }
    }

    var supportingText: String {
        switch self {
        case .loading:
            return productLocalized("Waiting for a trusted reading", "正在等待可信读数")
        case let .available(_, source, sampledAt):
            return "\(source) · \(ProductDateFormatter.time.string(from: sampledAt))"
        case let .stale(_, source, sampledAt):
            return productLocalized(
                "Stale · \(source) · \(ProductDateFormatter.time.string(from: sampledAt))",
                "数据已过期 · \(source) · \(ProductDateFormatter.time.string(from: sampledAt))"
            )
        case let .unavailable(reason, source, observedAt, isStale):
            let status = isStale
                ? productLocalized("Stale unavailable state", "不可用状态已过期")
                : productLocalized("Unavailable", "不可用")
            return "\(status) · \(reason) · \(source) · \(ProductDateFormatter.time.string(from: observedAt))"
        }
    }
}

enum ProductMenuBarDisplayMode: String, CaseIterable, Identifiable {
    case temperature
    case iconOnly

    var id: String { rawValue }

    func title(isChinese: Bool) -> String {
        switch self {
        case .temperature:
            return isChinese ? "图标与温度" : "Icon and temperature"
        case .iconOnly:
            return isChinese ? "仅图标" : "Icon only"
        }
    }
}

enum ProductHealthLevel {
    case healthy
    case elevated
    case critical
    case unavailable

    var color: Color {
        switch self {
        case .healthy:
            return .green
        case .elevated:
            return .orange
        case .critical:
            return .red
        case .unavailable:
            return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .healthy:
            return "checkmark.circle.fill"
        case .elevated:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "exclamationmark.octagon.fill"
        case .unavailable:
            return "questionmark.circle"
        }
    }
}

private enum ProductDateFormatter {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

func productLocalized(_ english: String, _ chinese: String) -> String {
    LanguageManager.shared.currentLanguage == "zh" ? chinese : english
}

var productIsBetaBuild: Bool {
    #if BETA
    true
    #else
    false
    #endif
}

/// A thin trusted presentation layer over the existing telemetry service.
/// Read-only sampling starts with the menu-bar app so history and alerts do not
/// silently stop when every product window is closed.
final class ProductUIModel: ObservableObject {
    static let shared = ProductUIModel()

    @Published var selectedSection: ProductSection = .overview
    @Published var temperature: ProductMetricState = .loading
    @Published var fanSpeed: ProductMetricState = .loading
    @Published var memoryPressure: ProductMetricState = .loading
    @Published var cpuUsage: ProductMetricState = .loading
    @Published var thermalPressure: ProductMetricState = .loading
    @Published var batteryCapacity: ProductMetricState = .loading
    @Published var batteryCycles: ProductMetricState = .loading
    @Published var batteryCondition: ProductMetricState = .loading
    @Published private(set) var diagnosis: Diagnosis
    @Published private(set) var helperSetupRequested = false
    @Published private(set) var helperRuntimeStatus = "Not Installed"
    @Published var menuBarDisplayMode: ProductMenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: Self.menuBarDisplayModeKey)
        }
    }

    private static let menuBarDisplayModeKey = "productMenuBarDisplayMode"
    private let daemon = DaemonManager.shared
    private let diagnosisEvaluator: DiagnosisEvaluator
    private var cancellables = Set<AnyCancellable>()
    private var staleTimer: Timer?
    private var monitoringStarted = false
    private var latestSnapshot: SystemSnapshot

    private init() {
        let initialSnapshot = DaemonManager.shared.systemSnapshot
        let evaluator = DiagnosisEvaluator()
        let storedMode = UserDefaults.standard.string(forKey: Self.menuBarDisplayModeKey)
        #if APPSTORE
        let defaultMenuBarMode = ProductMenuBarDisplayMode.iconOnly
        #else
        let defaultMenuBarMode = ProductMenuBarDisplayMode.temperature
        #endif
        menuBarDisplayMode = ProductMenuBarDisplayMode(rawValue: storedMode ?? "")
            ?? defaultMenuBarMode
        latestSnapshot = initialSnapshot
        diagnosisEvaluator = evaluator
        diagnosis = evaluator.evaluate(initialSnapshot, at: Date())
        apply(initialSnapshot, at: Date())
        observeTelemetry()
    }

    var isAppStoreEdition: Bool {
        latestSnapshot.channel == .appStore
    }

    var editionName: String {
        let edition = isAppStoreEdition
            ? productLocalized("App Store Monitor", "App Store 监测版")
            : productLocalized("Direct", "官网直装版")
        return productIsBetaBuild
            ? edition + productLocalized(" · Beta Preview", " · 免费 Beta")
            : edition
    }

    var hasNotchedScreen: Bool {
        NSScreen.screens.contains { screen in
            screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }
    }

    var overallHealth: ProductHealthLevel {
        switch diagnosis.status {
        case .healthy:
            return .healthy
        case .warning:
            return .elevated
        case .critical:
            return .critical
        case .insufficientData:
            return .unavailable
        }
    }

    var freshestSampleDate: Date? {
        [
            temperature,
            fanSpeed,
            memoryPressure,
            cpuUsage,
            thermalPressure,
            batteryCapacity,
            batteryCycles,
            batteryCondition
        ]
            .compactMap(\.availableSampleDate)
            .max()
    }

    var hardwareMonitoringReady: Bool {
        latestSnapshot.capabilities.allows(.cpuTemperature)
            || latestSnapshot.capabilities.allows(.fanRead)
    }

    func hardwareMonitoringStatus(isChinese: Bool) -> String {
        if hardwareMonitoringReady {
            return isChinese ? "可信硬件读数已启用" : "Trusted hardware readings enabled"
        }
        if helperRuntimeStatus.contains("Retiring Legacy Helper") {
            return isChinese
                ? "正在安全撤销旧版辅助组件"
                : "Securely retiring the legacy helper"
        }
        if helperRuntimeStatus.contains("Manual Removal Required") {
            return isChinese
                ? "检测到旧式 root 组件；需按安全指南手动移除"
                : "Legacy root helper detected; follow the safe removal guide"
        }
        if helperRuntimeStatus.contains("Failed")
            || helperRuntimeStatus.contains("Could Not Be Verified")
            || helperRuntimeStatus.contains("Status Unknown") {
            return isChinese
                ? "辅助组件安全迁移失败：\(helperRuntimeStatus)"
                : helperRuntimeStatus
        }
        if helperRuntimeStatus.contains("Legacy Helper") {
            return isChinese
                ? "检测到旧版组件；需要安全迁移"
                : "Legacy helper detected; secure migration required"
        }
        if helperRuntimeStatus.contains("Approval Required") {
            return isChinese ? "需要在系统设置中批准" : "Approval required in System Settings"
        }
        if helperRuntimeStatus.contains("Error") {
            return isChinese
                ? "辅助组件设置失败；可安全重试"
                : "Helper setup failed; it is safe to retry"
        }
        if helperRuntimeStatus.contains("Not Found") {
            return isChinese
                ? "当前安装中缺少安全辅助组件"
                : "The secure helper is missing from this installation"
        }
        if helperSetupRequested {
            return isChinese ? "正在检查辅助组件状态" : "Checking helper status"
        }
        let temperatureState = latestSnapshot.capabilities.state(for: .cpuTemperature)
        let fanState = latestSnapshot.capabilities.state(for: .fanRead)
        let state = preferredCapabilityState(temperatureState, fanState)
        return capabilityAvailabilityText(state.availability, isChinese: isChinese)
    }

    func healthTitle(isChinese: Bool) -> String {
        switch overallHealth {
        case .healthy:
            return isChinese ? "系统热状态正常" : "Thermal state is normal"
        case .elevated:
            return isChinese ? "系统负载正在升高" : "System load is elevated"
        case .critical:
            return isChinese ? "系统需要立即关注" : "Your Mac needs attention"
        case .unavailable:
            return isChinese ? "监测数据尚不完整" : "Monitoring data is incomplete"
        }
    }

    func healthMessage(isChinese: Bool) -> String {
        switch diagnosis.code {
        case .noAlertsInAvailableMetrics:
            return isChinese
                ? "DiagnosisEvaluator 未在新鲜且可用的指标中发现异常。"
                : "DiagnosisEvaluator found no alert in fresh, available metrics."
        case .insufficientData:
            return isChinese
                ? "没有足够的新鲜可信指标；CoolCumber 不会用估算值代替。"
                : "There are not enough fresh trusted metrics; CoolCumber does not substitute estimates."
        case .thermalPressureFair:
            return isChinese ? "macOS 报告热压力升高。" : "macOS reports elevated thermal pressure."
        case .thermalPressureSerious:
            return isChinese ? "macOS 报告较严重的热压力。" : "macOS reports serious thermal pressure."
        case .thermalPressureCritical:
            return isChinese ? "macOS 报告严重热压力，请保存工作并降低负载。" : "macOS reports critical thermal pressure. Save your work and reduce load."
        case .highCPUTemperature:
            return isChinese ? "可信 CPU 温度读数已超过警戒阈值。" : "The trusted CPU temperature exceeds the warning threshold."
        case .criticalCPUTemperature:
            return isChinese ? "可信 CPU 温度读数已超过严重阈值。" : "The trusted CPU temperature exceeds the critical threshold."
        case .highMemoryUsage:
            return isChinese ? "可信内存使用率已超过警戒阈值。" : "Trusted memory use exceeds the warning threshold."
        case .highCPUUsage:
            return isChinese ? "可信 CPU 使用率已超过警戒阈值。" : "Trusted CPU use exceeds the warning threshold."
        case .lowDiskSpace:
            return isChinese ? "可信存储读数显示可用空间不足。" : "Trusted storage data reports low available space."
        }
    }

    func startReadOnlyMonitoring() {
        guard !monitoringStarted else { return }
        monitoringStarted = true

        daemon.startPolling()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshPresentationFreshness()
        }
    }

    func stopReadOnlyMonitoring() {
        staleTimer?.invalidate()
        staleTimer = nil
        daemon.stopPolling()
        monitoringStarted = false
    }

    func refresh() {
        if !monitoringStarted {
            startReadOnlyMonitoring()
        } else {
            daemon.checkThermalStatus()
        }
    }

    func requestHelperSetup() {
        #if !APPSTORE
        helperSetupRequested = true
        daemon.installDaemonIfNeeded()
        #endif
    }

    private func observeTelemetry() {
        daemon.$systemSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.latestSnapshot = snapshot
                self.apply(snapshot, at: Date())
            }
            .store(in: &cancellables)

        daemon.$daemonStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.helperRuntimeStatus = status
            }
            .store(in: &cancellables)

    }

    private func refreshPresentationFreshness() {
        apply(latestSnapshot, at: Date())
    }

    private func apply(_ snapshot: SystemSnapshot, at referenceDate: Date) {
        temperature = metricState(
            snapshot.thermal.cpuTemperature,
            at: referenceDate
        ) { String(format: "%.0f", $0.value) }

        thermalPressure = metricState(
            snapshot.thermal.pressure,
            at: referenceDate
        ) { thermalPressureText($0) }

        cpuUsage = metricState(snapshot.cpu.usage, at: referenceDate) {
            String(format: "%.0f", $0.value)
        }

        memoryPressure = metricState(snapshot.memory.usage, at: referenceDate) {
            String(format: "%.0f", $0.value)
        }

        if let firstFan = snapshot.fans.first {
            fanSpeed = metricState(firstFan.currentSpeed, at: referenceDate) {
                String($0.value)
            }
        } else {
            fanSpeed = missingFanState(snapshot: snapshot, at: referenceDate)
        }

        batteryCapacity = metricState(snapshot.battery.maximumCapacity, at: referenceDate) {
            String(format: "%.0f", $0.value)
        }
        batteryCycles = metricState(snapshot.battery.cycleCount, at: referenceDate) {
            String($0)
        }
        batteryCondition = metricState(snapshot.battery.condition, at: referenceDate) {
            batteryConditionText($0)
        }

        diagnosis = diagnosisEvaluator.evaluate(snapshot, at: referenceDate)
    }

    private func metricState<Value>(
        _ sample: MetricSample<Value>,
        at referenceDate: Date,
        formatter: (Value) -> String
    ) -> ProductMetricState where Value: Codable & Equatable & Sendable {
        let maximumAge = diagnosisEvaluator.thresholds.maximumMetricAge.value
        let freshness = sample.freshness(at: referenceDate, maximumAge: maximumAge)
        let source = provenanceText(sample.provenance)

        guard sample.availability == .available, let value = sample.value else {
            return .unavailable(
                reason: metricAvailabilityText(sample.availability, failure: sample.failure),
                source: source,
                observedAt: sample.observedAt,
                isStale: freshness == .stale
            )
        }

        let displayValue = formatter(value)
        if freshness == .stale {
            return .stale(
                value: displayValue,
                source: source,
                sampledAt: sample.observedAt
            )
        }
        return .available(
            value: displayValue,
            source: source,
            sampledAt: sample.observedAt
        )
    }

    private func missingFanState(
        snapshot: SystemSnapshot,
        at referenceDate: Date
    ) -> ProductMetricState {
        let capability = snapshot.capabilities.state(for: .fanRead)
        let maximumAge = diagnosisEvaluator.thresholds.maximumMetricAge.value
        let capabilityAge = referenceDate.timeIntervalSince(capability.evaluatedAt)
        let isStale = !capabilityAge.isFinite
            || capabilityAge < 0
            || capabilityAge > maximumAge
        return .unavailable(
            reason: capabilityAvailabilityText(
                capability.availability,
                reasonCode: capability.reasonCode,
                isChinese: LanguageManager.shared.currentLanguage == "zh"
            ),
            source: productLocalized("Capability model", "能力模型"),
            observedAt: capability.evaluatedAt,
            isStale: isStale
        )
    }

    private func metricAvailabilityText(
        _ availability: MetricAvailability,
        failure: MetricFailure?
    ) -> String {
        if let message = failure?.message, !message.isEmpty {
            return message
        }
        switch availability {
        case .available:
            return productLocalized("Available sample has no value", "可用样本缺少数值")
        case .unsupported:
            return productLocalized("Unsupported on this edition or device", "当前版本或设备不支持")
        case .notPresent:
            return productLocalized("Sensor is not present", "设备不存在此传感器")
        case .permissionRequired:
            return productLocalized("Permission is required", "需要授权")
        case .temporarilyUnavailable:
            return productLocalized("Temporarily unavailable", "暂时不可用")
        case .failed:
            if let code = failure?.code {
                return productLocalized("Collection failed (\(code))", "采集失败（\(code)）")
            }
            return productLocalized("Collection failed", "采集失败")
        case .unknown:
            return productLocalized("Not evaluated yet", "尚未完成评估")
        }
    }

    private func provenanceText(_ provenance: MetricProvenance) -> String {
        let source: String
        switch provenance.source {
        case .smc: source = "SMC"
        case .processInfo: source = "ProcessInfo"
        case .machKernel: source = productLocalized("Mach kernel", "Mach 内核")
        case .ioKit: source = "IOKit"
        case .fileSystem: source = productLocalized("File system", "文件系统")
        case .networkInterface: source = productLocalized("Network interface", "网络接口")
        case .systemProfiler: source = "System Profiler"
        case .powermetrics: source = "powermetrics"
        case .derived: source = productLocalized("Derived metric", "派生指标")
        case .fixture: source = productLocalized("Test fixture", "测试样本")
        case .unknown: source = productLocalized("Unknown source", "未知来源")
        }

        let quality: String
        switch provenance.quality {
        case .measured: quality = productLocalized("measured", "实测")
        case .systemReported: quality = productLocalized("system reported", "系统报告")
        case .derived: quality = productLocalized("derived", "派生")
        case .fixture: quality = productLocalized("fixture", "测试数据")
        case .unknown: quality = productLocalized("unverified", "未验证")
        }
        return "\(source) · \(quality)"
    }

    private func thermalPressureText(_ pressure: ThermalPressure) -> String {
        switch pressure {
        case .nominal: return productLocalized("Normal", "正常")
        case .fair: return productLocalized("Elevated", "升高")
        case .serious: return productLocalized("Serious", "较高")
        case .critical: return productLocalized("Critical", "严重")
        }
    }

    private func batteryConditionText(_ condition: BatteryCondition) -> String {
        switch condition {
        case .normal: return productLocalized("Normal", "正常")
        case .serviceRecommended: return productLocalized("Service recommended", "建议检修")
        case .unknown: return productLocalized("Unknown", "未知")
        }
    }

    private func preferredCapabilityState(
        _ first: CapabilityState,
        _ second: CapabilityState
    ) -> CapabilityState {
        let priority: (CapabilityAvailability) -> Int = { availability in
            switch availability {
            case .available: return 6
            case .authorizationRequired: return 5
            case .temporarilyUnavailable: return 4
            case .unknown: return 3
            case .notPresent: return 2
            case .unsupported: return 1
            }
        }
        return priority(first.availability) >= priority(second.availability) ? first : second
    }

    private func capabilityAvailabilityText(
        _ availability: CapabilityAvailability,
        reasonCode: String? = nil,
        isChinese: Bool
    ) -> String {
        switch availability {
        case .available:
            return isChinese ? "可用" : "Available"
        case .unsupported:
            return isChinese ? "当前版本或设备不支持" : "Unsupported on this edition or device"
        case .notPresent:
            return isChinese ? "设备不存在相应硬件" : "Required hardware is not present"
        case .authorizationRequired:
            return isChinese ? "需要在系统设置中批准" : "Approval is required in System Settings"
        case .temporarilyUnavailable:
            return isChinese ? "暂时不可用" : "Temporarily unavailable"
        case .unknown:
            if let reasonCode, !reasonCode.isEmpty {
                return isChinese ? "尚未完成评估（\(reasonCode)）" : "Not evaluated yet (\(reasonCode))"
            }
            return isChinese ? "尚未完成评估" : "Not evaluated yet"
        }
    }
}

// MARK: - Menu bar controller

final class MenuBarManager: NSObject, NSPopoverDelegate {
    static let shared = MenuBarManager()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var dashboardWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var isSetup = false

    func setup() {
        guard !isSetup else { return }
        isSetup = true

        configureDashboardWindow()
        configurePopover()
        configureStatusItem()
        observeMenuBarPresentation()
    }

    private func configureDashboardWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CoolCumber"
        window.minSize = NSSize(width: 780, height: 560)
        window.isReleasedWhenClosed = false
        window.isRestorable = true
        window.setFrameAutosaveName("CoolCumberMainWindow")
        window.contentViewController = NSHostingController(
            rootView: ProductRootView(model: ProductUIModel.shared)
        )
        dashboardWindow = window
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: ProductMenuPopoverView(model: ProductUIModel.shared)
        )
        popover.delegate = self
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: "leaf.fill",
            accessibilityDescription: "CoolCumber"
        ) ?? NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: "CoolCumber")
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = image?.withSymbolConfiguration(configuration)
        button.image?.isTemplate = true
        button.imagePosition = .imageLeft
        button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(handleMainClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observeMenuBarPresentation() {
        ProductUIModel.shared.$temperature
            .combineLatest(ProductUIModel.shared.$menuBarDisplayMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] temperature, mode in
                self?.updateStatusItem(temperature: temperature, mode: mode)
            }
            .store(in: &cancellables)
    }

    @objc private func handleMainClick(_ sender: NSStatusBarButton) {
        guard NSApp.currentEvent?.type != .rightMouseUp else {
            showContextMenu()
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            ProductUIModel.shared.startReadOnlyMonitoring()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: productLocalized("Open CoolCumber", "打开 CoolCumber"), action: #selector(openDashboard), keyEquivalent: "")
        menu.addItem(withTitle: productLocalized("History & Alerts", "历史与提醒"), action: #selector(openHistory), keyEquivalent: "h")
        menu.addItem(withTitle: productLocalized("Refresh Readings", "刷新读数"), action: #selector(refreshReadings), keyEquivalent: "r")
        menu.addItem(withTitle: productLocalized("Settings…", "设置…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: productLocalized("Quit CoolCumber", "退出 CoolCumber"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)
        menu.items.filter { $0.target == nil }.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func openDashboard() {
        popover.performClose(nil)
        guard let window = dashboardWindow else { return }
        ProductUIModel.shared.startReadOnlyMonitoring()
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func refreshReadings() {
        ProductUIModel.shared.refresh()
    }

    @objc private func openSettings() {
        ProductUIModel.shared.selectedSection = .settings
        openDashboard()
    }

    @objc private func openHistory() {
        ProductUIModel.shared.selectedSection = .history
        openDashboard()
    }

    /// Kept for compatibility with the previous DashboardView close control.
    @objc func closePopover() {
        popover.performClose(nil)
        dashboardWindow?.orderOut(nil)
    }

    private func updateStatusItem(
        temperature: ProductMetricState,
        mode: ProductMenuBarDisplayMode
    ) {
        guard let button = statusItem.button else { return }
        switch mode {
        case .iconOnly:
            button.title = ""
        case .temperature:
            let suffix: String
            switch temperature {
            case .loading:
                suffix = " …"
            case let .available(value, _, _):
                suffix = " \(value)°"
            case let .stale(value, _, _):
                suffix = " ~\(value)°"
            case .unavailable:
                suffix = " —"
            }
            button.title = suffix
        }
        button.toolTip = menuBarTooltip(for: temperature)
    }

    private func menuBarTooltip(for temperature: ProductMetricState) -> String {
        switch temperature {
        case .loading:
            return productLocalized("CoolCumber · Waiting for a trusted reading", "CoolCumber · 正在等待可信读数")
        case let .available(value, _, sampledAt):
            return productLocalized(
                "CoolCumber · CPU \(value)°C · Updated \(ProductDateFormatter.time.string(from: sampledAt))",
                "CoolCumber · CPU \(value)°C · 更新于 \(ProductDateFormatter.time.string(from: sampledAt))"
            )
        case let .stale(value, _, sampledAt):
            return productLocalized(
                "CoolCumber · Stale CPU reading \(value)°C · \(ProductDateFormatter.time.string(from: sampledAt))",
                "CoolCumber · CPU 旧读数 \(value)°C · \(ProductDateFormatter.time.string(from: sampledAt))"
            )
        case let .unavailable(reason, source, observedAt, isStale):
            let state = isStale
                ? productLocalized("stale", "已过期")
                : productLocalized("unavailable", "不可用")
            return "CoolCumber · \(state) · \(reason) · \(source) · \(ProductDateFormatter.time.string(from: observedAt))"
        }
    }
}

// MARK: - Menu bar views

private struct ProductMenuPopoverView: View {
    @ObservedObject var model: ProductUIModel
    @ObservedObject private var language = LanguageManager.shared

    private var isChinese: Bool { language.currentLanguage == "zh" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.overallHealth.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(model.overallHealth.color)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.healthTitle(isChinese: isChinese))
                        .font(.system(size: 15, weight: .semibold))
                    Text(model.healthMessage(isChinese: isChinese))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Divider()

            VStack(spacing: 12) {
                ProductMenuMetricRow(
                    title: isChinese ? "CPU 温度" : "CPU temperature",
                    icon: "thermometer.medium",
                    state: model.temperature,
                    unit: "°C"
                )
                ProductMenuMetricRow(
                    title: isChinese ? "风扇" : "Fan",
                    icon: "fanblades",
                    state: model.fanSpeed,
                    unit: "RPM"
                )
                ProductMenuMetricRow(
                    title: isChinese ? "内存" : "Memory",
                    icon: "memorychip",
                    state: model.memoryPressure,
                    unit: "%"
                )
            }

            Divider()

            HStack {
                Button(isChinese ? "打开 CoolCumber" : "Open CoolCumber") {
                    MenuBarManager.shared.openDashboard()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Spacer()

                Button {
                    model.refresh()
                } label: {
                    Label(isChinese ? "刷新" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help(isChinese ? "退出 CoolCumber" : "Quit CoolCumber")
                .accessibilityLabel(isChinese ? "退出 CoolCumber" : "Quit CoolCumber")
            }
            }
            .padding(18)
        }
        .frame(width: 360, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.startReadOnlyMonitoring()
        }
    }
}

private struct ProductMenuMetricRow: View {
    let title: String
    let icon: String
    let state: ProductMetricState
    let unit: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(state.supportingText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(state.displayedValue)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                if !unit.isEmpty, state.displayedValue != "—", state.displayedValue != "…" {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(state.displayedValue) \(unit). \(state.supportingText)")
    }
}
