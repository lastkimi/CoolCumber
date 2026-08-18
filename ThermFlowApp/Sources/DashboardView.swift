import SwiftUI
import Charts

/// DashboardView V3 - The main control dashboard.
/// Fully redesigned with translucent left sidebar, premium glass telemetry grid, and high-performance charts.
struct DashboardView: View {
    @ObservedObject var daemonManager = DaemonManager.shared
    @ObservedObject var aiEngine = DiagnosticRuleEngine.shared
    @ObservedObject var llmEngine = LLMEngine.shared
    @ObservedObject private var lang = LanguageManager.shared
    
    @State private var cpuHistory: [Double] = Array(repeating: 45.0, count: 30)
    @State private var isHoveringClose = false
    @State private var selectedTab: String = "dashboard"
    @State private var toastMessage: String?
    
    @AppStorage("ecoModeEnabled") private var ecoModeEnabled = false
    @AppStorage("isMaxCooling") private var isMaxCooling = false
    
    private var headerBar: some View {
        HStack {
            Text(tabTitle(for: selectedTab))
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            Spacer()
            
            // Custom Close Button for hiddenTitleBar
            Button(action: {
                MenuBarManager.shared.closePopover()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(isHoveringClose ? DesignSystem.Colors.statusCritical : DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hover in isHoveringClose = hover }
        }
        .padding(.horizontal, DesignSystem.Spacing.pageMargin)
        .padding(.top, DesignSystem.Spacing.comfortable)
        .padding(.bottom, DesignSystem.Spacing.normal)
    }
    
    private var aiStatusBar: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.normal) {
            HStack(spacing: DesignSystem.Spacing.comfortable) {
                Image(systemName: "sparkles")
                    .foregroundColor(DesignSystem.Colors.accentAI)
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(aiEngine.currentDiagnosis.status == .healthy ? lang.tr("ai_copilot_status").replacingOccurrences(of: "%@", with: "COOL") : lang.tr("ai_copilot_status").replacingOccurrences(of: "%@", with: "HOT"))
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(aiEngine.currentDiagnosis.status == .healthy ? DesignSystem.Colors.accentBrand : DesignSystem.Colors.statusWarning)
                    Text(lang.currentLanguage == "zh" ? "系统运行正常。温度与能效处于最佳状态。" : aiEngine.currentDiagnosis.message)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(2)
                }
                Spacer()
                
                HStack(spacing: DesignSystem.Spacing.normal) {
                    // Ask AI Button
                    Button(action: {
                        let provider = UserDefaults.standard.string(forKey: "ai_provider") ?? "deepseek"
                        llmEngine.askAI(provider: provider) { _ in }
                    }) {
                        if llmEngine.isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 20, height: 20)
                        } else {
                            HStack(spacing: DesignSystem.Spacing.tight) {
                                Image(systemName: "brain")
                                Text(lang.tr("ask_ai"))
                            }
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(DesignSystem.Colors.accentAI)
                            .cornerRadius(DesignSystem.Corners.smallButton)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(llmEngine.isLoading)
                    
                    if let action = aiEngine.currentDiagnosis.recommendedAction {
                        Button(action: {
                            executeRecommendedAction(action)
                        }) {
                            Text("Execute")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textInverse)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(DesignSystem.Colors.accentBrand)
                                .cornerRadius(DesignSystem.Corners.smallButton)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            if !llmEngine.responseText.isEmpty {
                Divider().background(DesignSystem.Colors.divider)
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                    Text("Deep Diagnosis:")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.accentAI)
                        .padding(.top, 4)
                    Text(llmEngine.responseText)
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DesignSystem.Spacing.comfortable)
        .glassCard()
        .padding(.horizontal, DesignSystem.Spacing.pageMargin)
        .padding(.bottom, DesignSystem.Spacing.comfortable)
    }
    
    private var telemetryGrid: some View {
        VStack(spacing: DesignSystem.Spacing.comfortable) {
            // First Row of gauges
            HStack(spacing: DesignSystem.Spacing.comfortable) {
                // CPU Temperature Gauge
                let cpuTemp = daemonManager.temperatures["CPU"] ?? 45.0
                let cpuStatusColor = cpuTemp > 80 ? DesignSystem.Colors.statusCritical : (cpuTemp > 65 ? DesignSystem.Colors.statusWarning : DesignSystem.Colors.statusHealthy)
                VStack(spacing: DesignSystem.Spacing.tight) {
                    ThermalGauge(value: cpuTemp, maxValue: 105.0, title: lang.tr("cpu_temp"), unit: "°C", statusColor: cpuStatusColor)
                }
                .padding(DesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity)
                .glassCard()
                
                // Fan speed gauge
                let fanRPMString = daemonManager.fanSpeed.replacingOccurrences(of: " RPM", with: "")
                let fanRPM = Double(fanRPMString) ?? 0.0
                VStack(spacing: DesignSystem.Spacing.tight) {
                    ThermalGauge(value: fanRPM, maxValue: 6000.0, title: lang.tr("fan_speed"), unit: "RPM", statusColor: DesignSystem.Colors.accentBrand)
                }
                .padding(DesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity)
                .glassCard()
                
                // Memory load gauge
                let totalMem = daemonManager.memoryStats["total"] ?? 1.0
                let usedMem = daemonManager.memoryStats["used"] ?? 0.0
                let memPercent = totalMem > 0 ? (usedMem / totalMem) * 100 : 0
                VStack(spacing: DesignSystem.Spacing.tight) {
                    ThermalGauge(value: memPercent, maxValue: 100.0, title: lang.tr("memory"), unit: "%", statusColor: DesignSystem.Colors.accentAI)
                }
                .padding(DesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity)
                .glassCard()
            }
            
            // Second Row of secondary metrics
            HStack(spacing: DesignSystem.Spacing.comfortable) {
                // Network Down Rate Card
                let downRate = (daemonManager.networkStats["down"] ?? 0) / 1024 / 1024
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                    Text(lang.tr("network_down"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.1f", downRate))
                            .font(DesignSystem.Typography.dataHero)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("MB/s")
                            .font(DesignSystem.Typography.dataCaption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(DesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
                
                // Available Disk space card
                let totalDisk = daemonManager.diskSpace["total"] ?? 1.0
                let availDisk = daemonManager.diskSpace["available"] ?? 0.0
                let freeGB = availDisk / 1_000_000_000
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                    Text(lang.tr("free_storage"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", freeGB))
                            .font(DesignSystem.Typography.dataHero)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("GB")
                            .font(DesignSystem.Typography.dataCaption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(DesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
                
                // Disk space usage percent card
                let diskPercent = totalDisk > 0 ? ((totalDisk - availDisk) / totalDisk) * 100 : 0
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                    Text(lang.tr("disk_used"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", diskPercent))
                            .font(DesignSystem.Typography.dataHero)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("%")
                            .font(DesignSystem.Typography.dataCaption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .padding(DesignSystem.Spacing.comfortable)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            }
            
            // Third Row: Historical area graph
            thermalChart
        }
        .frame(maxWidth: .infinity)
    }
    
    private var thermalChart: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.normal) {
            Text(lang.tr("cpu_thermal_history"))
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            SparklineChart(data: cpuHistory, color: DesignSystem.Colors.accentBrand)
        }
        .padding(DesignSystem.Spacing.comfortable)
        .glassCard()
    }
    
    private var toolsGrid: some View {
        VStack(spacing: DesignSystem.Spacing.comfortable) {
            ToolButton(title: lang.tr("smart_clean"), icon: "wand.and.stars", subtitle: lang.tr("purge_inactive_ram"), color: DesignSystem.Colors.accentBrand) {
                showToast(lang.currentLanguage == "zh" ? "正在释放闲置运行内存..." : "Purging inactive memory...")
                daemonManager.purgeMemory { success, _ in
                    showToast(success ? (lang.currentLanguage == "zh" ? "内存释放成功！" : "Memory purged successfully!") : (lang.currentLanguage == "zh" ? "释放失败。" : "Failed to purge memory."))
                }
            }
            
            ToolButton(
                title: isMaxCooling ? (lang.currentLanguage == "zh" ? "强力散热: 开启" : "Max Cooling: ON") : lang.tr("max_cooling"),
                icon: "wind",
                subtitle: isMaxCooling ? (lang.currentLanguage == "zh" ? "风扇 100% 运转" : "Fan at 100%") : lang.tr("force_100_fan"),
                color: isMaxCooling ? DesignSystem.Colors.statusCritical : DesignSystem.Colors.statusHealthy
            ) {
                isMaxCooling.toggle()
                if isMaxCooling {
                    showToast(lang.currentLanguage == "zh" ? "正在开启强力散热模式..." : "Enabling Max Cooling...")
                    daemonManager.connect()?.setFanSpeed(fanIndex: 0, rpm: 6000) { _,_ in }
                } else {
                    showToast(lang.currentLanguage == "zh" ? "正在恢复自动风扇控制..." : "Restoring Automatic Fan Control...")
                    daemonManager.connect()?.resetFanToAutomatic { _ in }
                }
            }
            
            ToolButton(
                title: ecoModeEnabled ? (lang.currentLanguage == "zh" ? "环保限能: 开启" : "Eco: ON") : lang.tr("eco_mode"),
                icon: "leaf.fill",
                subtitle: ecoModeEnabled ? (lang.currentLanguage == "zh" ? "功耗已受限" : "Power Limited") : lang.tr("limit_cpu_power"),
                color: ecoModeEnabled ? DesignSystem.Colors.statusHealthy : DesignSystem.Colors.textSecondary
            ) {
                ecoModeEnabled.toggle()
                let statusMsg = ecoModeEnabled ? "Eco Mode Enabled: CPU power limited." : "Eco Mode Disabled: Performance restored."
                showToast(statusMsg)
                
                daemonManager.setEcoMode(enabled: ecoModeEnabled) { success, error in
                    if !success {
                        print("Failed to set eco mode: \(error ?? "Unknown Error")")
                        DispatchQueue.main.async {
                            ecoModeEnabled.toggle() // Revert on failure
                            showToast("Failed to toggle Eco Mode.")
                        }
                    }
                }
            }
            
            Spacer()
        }
        .frame(width: 220)
        .overlay(
            VStack {
                Spacer()
                if let toast = toastMessage {
                    Text(toast)
                        .font(DesignSystem.Typography.caption)
                        .padding(DesignSystem.Spacing.normal)
                        .background(Color.black.opacity(0.85))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .cornerRadius(DesignSystem.Corners.normal)
                        .padding(.bottom, DesignSystem.Spacing.comfortable)
                        .transition(.opacity)
                }
            }
        )
    }
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.normal) {
            // App Title Header
            HStack(spacing: DesignSystem.Spacing.normal) {
                if let appIcon = NSApplication.shared.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .cornerRadius(DesignSystem.Corners.normal)
                } else {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DesignSystem.Colors.accentBrand)
                }
                Text("CoolCumber")
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 25)
            .padding(.bottom, 20)
            
            // Tab Buttons
            VStack(spacing: 6) {
                SidebarButton(title: lang.tr("status_center"), icon: "gauge", isSelected: selectedTab == "dashboard") {
                    selectedTab = "dashboard"
                }
                SidebarButton(title: lang.tr("thermal_power"), icon: "wind", isSelected: selectedTab == "thermal") {
                    selectedTab = "thermal"
                }
                SidebarButton(title: lang.tr("system_optimizer"), icon: "wand.and.stars", isSelected: selectedTab == "optimizer") {
                    selectedTab = "optimizer"
                }
                SidebarButton(title: lang.tr("preferences"), icon: "gearshape", isSelected: selectedTab == "preferences") {
                    selectedTab = "preferences"
                }
            }
            Spacer()
            
            // Language selector, links, and exit
            VStack(spacing: 6) {
                Divider().background(DesignSystem.Colors.divider)
                
                // Language Switcher
                HStack {
                    Text(lang.tr("language"))
                        .font(.system(size: 9))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    Spacer()
                    HStack(spacing: 2) {
                        Button("EN") {
                            lang.setLanguage("en")
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(lang.currentLanguage == "en" ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(lang.currentLanguage == "en" ? DesignSystem.Colors.accentBrand : Color.clear)
                        .cornerRadius(DesignSystem.Corners.smallButton)
                        .buttonStyle(.plain)
                        
                        Button("中文") {
                            lang.setLanguage("zh")
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(lang.currentLanguage == "zh" ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(lang.currentLanguage == "zh" ? DesignSystem.Colors.accentBrand : Color.clear)
                        .cornerRadius(DesignSystem.Corners.smallButton)
                        .buttonStyle(.plain)
                    }
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(DesignSystem.Corners.smallButton)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                
                // Privacy and About Links
                HStack {
                    Link(lang.tr("privacy"), destination: URL(string: "https://www.slmcamp.com/#/privacy")!)
                        .font(.system(size: 9))
                        .foregroundColor(DesignSystem.Colors.accentBrand)
                    
                    Spacer()
                    
                    Link(lang.tr("about_us"), destination: URL(string: "https://www.slmcamp.com/")!)
                        .font(.system(size: 9))
                        .foregroundColor(DesignSystem.Colors.accentBrand)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                
                // Version Label & Update Indicator
                HStack(spacing: 4) {
                    Text("\(lang.tr("version")): v\(UpdateManager.shared.currentVersion)")
                        .font(.system(size: 8))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Spacer()
                    
                    if UpdateManager.shared.hasUpdate {
                        Button(action: {
                            selectedTab = "preferences"
                        }) {
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(DesignSystem.Colors.statusHealthy)
                                    .frame(width: 5, height: 5)
                                Text("New")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.statusHealthy)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DesignSystem.Colors.statusHealthy.opacity(0.15))
                            .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                
                Divider().background(DesignSystem.Colors.divider)
                
                // Exit Button
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: DesignSystem.Spacing.normal) {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.statusCritical)
                            .frame(width: 14)
                        Text(lang.tr("quit_app"))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 10)
        }
        .frame(width: 170)
        .padding(.horizontal, 10)
        .background(DesignSystem.Colors.sidebarBg)
    }
    
    private var mainDashboardContent: some View {
        VStack(spacing: 0) {
            aiStatusBar
            
            HStack(spacing: DesignSystem.Spacing.comfortable) {
                telemetryGrid
                toolsGrid
            }
            .padding(.horizontal, DesignSystem.Spacing.pageMargin)
            .padding(.bottom, DesignSystem.Spacing.pageMargin)
        }
    }
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.windowBg
                .edgesIgnoringSafeArea(.all)
            
            HStack(spacing: 0) {
                sidebarView
                
                VStack(spacing: 0) {
                    headerBar
                    
                    VStack(spacing: 0) {
                        switch selectedTab {
                        case "dashboard":
                            mainDashboardContent
                        case "thermal":
                            ThermalPowerView()
                        case "optimizer":
                            SystemOptimizerView()
                        case "preferences":
                            SettingsView()
                        default:
                            mainDashboardContent
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 940, height: 540)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Corners.popover, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Corners.popover, style: .continuous)
                .stroke(DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
        .onAppear {
            daemonManager.startPolling()
            DiagnosticRuleEngine.shared.start()
            AutoMaintenanceScheduler.shared.start()
        }
        .onDisappear {
            daemonManager.stopPolling()
            DiagnosticRuleEngine.shared.stop()
            AutoMaintenanceScheduler.shared.stop()
        }
        .onChange(of: daemonManager.temperatures) { temps in
            withAnimation(.easeInOut(duration: 0.5)) {
                if let cpu = temps["CPU"] {
                    cpuHistory.removeFirst()
                    cpuHistory.append(cpu)
                }
            }
        }
    }
    
    private func tabTitle(for tab: String) -> String {
        switch tab {
        case "dashboard": return lang.tr("status_center")
        case "thermal": return lang.tr("thermal_power_hub")
        case "optimizer": return lang.tr("system_optimizer_title")
        case "preferences": return lang.tr("pref_title")
        default: return "CoolCumber"
        }
    }
    
    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if toastMessage == message {
                withAnimation {
                    toastMessage = nil
                }
            }
        }
    }
    
    private func executeRecommendedAction(_ action: RecommendedAction) {
        switch action {
        case .increaseFan(let rpm):
            daemonManager.connect()?.setFanSpeed(fanIndex: 0, rpm: rpm) { _,_ in }
            showToast("Increasing fan speed to \(rpm) RPM...")
        case .purgeMemory:
            daemonManager.purgeMemory { success, _ in
                showToast(success ? "Memory purged successfully!" : "Failed to purge memory.")
            }
        case .killProcess(let pid):
            if let pidInt = Int32(pid) {
                daemonManager.connect()?.killProcess(pid: pidInt) { success, _ in
                    showToast(success ? "Killed rogue process (PID: \(pid))" : "Failed to kill process.")
                }
            } else {
                showToast("Invalid Process PID.")
            }
        }
    }
}

struct SidebarButton: View {
    var title: String
    var icon: String
    var isSelected: Bool
    var action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.normal) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? DesignSystem.Colors.accentBrand : DesignSystem.Colors.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(isSelected ? DesignSystem.Typography.headline : DesignSystem.Typography.body)
                    .foregroundColor(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.cardPadding)
            .padding(.vertical, DesignSystem.Spacing.normal)
            .background(
                isSelected
                ? DesignSystem.Colors.glassBgHover
                : (isHovered ? DesignSystem.Colors.glassBg.opacity(0.3) : Color.clear)
            )
            .cornerRadius(DesignSystem.Corners.normal)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hover
            }
        }
    }
}

struct ToolButton: View {
    var title: String
    var icon: String
    var subtitle: String
    var color: Color
    var action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.comfortable) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 15))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(DesignSystem.Spacing.normal)
            .glassCard(isHovered: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hover in
            withAnimation(DesignSystem.Animations.hover) {
                isHovered = hover
            }
        }
    }
}

struct TempData: Identifiable {
    let id = UUID()
    let time: Int
    let temp: Double
}
