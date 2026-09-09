import SwiftUI
import AppKit

// MARK: - Application lifecycle

private enum ProductDefaultsKey {
    static let completedWelcome = "com.slmcamp.CoolCumber.welcome.v1.completed"
}

@main
struct CoolCumberApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            ProductSettingsPane(model: ProductUIModel.shared)
                .frame(width: 560, height: 470)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let arguments = ProcessInfo.processInfo.arguments

        #if DEBUG
        if arguments.contains("--ui-language-en") {
            LanguageManager.shared.setLanguage("en")
        } else if arguments.contains("--ui-language-zh") {
            LanguageManager.shared.setLanguage("zh")
        }
        if arguments.contains("--ui-appearance-dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if arguments.contains("--ui-appearance-light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
        #endif

        // Monitoring starts with the menu-bar app so history and opt-in alerts
        // remain truthful even when no window has been opened. The collector is
        // read-only; privileged helper setup still requires an explicit action.
        DaemonManager.shared.retireLegacyHelperIfNeeded()
        MenuBarManager.shared.setup()
        ProductUIModel.shared.startReadOnlyMonitoring()
        Task { @MainActor in
            ProductDataCoordinator.shared.start()
        }

        let smartBarEnabled = UserDefaults.standard.bool(forKey: "smartBarEnabled")
        if smartBarEnabled && ProductUIModel.shared.hasNotchedScreen {
            SmartBarManager.shared.setup()
        }

        let shouldShowWelcome = arguments.contains("--show-welcome")
            || (!UserDefaults.standard.bool(
                forKey: ProductDefaultsKey.completedWelcome
            ) && !arguments.contains("--skip-welcome"))
        let requestedWindow = [
            "--open-main-window",
            "--open-history",
            "--open-settings",
            "--open-pro",
            "--show-welcome"
        ].contains(where: arguments.contains)
        if shouldShowWelcome || requestedWindow {
            DispatchQueue.main.async { [weak self] in
                if arguments.contains("--open-history") {
                    ProductUIModel.shared.selectedSection = .history
                } else if arguments.contains("--open-settings") {
                    ProductUIModel.shared.selectedSection = .settings
                }
                self?.showDashboard()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProductUIModel.shared.stopReadOnlyMonitoring()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showDashboard()
        }
        return true
    }

    func showDashboard() {
        MenuBarManager.shared.openDashboard()
    }
}

// MARK: - Navigation

enum ProductSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case cooling
    case activity
    case history
    case battery
    case maintenance
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .cooling: return "fanblades"
        case .activity: return "waveform.path.ecg"
        case .history: return "chart.xyaxis.line"
        case .battery: return "battery.75percent"
        case .maintenance: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }

    func title(isChinese: Bool) -> String {
        switch self {
        case .overview: return isChinese ? "概览" : "Overview"
        case .cooling: return isChinese ? "散热" : "Cooling"
        case .activity: return isChinese ? "活动" : "Activity"
        case .history: return isChinese ? "历史" : "History"
        case .battery: return isChinese ? "电池" : "Battery"
        case .maintenance: return isChinese ? "维护" : "Maintenance"
        case .settings: return isChinese ? "设置" : "Settings"
        }
    }
}

struct ProductRootView: View {
    @ObservedObject var model: ProductUIModel
    @ObservedObject private var language = LanguageManager.shared
    @ObservedObject private var commerce = PurchaseController.shared
    @State private var showsPaywall: Bool
    @State private var showsWelcome: Bool

    init(model: ProductUIModel) {
        self.model = model
        let arguments = ProcessInfo.processInfo.arguments
        _showsPaywall = State(
            initialValue: arguments.contains("--open-pro")
        )
        _showsWelcome = State(
            initialValue: arguments.contains("--show-welcome")
                || (!UserDefaults.standard.bool(
                    forKey: ProductDefaultsKey.completedWelcome
                )
                    && !arguments.contains("--skip-welcome")
                    && !arguments.contains("--open-pro"))
        )
    }

