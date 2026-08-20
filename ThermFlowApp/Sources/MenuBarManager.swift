import AppKit
import SwiftUI
import Combine

// MARK: - Product UI state

/// A presentation-safe metric state. The UI never substitutes a fabricated
/// number when a source is loading, stale, unsupported, or disconnected.
enum ProductMetricState: Equatable {
    case loading
    case available(value: String, source: String, sampledAt: Date)
    case stale(value: String, source: String, sampledAt: Date)
    case unavailable(reason: String)

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
        case let .unavailable(reason):
            return reason
        }
    }

    func markingStale(at now: Date, after interval: TimeInterval) -> ProductMetricState {
        guard case let .available(value, source, sampledAt) = self,
              now.timeIntervalSince(sampledAt) > interval else {
            return self
        }
        return .stale(value: value, source: source, sampledAt: sampledAt)
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

/// A thin trusted presentation layer over the existing telemetry service.
/// It starts read-only sampling only after a user opens a product surface.
final class ProductUIModel: ObservableObject {
    static let shared = ProductUIModel()

    @Published var selectedSection: ProductSection = .overview
    @Published var temperature: ProductMetricState = .loading
    @Published var fanSpeed: ProductMetricState = .loading
    @Published var memoryPressure: ProductMetricState = .loading
    @Published var cpuUsage: ProductMetricState = .loading
    @Published var thermalPressure: ProductMetricState = .loading
    @Published var helperStatus: String = productLocalized("Not checked", "尚未检查")
    @Published var menuBarDisplayMode: ProductMenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: Self.menuBarDisplayModeKey)
        }
    }

    private static let menuBarDisplayModeKey = "productMenuBarDisplayMode"
    private let staleInterval: TimeInterval = 15
    private let daemon = DaemonManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var staleTimer: Timer?
    private var monitoringStarted = false
    private var latestTemperature: Double?

    private init() {
        let storedMode = UserDefaults.standard.string(forKey: Self.menuBarDisplayModeKey)
        menuBarDisplayMode = ProductMenuBarDisplayMode(rawValue: storedMode ?? "") ?? .temperature
        observeTelemetry()
    }

    var isAppStoreEdition: Bool {
        #if APPSTORE
        return true
        #else
        return false
        #endif
    }

    var editionName: String {
        isAppStoreEdition
            ? productLocalized("App Store Monitor", "App Store 监测版")
            : productLocalized("Direct", "官网直装版")
    }

    var hasNotchedScreen: Bool {
        NSScreen.screens.contains { screen in
            screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        }
    }

    var overallHealth: ProductHealthLevel {
        let thermal = daemon.thermalStatus.lowercased()
        if thermal.contains("critical") {
            return .critical
        }
        if thermal.contains("serious") || thermal.contains("fair") {
            return .elevated
        }
        if let latestTemperature {
            if latestTemperature >= 90 { return .critical }
            if latestTemperature >= 75 { return .elevated }
            return .healthy
        }
        if thermal.contains("nominal") || thermal.contains("normal") {
            return .healthy
        }
        return .unavailable
    }

    var freshestSampleDate: Date? {
        [temperature, fanSpeed, memoryPressure, cpuUsage, thermalPressure]
            .compactMap(\.sampledAt)
            .max()
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
        switch overallHealth {
        case .healthy:
            return isChinese
                ? "已获得的系统读数未显示明显热压力。"
                : "Available system readings show no significant thermal pressure."
        case .elevated:
            return isChinese
                ? "温度或系统热压力升高，请查看各指标的来源和更新时间。"
                : "Temperature or system thermal pressure is elevated. Review each reading and its freshness."
        case .critical:
            return isChinese
                ? "系统报告严重热压力或高温，请先保存工作并降低负载。"
                : "The system reports critical thermal pressure or temperature. Save your work and reduce load."
        case .unavailable:
            return isChinese
                ? "CoolCumber 不会用估算值代替缺失的传感器数据。"
                : "CoolCumber does not replace missing sensor data with estimates."
        }
    }

    func startReadOnlyMonitoring() {
        guard !monitoringStarted else { return }
        monitoringStarted = true

        daemon.startPolling()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.markOldReadingsStale()
        }

        // A disconnected Direct helper may never publish an empty payload. End
        // the loading state without inventing values after the first attempt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.settleLoadingStates()
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
        daemon.installDaemonIfNeeded()
        #endif
    }

    private func observeTelemetry() {
        daemon.$temperatures
            .receive(on: RunLoop.main)
            .sink { [weak self] readings in
                guard let self else { return }
                guard let value = readings["CPU"], value.isFinite, (-20...130).contains(value) else {
                    if self.monitoringStarted {
                        self.latestTemperature = nil
                        self.temperature = .unavailable(reason: self.temperatureUnavailableReason)
                    }
                    return
                }
                self.latestTemperature = value
                self.temperature = .available(
                    value: String(format: "%.0f", value),
                    source: productLocalized("Hardware sensor", "硬件传感器"),
                    sampledAt: Date()
                )
            }
            .store(in: &cancellables)

        daemon.$fanSpeed
            .receive(on: RunLoop.main)
            .sink { [weak self] rawValue in
                guard let self else { return }
                let token = rawValue.split(separator: " ").first.flatMap { Double($0) }
                guard let rpm = token, rpm.isFinite, rpm >= 0 else {
                    if self.monitoringStarted {
                        self.fanSpeed = .unavailable(reason: self.fanUnavailableReason)
                    }
                    return
                }
                self.fanSpeed = .available(
                    value: String(format: "%.0f", rpm),
                    source: productLocalized("Fan controller", "风扇控制器"),
                    sampledAt: Date()
                )
            }
            .store(in: &cancellables)

        daemon.$memoryStats
            .receive(on: RunLoop.main)
            .sink { [weak self] stats in
                guard let self else { return }
                guard let used = stats["used"], let total = stats["total"], total > 0 else {
                    if self.monitoringStarted {
                        self.memoryPressure = .unavailable(
                            reason: productLocalized("Memory statistics are unavailable", "无法读取内存统计")
                        )
                    }
                    return
                }
                let percentage = min(100, max(0, used / total * 100))
                self.memoryPressure = .available(
                    value: String(format: "%.0f", percentage),
                    source: productLocalized("macOS host statistics", "macOS 主机统计"),
                    sampledAt: Date()
                )
            }
            .store(in: &cancellables)

        daemon.$cpuUsage
            .combineLatest(daemon.$currentCpuPercent)
            .receive(on: RunLoop.main)
            .sink { [weak self] ticks, percentage in
                guard let self else { return }
                guard !ticks.isEmpty, percentage.isFinite else {
                    if self.monitoringStarted {
                        self.cpuUsage = .unavailable(
                            reason: productLocalized("CPU usage is unavailable", "无法读取 CPU 使用率")
                        )
                    }
                    return
                }
                self.cpuUsage = .available(
                    value: String(format: "%.0f", min(100, max(0, percentage))),
                    source: productLocalized("macOS processor statistics", "macOS 处理器统计"),
                    sampledAt: Date()
                )
            }
            .store(in: &cancellables)

        daemon.$thermalStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty,
                      normalized.lowercased() != "unknown",
                      !normalized.lowercased().contains("failed"),
                      !normalized.lowercased().contains("error") else {
                    if self.monitoringStarted {
                        self.thermalPressure = .unavailable(
                            reason: productLocalized("System thermal pressure is unavailable", "无法读取系统热压力")
                        )
                    }
                    return
                }
                self.thermalPressure = .available(
                    value: self.friendlyThermalStatus(normalized),
                    source: self.isAppStoreEdition
                        ? "ProcessInfo.thermalState"
                        : productLocalized("Trusted helper", "可信辅助组件"),
                    sampledAt: Date()
                )
            }
            .store(in: &cancellables)

        daemon.$daemonStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.helperStatus = status
            }
            .store(in: &cancellables)
    }

    private func settleLoadingStates() {
        guard monitoringStarted else { return }
        if temperature == .loading {
            temperature = .unavailable(reason: temperatureUnavailableReason)
        }
        if fanSpeed == .loading {
            fanSpeed = .unavailable(reason: fanUnavailableReason)
        }
        if memoryPressure == .loading {
            memoryPressure = .unavailable(
                reason: productLocalized("Memory statistics are unavailable", "无法读取内存统计")
            )
        }
        if cpuUsage == .loading {
            cpuUsage = .unavailable(
                reason: productLocalized("CPU usage is unavailable", "无法读取 CPU 使用率")
            )
        }
        if thermalPressure == .loading {
            thermalPressure = .unavailable(
                reason: productLocalized("System thermal pressure is unavailable", "无法读取系统热压力")
            )
        }
    }

    private func markOldReadingsStale() {
        let now = Date()
        temperature = temperature.markingStale(at: now, after: staleInterval)
        fanSpeed = fanSpeed.markingStale(at: now, after: staleInterval)
        memoryPressure = memoryPressure.markingStale(at: now, after: staleInterval)
        cpuUsage = cpuUsage.markingStale(at: now, after: staleInterval)
        thermalPressure = thermalPressure.markingStale(at: now, after: staleInterval)
    }

    private var temperatureUnavailableReason: String {
        #if APPSTORE
        return productLocalized(
            "The App Store sandbox does not expose sensor temperatures",
            "App Store 沙盒不提供传感器温度"
        )
        #else
        return productLocalized(
            "No verified temperature reading; helper setup may be required",
            "没有可信温度读数；可能需要设置辅助组件"
        )
        #endif
    }

    private var fanUnavailableReason: String {
        #if APPSTORE
        return productLocalized(
            "The App Store sandbox does not expose fan RPM",
            "App Store 沙盒不提供风扇转速"
        )
        #else
        return productLocalized(
            "No verified fan reading; helper setup may be required",
            "没有可信风扇读数；可能需要设置辅助组件"
        )
        #endif
    }

    private func friendlyThermalStatus(_ status: String) -> String {
        let normalized = status.lowercased()
        if normalized.contains("critical") {
            return productLocalized("Critical", "严重")
        }
        if normalized.contains("serious") {
            return productLocalized("Serious", "较高")
        }
        if normalized.contains("fair") {
            return productLocalized("Elevated", "升高")
        }
        if normalized.contains("nominal") || normalized.contains("normal") {
            return productLocalized("Normal", "正常")
        }
        return status
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
            systemSymbolName: "fanblades.fill",
            accessibilityDescription: "CoolCumber"
        ) ?? NSImage(systemSymbolName: "wind", accessibilityDescription: "CoolCumber")
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
            case let .available(value, _, _), let .stale(value, _, _):
                suffix = " \(value)°"
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
        case let .unavailable(reason):
            return "CoolCumber · \(reason)"
        }
    }
}

// MARK: - Menu bar views

private struct ProductMenuPopoverView: View {
    @ObservedObject var model: ProductUIModel
    @ObservedObject private var language = LanguageManager.shared

    private var isChinese: Bool { language.currentLanguage == "zh" }

    var body: some View {
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

            Spacer(minLength: 0)
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
                    .lineLimit(1)
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
