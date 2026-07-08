import SwiftUI

/// ThermalPowerView V3 - Cohesive management hub for cooling, power optimization, and battery care.
/// Merges old CoolingView + BCLM + Battery health predictor + App Freezer.
struct ThermalPowerView: View {
    @StateObject private var coolingVM = CoolingViewModel()
    @ObservedObject var freezerManager = AppFreezerManager.shared
    @ObservedObject private var lang = LanguageManager.shared
    
    // Battery Status States
    @State private var isBclmEnabled = false
    @State private var bclmLimit = 80
    @State private var batteryStatusText: String = ""
    @State private var cycleCount = 0
    @State private var currentHealth = 100
    @State private var condition = "Normal"
    @State private var prediction: BatteryPrediction?
    
    // App Freezer States
    @State private var runningApps: [NSRunningApplication] = []
    @State private var selectedAppBundleId: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sectionGap) {
                
                // Header Title
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                    Text(LanguageManager.shared.tr("thermal_power_hub"))
                        .font(DesignSystem.Typography.display)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(LanguageManager.shared.tr("manage_cooling"))
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.bottom, DesignSystem.Spacing.normal)
                
                if let msg = coolingVM.statusMessage {
                    Text(lang.currentLanguage == "zh" ? "风扇控制状态已应用。" : msg)
                        .font(DesignSystem.Typography.headline)
                        .padding(DesignSystem.Spacing.normal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.accentBrand.opacity(0.12))
                        .foregroundColor(DesignSystem.Colors.accentBrand)
                        .cornerRadius(DesignSystem.Corners.normal)
                        .transition(.slide.combined(with: .opacity))
                }
                
                // ROW 1: Cooling Engine (Dual Cards)
                HStack(alignment: .top, spacing: DesignSystem.Spacing.comfortable) {
                    // Card 1A: Proactive Cooling
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                                Text(LanguageManager.shared.tr("proactive_cooling"))
                                    .font(DesignSystem.Typography.title)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(LanguageManager.shared.tr("fan_profile_desc"))
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { coolingVM.fanEngine.isProactiveModeEnabled },
                                set: { _ in coolingVM.toggleProactiveMode() }
                            ))
                            .toggleStyle(.switch)
                        }
                        
                        if coolingVM.fanEngine.isProactiveModeEnabled {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                                Text(lang.currentLanguage == "zh" ? "加速的应用程序:" : "Accelerated Apps:")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                
                                FlowLayout(spacing: 6) {
                                    ForEach(coolingVM.fanEngine.heavyApps, id: \.self) { app in
                                        Text(app)
                                            .font(DesignSystem.Typography.dataMicro)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(DesignSystem.Colors.accentBrand.opacity(0.12))
                                            .foregroundColor(DesignSystem.Colors.accentBrand)
                                            .cornerRadius(DesignSystem.Corners.badge)
                                    }
                                }
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.comfortable)
                    .glassCard()
                    
                    // Card 1B: Manual SMC Fan Speed Override
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                                Text(LanguageManager.shared.tr("manual_fan"))
                                    .font(DesignSystem.Typography.title)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(LanguageManager.shared.tr("override_fan_speed"))
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { coolingVM.fanEngine.isManualModeEnabled },
                                set: { newValue in
                                    if newValue {
                                        coolingVM.applyManualSpeed()
                                    } else {
                                        coolingVM.restoreAutomatic()
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                        }
                        
                        HStack(spacing: DesignSystem.Spacing.normal) {
                            Text(lang.currentLanguage == "zh" ? "当前:" : "Current:")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text("\(coolingVM.currentRPM)")
                                .font(DesignSystem.Typography.dataHeadline)
                                .foregroundColor(DesignSystem.Colors.accentBrand)
                            Text("RPM")
                                .font(DesignSystem.Typography.micro)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        if coolingVM.fanEngine.isManualModeEnabled {
                            VStack(spacing: DesignSystem.Spacing.normal) {
                                Slider(value: Binding(
                                    get: { coolingVM.fanEngine.manualFanRPM },
                                    set: { coolingVM.fanEngine.manualFanRPM = $0 }
                                ), in: 1200...6000, step: 100)
                                .accentColor(DesignSystem.Colors.accentBrand)
                                
                                HStack {
                                    Text((lang.currentLanguage == "zh" ? "设定转速: " : "Set Speed: ") + "\(Int(coolingVM.fanEngine.manualFanRPM)) RPM")
                                        .font(DesignSystem.Typography.dataCaption)
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    Spacer()
                                    Button(lang.currentLanguage == "zh" ? "应用" : "Apply") {
                                        coolingVM.applyManualSpeed()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(DesignSystem.Colors.accentBrand)
                                    .foregroundColor(DesignSystem.Colors.textInverse)
                                }
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.comfortable)
                    .glassCard()
                }
                
                // ROW 2: Battery Management
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
                    HStack {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                            Text(LanguageManager.shared.tr("smc_limit"))
                                .font(DesignSystem.Typography.title)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Text(LanguageManager.shared.tr("battery_mgmt"))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $isBclmEnabled)
                            .toggleStyle(.switch)
                            .onChange(of: isBclmEnabled) { enabled in
                                applyBatteryLimit(enabled: enabled)
                            }
                    }
                    
                    if isBclmEnabled {
                        HStack(spacing: DesignSystem.Spacing.comfortable) {
                            Slider(value: Binding(
                                get: { Double(bclmLimit) },
                                set: { bclmLimit = Int($0) }
                            ), in: 50...95, step: 5)
                            .accentColor(DesignSystem.Colors.accentBrand)
                            .onChange(of: bclmLimit) { val in
                                applyBatteryLimit(enabled: true)
                            }
                            
                            Text("\(bclmLimit)%")
                                .font(DesignSystem.Typography.dataTitle)
                                .foregroundColor(DesignSystem.Colors.accentBrand)
                                .frame(width: 44)
                        }
                    }
                    
                    Divider().background(DesignSystem.Colors.divider)
                    
                    // Battery Lifespan Display Grid
                    HStack(spacing: DesignSystem.Spacing.comfortable) {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                            Text(lang.currentLanguage == "zh" ? "当前容量健康度" : "Current Health")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text("\(currentHealth)%")
                                .font(DesignSystem.Typography.dataHero)
                                .foregroundColor(currentHealth > 80 ? DesignSystem.Colors.statusHealthy : DesignSystem.Colors.statusWarning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                            Text(lang.currentLanguage == "zh" ? "电池循环次数" : "Cycle Count")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text("\(cycleCount)")
                                .font(DesignSystem.Typography.dataHero)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                            Text(lang.currentLanguage == "zh" ? "运行状况工况" : "Condition")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text(condition == "Normal" ? (lang.currentLanguage == "zh" ? "良好" : "Normal") : (lang.currentLanguage == "zh" ? "服务维保" : "Service"))
                                .font(DesignSystem.Typography.title)
                                .foregroundColor(condition == "Normal" ? DesignSystem.Colors.statusHealthy : DesignSystem.Colors.statusCritical)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if let pred = prediction {
                        Divider().background(DesignSystem.Colors.divider)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.normal) {
                            Text(LanguageManager.shared.tr("lifespan_forecaster"))
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            
                            HStack {
                                Text(lang.currentLanguage == "zh" ? "1 年后 (约新增 150 次循环):" : "In 1 Year (approx. +150 cycles):")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                Spacer()
                                Text("\(pred.predictedHealthOneYear)%")
                                    .font(DesignSystem.Typography.dataHeadline)
                                    .foregroundColor(pred.predictedHealthOneYear > 80 ? DesignSystem.Colors.statusHealthy : DesignSystem.Colors.statusWarning)
                            }
                            
                            HStack {
                                Text(lang.currentLanguage == "zh" ? "2 年后 (约新增 300 次循环):" : "In 2 Years (approx. +300 cycles):")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                                Spacer()
                                Text("\(pred.predictedHealthTwoYears)%")
                                    .font(DesignSystem.Typography.dataHeadline)
                                    .foregroundColor(pred.predictedHealthTwoYears > 80 ? DesignSystem.Colors.statusHealthy : DesignSystem.Colors.statusWarning)
                            }
                            
                            Text(lang.currentLanguage == "zh" ? "警告提示: 电池处于正常衰退区间。开启 80% 充上限限制预计可延长电池寿命约 1.8 倍。" : pred.advice)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.accentBrand)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.comfortable)
                .glassCard()
                
                // ROW 3: App Freezer (Smart Memory Compressor)
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
                    HStack {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                            Text(LanguageManager.shared.tr("app_freezer"))
                                .font(DesignSystem.Typography.title)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Text(LanguageManager.shared.tr("freeze_desc"))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $freezerManager.isEnabled)
                            .toggleStyle(.switch)
                    }
                    
                    if freezerManager.isEnabled {
                        Divider().background(DesignSystem.Colors.divider)
                        
                        HStack {
                            Picker(lang.currentLanguage == "zh" ? "目标进程" : "Target App", selection: $selectedAppBundleId) {
                                Text(lang.currentLanguage == "zh" ? "选择一个正在运行的 App..." : "Select running application...").tag("")
                                ForEach(runningApps, id: \.bundleIdentifier) { app in
                                    if let bundleId = app.bundleIdentifier, let name = app.localizedName {
                                        Text(name).tag(bundleId)
                                    }
                                }
                            }
                            .onTapGesture {
                                refreshRunningApps()
                            }
                            
                            Button(LanguageManager.shared.tr("suspend")) {
                                if !selectedAppBundleId.isEmpty {
                                    freezerManager.config[selectedAppBundleId] = "freeze"
                                    selectedAppBundleId = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.accentBrand)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            
                            Button(lang.currentLanguage == "zh" ? "降频限制" : "Throttle") {
                                if !selectedAppBundleId.isEmpty {
                                    freezerManager.config[selectedAppBundleId] = "throttle"
                                    selectedAppBundleId = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.statusWarning)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                        }
                        
                        // Frozen apps list
                        if !freezerManager.config.isEmpty {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.normal) {
                                ForEach(Array(freezerManager.config.keys), id: \.self) { bundleId in
                                    HStack {
                                        Text(bundleId)
                                            .font(DesignSystem.Typography.dataBody)
                                            .foregroundColor(DesignSystem.Colors.textPrimary)
                                        Spacer()
                                        
                                        let isFreeze = freezerManager.config[bundleId] == "freeze"
                                        Text(isFreeze ? (lang.currentLanguage == "zh" ? "深度冻结 (SIGSTOP)" : "Deep Freeze (SIGSTOP)") : (lang.currentLanguage == "zh" ? "智能降频 (App Nap)" : "Soft Throttle (App Nap)"))
                                            .statusBadge(color: isFreeze ? DesignSystem.Colors.accentBrand : DesignSystem.Colors.statusWarning)
                                        
                                        Button(action: {
                                            freezerManager.config.removeValue(forKey: bundleId)
                                        }) {
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, DesignSystem.Spacing.normal)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.comfortable)
                .glassCard()
                
            }
            .padding(DesignSystem.Spacing.pageMargin)
        }
        .onAppear {
            coolingVM.startPolling()
            fetchBatteryData()
            refreshRunningApps()
            isBclmEnabled = UserDefaults.standard.bool(forKey: "bclm_enabled")
            bclmLimit = UserDefaults.standard.integer(forKey: "bclm_limit")
            if bclmLimit == 0 { bclmLimit = 80 }
        }
        .onDisappear {
            coolingVM.stopPolling()
        }
    }
    
    private func fetchBatteryData() {
        DaemonManager.shared.readBatteryHealth { stats in
            DispatchQueue.main.async {
                self.cycleCount = stats["cycleCount"] as? Int ?? 120
                self.currentHealth = stats["maxCapacityPercent"] as? Int ?? 92
                self.condition = stats["condition"] as? String ?? "Normal"
                
                self.prediction = BatteryHealthPredictor.predict(
                    cycleCount: self.cycleCount,
                    maxCapacityPercent: self.currentHealth,
                    condition: self.condition
                )
            }
        }
    }
    
    private func applyBatteryLimit(enabled: Bool) {
        let limitValue = enabled ? bclmLimit : 100
        DaemonManager.shared.setBatteryChargeLimit(limitValue) { success, error in
            DispatchQueue.main.async {
                if success {
                    UserDefaults.standard.set(enabled, forKey: "bclm_enabled")
                    UserDefaults.standard.set(bclmLimit, forKey: "bclm_limit")
                    self.batteryStatusText = LanguageManager.shared.tr("smc_applied")
                    
                    self.prediction = BatteryHealthPredictor.predict(
                        cycleCount: self.cycleCount,
                        maxCapacityPercent: self.currentHealth,
                        condition: self.condition
                    )
                } else {
                    self.batteryStatusText = error ?? LanguageManager.shared.tr("smc_failed")
                }
            }
        }
    }
    
    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }
}

// MARK: - CoolingViewModel
class CoolingViewModel: ObservableObject {
    @Published var currentRPM: Int = 1800
    @Published var statusMessage: String?
    
    private var timer: Timer?
    
    var fanEngine: FanEngine {
        return FanEngine.shared
    }
    
    func startPolling() {
        refreshFanSpeed()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.refreshFanSpeed()
        }
    }
    
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    private func refreshFanSpeed() {
        guard let proxy = DaemonManager.shared.connect() else { return }
        proxy.readFanSpeeds { [weak self] speeds in
            DispatchQueue.main.async {
                if let first = speeds.first {
                    self?.currentRPM = first
                }
            }
        }
    }
    
    func toggleProactiveMode() {
        fanEngine.isProactiveModeEnabled.toggle()
        statusMessage = fanEngine.isProactiveModeEnabled ? LanguageManager.shared.tr("proactive_enabled") : LanguageManager.shared.tr("proactive_disabled")
    }
    
    func applyManualSpeed() {
        fanEngine.isManualModeEnabled = true
        fanEngine.applyCurrentState()
        statusMessage = String(format: LanguageManager.shared.tr("fan_override_set"), Int(fanEngine.manualFanRPM))
    }
    
    func restoreAutomatic() {
        fanEngine.isManualModeEnabled = false
        fanEngine.applyCurrentState()
        statusMessage = LanguageManager.shared.tr("restored_default")
    }
}

// MARK: - FlowLayout Helper
struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
        height = currentY + rowHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