    private var isChinese: Bool { language.currentLanguage == "zh" }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<ProductSection?>(
                get: { model.selectedSection },
                set: { selection in
                    if let selection {
                        model.selectedSection = selection
                    }
                }
            )) {
                Section {
                    ForEach(ProductSection.allCases.filter { $0 != .settings }) { section in
                        Label(section.title(isChinese: isChinese), systemImage: section.icon)
                            .font(.system(size: 13))
                            .tag(section)
                    }
                }

                Section {
                    Label(
                        ProductSection.settings.title(isChinese: isChinese),
                        systemImage: ProductSection.settings.icon
                    )
                    .font(.system(size: 13))
                    .tag(ProductSection.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("CoolCumber")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } detail: {
            sectionContent
                .navigationTitle(model.selectedSection.title(isChinese: isChinese))
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        ProductFreshnessLabel(date: model.freshestSampleDate, isChinese: isChinese)

                        Button {
                            showsPaywall = true
                        } label: {
                            Label(
                                commerce.isProUnlocked
                                    ? (isChinese ? "Pro 已启用" : "Pro active")
                                    : (isChinese ? "了解 Pro" : "View Pro"),
                                systemImage: commerce.isProUnlocked ? "checkmark.seal.fill" : "sparkles"
                            )
                        }
                        .help(isChinese ? "查看版本与购买状态" : "View edition and purchase status")

                        Button {
                            model.refresh()
                        } label: {
                            Label(isChinese ? "刷新读数" : "Refresh readings", systemImage: "arrow.clockwise")
                        }
                        .help(isChinese ? "刷新所有可信读数" : "Refresh all trusted readings")
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.green)
        .onAppear {
            model.startReadOnlyMonitoring()
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showsWelcome) {
            ProductWelcomeView(model: model) {
                UserDefaults.standard.set(
                    true,
                    forKey: ProductDefaultsKey.completedWelcome
                )
                showsWelcome = false
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.selectedSection {
        case .overview:
            ProductOverviewPage(model: model, isChinese: isChinese)
        case .cooling:
            ProductCoolingPage(model: model, isChinese: isChinese)
        case .activity:
            ProductActivityPage(model: model, isChinese: isChinese)
        case .history:
            ProductHistoryPage(
                isChinese: isChinese,
                showPro: { showsPaywall = true }
            )
        case .battery:
            ProductBatteryPage(model: model, isChinese: isChinese)
        case .maintenance:
            ProductMaintenancePage(model: model, isChinese: isChinese)
        case .settings:
            ScrollView {
                ProductSettingsPane(model: model)
                    .padding(24)
            }
        }
    }
}

private struct ProductWelcomeView: View {
    @ObservedObject var model: ProductUIModel
    @ObservedObject private var language = LanguageManager.shared
    let complete: () -> Void

    private var isChinese: Bool { language.currentLanguage == "zh" }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isChinese ? "欢迎使用 CoolCumber" : "Welcome to CoolCumber")
                        .font(.title2.weight(.semibold))
                    Text(isChinese ? "安静、可信的 Mac 健康监测" : "Quiet, trustworthy Mac health monitoring")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                welcomeRow(
                    icon: "checkmark.shield",
                    title: isChinese ? "只展示可信数据" : "Only trustworthy data",
                    detail: isChinese
                        ? "缺失、过期或不支持的指标会明确标记，绝不补入模拟数值。"
                        : "Missing, stale, and unsupported metrics are labeled explicitly—never replaced with simulated values."
                )
                welcomeRow(
                    icon: "menubar.rectangle",
                    title: isChinese ? "菜单栏是主入口" : "Built for the menu bar",
                    detail: isChinese
                        ? "关闭窗口后仍会进行轻量只读采样，以维护本地历史和你主动开启的提醒。"
                        : "Lightweight read-only sampling continues with windows closed to maintain local history and alerts you enable."
                )
                welcomeRow(
                    icon: model.isAppStoreEdition ? "shippingbox" : "lock.shield",
                    title: model.isAppStoreEdition
                        ? (isChinese ? "严格沙盒运行" : "Strictly sandboxed")
                        : (isChinese ? "硬件组件始终可选" : "Hardware helper stays optional"),
                    detail: model.isAppStoreEdition
                        ? (isChinese
                            ? "App Store 版不会安装特权组件；底层温度和风扇数据可能显示为不支持。"
                            : "The App Store edition never installs a privileged helper; low-level temperature and fan readings may be unsupported.")
                        : (isChinese
                            ? "只有在你查看说明并明确确认后，才会注册有界只读的硬件监测组件。"
                            : "The bounded, read-only hardware helper is registered only after you review the explanation and explicitly confirm.")
                )
            }

            Button(isChinese ? "进入 CoolCumber" : "Continue to CoolCumber") {
                complete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(28)
        .frame(width: 600)
    }

    private func welcomeRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Overview

private struct ProductOverviewPage: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProductHealthSummary(model: model, isChinese: isChinese)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ProductMetricCard(
                        title: isChinese ? "CPU 温度" : "CPU temperature",
                        icon: "thermometer.medium",
                        state: model.temperature,
                        unit: "°C"
                    )
                    ProductMetricCard(
                        title: isChinese ? "系统热压力" : "Thermal pressure",
                        icon: "flame",
                        state: model.thermalPressure,
                        unit: ""
                    )
                    ProductMetricCard(
                        title: isChinese ? "风扇转速" : "Fan speed",
                        icon: "fanblades",
                        state: model.fanSpeed,
                        unit: "RPM"
                    )
                    ProductMetricCard(
                        title: isChinese ? "内存使用" : "Memory use",
                        icon: "memorychip",
                        state: model.memoryPressure,
                        unit: "%"
                    )
                }

                ProductNoticeCard(
                    icon: "checkmark.shield",
                    title: isChinese ? "可信数据原则" : "Trusted data by design",
                    message: isChinese
                        ? "缺失的传感器读数会显示为“不可用”；旧读数会明确标记为“已过期”。CoolCumber 不再用默认数值填补空白。"
                        : "Missing sensor readings are shown as unavailable and old readings are marked stale. CoolCumber no longer fills gaps with default values.",
                    tone: .neutral
                )
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
    }
}

