import SwiftUI
import AppKit

// MARK: - Application lifecycle

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

        // The menu bar shell is intentionally the only automatic startup work.
        // Sensor polling starts after a user opens the popover or main window,
        // and privileged helper setup always requires an explicit action.
        MenuBarManager.shared.setup()

        let smartBarEnabled = UserDefaults.standard.bool(forKey: "smartBarEnabled")
        if smartBarEnabled && ProductUIModel.shared.hasNotchedScreen {
            SmartBarManager.shared.setup()
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
    case battery
    case maintenance
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .cooling: return "fanblades"
        case .activity: return "waveform.path.ecg"
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
        case .battery: return isChinese ? "电池" : "Battery"
        case .maintenance: return isChinese ? "维护" : "Maintenance"
        case .settings: return isChinese ? "设置" : "Settings"
        }
    }
}

private enum ProductLegacyPage: String, Identifiable {
    case cooling
    case optimizer
    case settings

    var id: String { rawValue }
}

struct ProductRootView: View {
    @ObservedObject var model: ProductUIModel
    @ObservedObject private var language = LanguageManager.shared
    @State private var legacyPage: ProductLegacyPage?

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
        .sheet(item: $legacyPage) { page in
            ProductLegacySheet(page: page)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.selectedSection {
        case .overview:
            ProductOverviewPage(model: model, isChinese: isChinese)
        case .cooling:
            ProductCoolingPage(model: model, isChinese: isChinese) {
                legacyPage = .cooling
            }
        case .activity:
            ProductActivityPage(model: model, isChinese: isChinese) {
                legacyPage = .optimizer
            }
        case .battery:
            ProductBatteryPage(model: model, isChinese: isChinese) {
                legacyPage = .cooling
            }
        case .maintenance:
            ProductMaintenancePage(model: model, isChinese: isChinese) {
                legacyPage = .optimizer
            }
        case .settings:
            ScrollView {
                ProductSettingsPane(model: model)
                    .padding(24)
            }
        }
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
    let openLegacy: () -> Void

    var body: some View {
        ProductPageContainer {
            ProductPageHeader(
                icon: "fanblades",
                title: isChinese ? "散热" : "Cooling",
                subtitle: isChinese
                    ? "先展示系统真实状态，再逐步开放经过安全验证的控制能力。"
                    : "See real system state first; controls appear only after they pass safety validation."
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
                ProductLegacyButton(
                    title: isChinese ? "打开现有散热详细视图" : "Open existing cooling details",
                    message: isChinese
                        ? "现有页面保留为二级工具；需要明确操作后才会打开。"
                        : "The existing page remains available as a secondary tool and opens only on request.",
                    action: openLegacy
                )
            }
        }
    }
}

private struct ProductActivityPage: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool
    let openLegacy: () -> Void

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
                    ? "可信进程采样和可恢复操作将在下一阶段接入；当前骨架不会自动终止、冻结或降频任何进程。"
                    : "Trusted process sampling and recoverable actions arrive in the next phase. This shell never terminates, freezes, or throttles a process automatically.",
                tone: .neutral
            )

            #if !APPSTORE
            ProductLegacyButton(
                title: isChinese ? "打开现有活动详细视图" : "Open existing activity details",
                message: isChinese ? "仅在主动打开后加载现有工具。" : "Existing tools load only after you open them.",
                action: openLegacy
            )
            #endif
        }
    }
}

private struct ProductBatteryPage: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool
    let openLegacy: () -> Void

    var body: some View {
        ProductPageContainer {
            ProductPageHeader(
                icon: "battery.75percent",
                title: isChinese ? "电池" : "Battery",
                subtitle: isChinese
                    ? "只展示能够从系统或可信组件验证的电池信息。"
                    : "Only battery information verified by macOS or a trusted component is shown."
            )

            ProductUnavailablePanel(
                icon: "battery.0percent",
                title: isChinese ? "电池可信数据层尚未接入" : "Trusted battery data is not connected yet",
                message: model.isAppStoreEdition
                    ? (isChinese
                        ? "当前 App Store 版本不会模拟健康度、循环次数或充电限制。"
                        : "This App Store build does not simulate health, cycle count, or charge limits.")
                    : (isChinese
                        ? "完成辅助组件验证后，这里才会显示真实健康度、循环次数与可用控制。"
                        : "Real health, cycle count, and supported controls appear only after helper validation is complete.")
            )

            #if !APPSTORE
            ProductLegacyButton(
                title: isChinese ? "打开现有电池详细视图" : "Open existing battery details",
                message: isChinese ? "现有页面保留为二级工具。" : "The existing page remains a secondary tool.",
                action: openLegacy
            )
            #endif
        }
    }
}

private struct ProductMaintenancePage: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool
    let openLegacy: () -> Void

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
                    ? "此阶段不会自动清理文件、释放内存、重建索引或修改后台服务。安全操作模型完成后再逐项开放。"
                    : "This phase never cleans files, purges memory, rebuilds indexes, or changes services automatically. Capabilities return individually after the safety model is complete.",
                tone: .warning
            )

            ProductUnavailablePanel(
                icon: "clock.arrow.circlepath",
                title: isChinese ? "操作历史将在下一阶段提供" : "Operation history arrives next",
                message: isChinese
                    ? "每次操作都将记录目标、预估影响、结果和恢复方式。"
                    : "Each action will record its target, expected impact, result, and recovery path."
            )

            #if !APPSTORE
            ProductLegacyButton(
                title: isChinese ? "打开现有维护详细视图" : "Open existing maintenance details",
                message: isChinese ? "仅在主动打开后加载现有工具。" : "Existing tools load only after you open them.",
                action: openLegacy
            )
            #endif
        }
    }
}

// MARK: - Settings

struct ProductSettingsPane: View {
    @ObservedObject var model: ProductUIModel
    @ObservedObject private var language = LanguageManager.shared
    @AppStorage("smartBarEnabled") private var smartBarEnabled = false

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
        }
        .formStyle(.grouped)
    }
}

private struct ProductHelperSetupCard: View {
    @ObservedObject var model: ProductUIModel
    let isChinese: Bool
    @State private var showsConfirmation = false

    private var helperAppearsEnabled: Bool {
        let status = model.helperStatus.lowercased()
        return status.contains("enabled") || status.contains("registered")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    isChinese ? "硬件监测辅助组件" : "Hardware monitoring helper",
                    systemImage: helperAppearsEnabled ? "checkmark.shield.fill" : "lock.shield"
                )
                .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.helperStatus)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Text(isChinese
                 ? "辅助组件用于读取 macOS 未向普通 App 开放的传感器。安装前会说明用途，并由你明确确认。"
                 : "The helper reads sensors macOS does not expose to ordinary apps. Its purpose is explained before you explicitly approve setup.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if !helperAppearsEnabled {
                Button(isChinese ? "设置硬件监测…" : "Set Up Hardware Monitoring…") {
                    showsConfirmation = true
                }
                .buttonStyle(.bordered)
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
            isChinese ? "设置辅助组件？" : "Set up the helper?",
            isPresented: $showsConfirmation
        ) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            Button(isChinese ? "继续" : "Continue") {
                model.requestHelperSetup()
            }
        } message: {
            Text(isChinese
                 ? "macOS 可能要求你在系统设置中批准后台项目。CoolCumber 不会在未经确认时安装它。"
                 : "macOS may ask you to approve a background item in System Settings. CoolCumber never installs it without confirmation.")
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

private struct ProductLegacyButton: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(productLocalized("Open", "打开"), action: action)
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

private struct ProductLegacySheet: View {
    let page: ProductLegacyPage

    @ViewBuilder
    var body: some View {
        switch page {
        case .cooling:
            ThermalPowerView()
                .frame(minWidth: 900, minHeight: 620)
        case .optimizer:
            SystemOptimizerView()
                .frame(minWidth: 900, minHeight: 620)
        case .settings:
            SettingsView()
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}