private struct ProductHealthSummary: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: model.overallHealth.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(model.overallHealth.color)
                .frame(width: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(model.healthTitle(isChinese: isChinese))
                    .font(.system(size: 21, weight: .semibold))
                Text(model.healthMessage(isChinese: isChinese))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let date = model.freshestSampleDate {
                    Text(
                        (isChinese ? "最近可信更新：" : "Latest trusted update: ")
                        + ProductTimestamp.text(for: date)
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)

            Text(model.editionName)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Feature pages

private struct ProductCoolingPage: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool

    var body: some View {
        ProductPageContainer {
            ProductPageHeader(
                icon: "fanblades",
                title: isChinese ? "散热" : "Cooling",
                subtitle: isChinese
                    ? "基于可验证读数展示散热状态；不支持的控制能力始终保持不可用。"
                    : "Cooling status is based on verified readings; unsupported controls remain unavailable."
            )

            HStack(alignment: .top, spacing: 16) {
                ProductMetricCard(
                    title: isChinese ? "CPU 温度" : "CPU temperature",
                    icon: "thermometer.medium",
                    state: model.temperature,
                    unit: "°C"
                )
                ProductMetricCard(
                    title: isChinese ? "风扇转速" : "Fan speed",
                    icon: "fanblades",
                    state: model.fanSpeed,
                    unit: "RPM"
                )
                ProductMetricCard(
                    title: isChinese ? "热压力" : "Thermal pressure",
                    icon: "flame",
                    state: model.thermalPressure,
                    unit: ""
                )
            }

            if model.isAppStoreEdition {
                ProductNoticeCard(
                    icon: "lock.shield",
                    title: isChinese ? "由 macOS 管理散热" : "Cooling is managed by macOS",
                    message: isChinese
                        ? "App Store 监测版不会提供沙盒外的风扇或 SMC 控制，也不会为这些不可用能力显示付费入口。"
                        : "The App Store Monitor does not expose fan or SMC controls outside its sandbox, and never sells unavailable capabilities.",
                    tone: .neutral
                )
            } else {
                ProductHelperSetupCard(model: model, isChinese: isChinese)
                ProductNoticeCard(
                    icon: "lock.shield",
                    title: productIsBetaBuild
                        ? (isChinese ? "Beta 暂不开放散热控制" : "Cooling controls are unavailable in Beta")
                        : (isChinese ? "手动散热控制未提供" : "Manual cooling controls are not offered"),
                    message: isChinese
                        ? "此版本只读取可信的 SystemSnapshot。它不会自动写入 SMC，也不会把不可用的硬件控制作为 Pro 功能销售。"
                        : "This release reads trusted SystemSnapshot data only. It never writes SMC automatically or sells unavailable hardware controls as Pro features.",
                    tone: .neutral
                )
            }
        }
    }
}

private struct ProductActivityPage: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool

    var body: some View {
        ProductPageContainer {
            ProductPageHeader(
                icon: "waveform.path.ecg",
                title: isChinese ? "活动" : "Activity",
                subtitle: isChinese
                    ? "查看 CPU 和内存负载；进程操作不会在后台自动执行。"
                    : "Review CPU and memory load. Process actions never run automatically in the background."
            )

            HStack(alignment: .top, spacing: 16) {
                ProductMetricCard(
                    title: isChinese ? "CPU 使用率" : "CPU usage",
                    icon: "cpu",
                    state: model.cpuUsage,
                    unit: "%"
                )
                ProductMetricCard(
                    title: isChinese ? "内存使用" : "Memory use",
                    icon: "memorychip",
                    state: model.memoryPressure,
                    unit: "%"
                )
            }

            ProductNoticeCard(
                icon: "person.crop.circle.badge.checkmark",
                title: isChinese ? "操作需要确认" : "Actions require confirmation",
                message: isChinese
                    ? "CoolCumber 只呈现可信的系统负载，不会自动终止、冻结或降频任何进程。"
                    : "CoolCumber presents trusted system load and never terminates, freezes, or throttles a process automatically.",
                tone: .neutral
            )

        }
    }
}

private struct ProductBatteryPage: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool

    var body: some View {
        ProductPageContainer {
            ProductPageHeader(
                icon: "battery.75percent",
                title: isChinese ? "电池" : "Battery",
                subtitle: isChinese
                    ? "只展示能够从系统或可信组件验证的电池信息。"
                    : "Only battery information verified by macOS or a trusted component is shown."
            )

            HStack(alignment: .top, spacing: 16) {
                ProductMetricCard(
                    title: isChinese ? "最大容量" : "Maximum capacity",
                    icon: "battery.75percent",
                    state: model.batteryCapacity,
                    unit: "%"
                )
                ProductMetricCard(
                    title: isChinese ? "循环次数" : "Cycle count",
                    icon: "arrow.triangle.2.circlepath",
                    state: model.batteryCycles,
                    unit: ""
                )
                ProductMetricCard(
                    title: isChinese ? "电池状况" : "Battery condition",
                    icon: "heart.text.square",
                    state: model.batteryCondition,
                    unit: ""
                )
            }

            ProductNoticeCard(
                icon: "eye",
                title: isChinese ? "当前为可信只读模式" : "Trusted read-only mode",
                message: isChinese
                    ? "所有值直接来自 SystemSnapshot；不可用与过期状态会如实显示。本产品不承诺或销售电池充电限制。"
                    : "Every value comes directly from SystemSnapshot, including unavailable and stale states. This product does not promise or sell battery charge limits.",
                tone: .neutral
            )
        }
    }
}

private struct ProductMaintenancePage: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool

    var body: some View {
        ProductPageContainer {
            ProductPageHeader(
                icon: "wrench.and.screwdriver",
                title: isChinese ? "维护" : "Maintenance",
                subtitle: isChinese
                    ? "任何文件或系统变更都必须可解释、可确认、可恢复。"
                    : "Every file or system change must be explained, confirmed, and recoverable."
            )

            ProductNoticeCard(
                icon: "hand.raised.fill",
                title: isChinese ? "自动维护已关闭" : "Automatic maintenance is off",
                message: isChinese
                    ? "CoolCumber 不会自动清理文件、制造内存压力、重建索引或修改后台服务。"
                    : "CoolCumber never cleans files automatically, creates memory pressure, rebuilds indexes, or changes background services.",
                tone: .warning
            )

            ProductUnavailablePanel(
                icon: "clock.arrow.circlepath",
                title: isChinese ? "没有隐式系统操作" : "No hidden system actions",
                message: isChinese
                    ? "维护页是清晰的产品边界说明；监测、历史和提醒不会修改你的文件或系统设置。"
                    : "This page documents the product boundary: monitoring, history, and alerts do not modify your files or system settings."
            )

        }
    }
}

// MARK: - Settings

struct ProductSettingsPane: View {
    @ObservedObject var model: ProductUIModel
    @ObservedObject private var language = LanguageManager.shared
    @AppStorage("smartBarEnabled") private var smartBarEnabled = false
    @ObservedObject private var commerce = PurchaseController.shared
    @State private var showsPaywall = false

    private var isChinese: Bool { language.currentLanguage == "zh" }

    var body: some View {
        Form {
            Section(isChinese ? "菜单栏" : "Menu Bar") {
                Picker(
                    isChinese ? "显示内容" : "Display",
                    selection: $model.menuBarDisplayMode
                ) {
                    ForEach(ProductMenuBarDisplayMode.allCases) { mode in
                        Text(mode.title(isChinese: isChinese)).tag(mode)
                    }
                }
                Text(isChinese
                     ? "菜单栏是所有 Mac（包括 2019 无刘海机型）的主入口。"
                     : "The menu bar is the primary entry point on every Mac, including 2019 models without a notch.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Section(isChinese ? "语言与显示" : "Language & Display") {
                Picker(
                    isChinese ? "语言" : "Language",
                    selection: Binding(
                        get: { language.currentLanguage },
                        set: { language.setLanguage($0) }
                    )
                ) {
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }

                if model.hasNotchedScreen {
                    Toggle(isChinese ? "启用刘海 SmartBar" : "Enable notch SmartBar", isOn: $smartBarEnabled)
                    Text(isChinese
                         ? "SmartBar 是可选增强，设置将在下次启动时生效。"
                         : "SmartBar is optional. This setting takes effect on the next launch.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    LabeledContent(isChinese ? "刘海 SmartBar" : "Notch SmartBar") {
                        Text(isChinese ? "此显示器不支持" : "Not available on this display")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(isChinese ? "版本与能力" : "Edition & Capabilities") {
                LabeledContent(isChinese ? "当前版本" : "Edition") {
                    Text(model.editionName)
                }

                if model.isAppStoreEdition {
                    Text(isChinese
                         ? "App Store 监测版遵守沙盒边界，不安装特权辅助组件。"
                         : "The App Store Monitor respects its sandbox and never installs a privileged helper.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ProductHelperSetupCard(model: model, isChinese: isChinese)
                }

                LabeledContent(isChinese ? "Pro 权益" : "Pro access") {
                    Text(commerce.entitlement.statusTitle(isChinese: isChinese))
                        .foregroundColor(commerce.isProUnlocked ? .green : .secondary)
                }

                Button {
                    showsPaywall = true
                } label: {
                    Label(
                        commerce.isProUnlocked
                            ? (isChinese ? "管理 Pro" : "Manage Pro")
                            : (isChinese ? "查看终身 Pro" : "View lifetime Pro"),
                        systemImage: commerce.isProUnlocked ? "checkmark.seal" : "sparkles"
                    )
                }
            }

            Section(isChinese ? "数据诚信" : "Data Integrity") {
                Label(
                    isChinese ? "不使用模拟温度或虚假正常值" : "No simulated temperatures or fake healthy defaults",
                    systemImage: "checkmark.shield"
                )
                .font(.system(size: 13))
                Label(
                    isChinese ? "旧数据明确标记为已过期" : "Old readings are explicitly marked stale",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.system(size: 13))
            }

            Section(isChinese ? "隐私与支持" : "Privacy & Support") {
                Link(
                    destination: URL(
                        string: "https://github.com/lastkimi/CoolCumber/blob/master/PRIVACY.md"
                    )!
                ) {
                    Label(isChinese ? "隐私政策" : "Privacy Policy", systemImage: "hand.raised")
                }
                Link(
                    destination: URL(
                        string: "https://github.com/lastkimi/CoolCumber/issues"
                    )!
                ) {
                    Label(isChinese ? "支持与问题反馈" : "Support and Feedback", systemImage: "questionmark.circle")
                }
                LabeledContent(isChinese ? "应用版本" : "App version") {
                    Text(appVersionText)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private struct ProductHelperSetupCard: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool
    @State private var showsConfirmation = false

    private var requiresManualRemoval: Bool {
        model.helperRuntimeStatus.contains("Manual Removal Required")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    isChinese ? "硬件监测辅助组件" : "Hardware monitoring helper",
                    systemImage: model.hardwareMonitoringReady ? "checkmark.shield.fill" : "lock.shield"
                )
                .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.hardwareMonitoringStatus(isChinese: isChinese))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Text(isChinese
                 ? "辅助组件用于读取 macOS 未向普通 App 开放的传感器。安装前会说明用途，并由你明确确认。"
                 : "The helper reads sensors macOS does not expose to ordinary apps. Its purpose is explained before you explicitly approve setup.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if !model.hardwareMonitoringReady {
                if requiresManualRemoval {
                    Link(
                        isChinese ? "查看安全移除指南" : "Open the safe removal guide",
                        destination: URL(
                            string: "https://github.com/lastkimi/CoolCumber/blob/master/SECURITY.md#removing-a-pre-v2-helper"
                        )!
                    )
                } else {
                    Button(
                        model.helperSetupRequested
                            ? (isChinese ? "重新检查或重试…" : "Check Again or Retry…")
                            : (isChinese ? "设置硬件监测…" : "Set Up Hardware Monitoring…")
                    ) {
                        showsConfirmation = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .alert(
            model.helperRuntimeStatus.contains("Legacy Helper")
                ? (isChinese ? "安全迁移旧版组件？" : "Migrate the legacy helper securely?")
                : (isChinese ? "设置辅助组件？" : "Set up the helper?"),
            isPresented: $showsConfirmation
        ) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            Button(isChinese ? "继续" : "Continue") {
                model.requestHelperSetup()
            }
        } message: {
            Text(
                model.helperRuntimeStatus.contains("Legacy Helper")
                    ? (isChinese
                        ? "CoolCumber 将停用旧版辅助组件，再注册只提供两项有界只读 SMC 读取的新版本；macOS 可能要求你批准后台项目。"
                        : "CoolCumber will retire the legacy helper, then register a new helper limited to two bounded, read-only SMC calls. macOS may ask you to approve the background item.")
                    : (isChinese
                        ? "macOS 可能要求你在系统设置中批准后台项目。CoolCumber 不会在未经确认时安装它。"
                        : "macOS may ask you to approve a background item in System Settings. CoolCumber never installs it without confirmation.")
            )
        }
    }
}

// MARK: - Reusable components

private struct ProductPageContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
    }
}

private struct ProductPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProductMetricCard: View {
    let title: String
    let icon: String
    let state: ProductMetricState
    let unit: String

    private var stateColor: Color {
        switch state {
        case .available: return .primary
        case .stale: return .orange
        case .loading, .unavailable: return .secondary
        }
    }

    private var stateLabel: String? {
        switch state {
        case .stale:
            return productLocalized("STALE", "已过期")
        case .unavailable:
            return productLocalized("UNAVAILABLE", "不可用")
        case .loading:
            return productLocalized("LOADING", "读取中")
        case .available:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if let stateLabel {
                    Text(stateLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(stateColor)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(state.displayedValue)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundColor(stateColor)
                if !unit.isEmpty, state.displayedValue != "—", state.displayedValue != "…" {
                    Text(unit)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Text(state.supportingText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(state.displayedValue) \(unit). \(state.supportingText)")
    }
}

private enum ProductNoticeTone {
    case neutral
    case warning

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .warning: return .orange
        }
    }
}

private struct ProductNoticeCard: View {
    let icon: String
    let title: String
    let message: String
    let tone: ProductNoticeTone

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tone.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.color.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tone.color.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct ProductUnavailablePanel: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

private struct ProductFreshnessLabel: View {
    let date: Date?
    let isChinese: Bool

    var body: some View {
        if let date {
            Label(ProductTimestamp.text(for: date), systemImage: "clock")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .accessibilityLabel(
                    (isChinese ? "最近可信更新：" : "Latest trusted update: ")
                    + ProductTimestamp.text(for: date)
                )
        } else {
            Label(
                isChinese ? "尚无可信读数" : "No trusted reading",
                systemImage: "questionmark.circle"
            )
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        }
    }
}

private enum ProductTimestamp {
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    static func text(for date: Date) -> String {
        formatter.string(from: date)
    }
}
