import SwiftUI

/// SystemOptimizerView V3 - CleanMyMac-style one-click system optimizer.
/// Merges old SweeperView + RogueEradicatorView + MaintenanceView.
class OptimizerState: ObservableObject {
    static let shared = OptimizerState()
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var selectedOptimizeTab = 0
}

struct SystemOptimizerView: View {
    @StateObject private var sweeper = SweeperEngine.shared
    @StateObject private var rogue = RogueEradicatorEngine.shared
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var state = OptimizerState.shared
    
    // Scan & Process States
    
    // Maintenance Tasks Running States
    @State private var runningSpotlight = false
    @State private var runningDNS = false
    @State private var runningRAM = false
    @State private var maintenanceMsg: String?
    
    // Sweeper Confirmation Alerts
    @State private var showDeleteConfirm = false
    
    // Rogue Confirmation Alerts
    @State private var processToKill: RunningProcessItem?
    @State private var showKillConfirm = false
    @State private var itemToUninstall: RogueItem?
    @State private var showUninstallConfirm = false
    
    var body: some View {
        VStack(spacing: 0) {
            if !state.hasScanned && !state.isScanning {
                // 1. Splash Screen: Large central "Scan" button
                VStack(spacing: DesignSystem.Spacing.comfortable) {
                    Spacer()
                    
                    // Large Breathing Scan Button
                    Button(action: {
                        triggerGlobalScan()
                    }) {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.accentBrand.opacity(0.12))
                                .frame(width: 140, height: 140)
                                .scaleEffect(state.isScanning ? 1.2 : 1.0)
                            
                            Circle()
                                .stroke(DesignSystem.Colors.accentBrand, lineWidth: 2)
                                .frame(width: 120, height: 120)
                            
                            VStack(spacing: DesignSystem.Spacing.tight) {
                                Image(systemName: "sparkles.radial")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(DesignSystem.Colors.accentBrand)
                                Text(lang.tr("scan_system"))
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Text(lang.tr("scan_desc"))
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                
            } else if state.isScanning {
                // 2. Scanning Progress Screen
                VStack(spacing: DesignSystem.Spacing.comfortable) {
                    Spacer()
                    
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(DesignSystem.Colors.accentBrand)
                    
                    Text(lang.tr("scanning"))
                        .font(DesignSystem.Typography.title)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text(lang.tr("scan_progress"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                
            } else {
                // 3. Scan Results View (Tabbed details)
                VStack(spacing: 0) {
                    HStack(spacing: DesignSystem.Spacing.normal) {
                        ForEach(0..<4) { index in
                            let label = [lang.tr("space_clean"), lang.tr("running_processes"), lang.tr("rogue_agents"), lang.tr("maintenance")][index]
                            Button(action: {
                                state.selectedOptimizeTab = index
                            }) {
                                Text(label)
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(state.selectedOptimizeTab == index ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(state.selectedOptimizeTab == index ? DesignSystem.Colors.accentBrand : DesignSystem.Colors.glassBgHover)
                                    .cornerRadius(DesignSystem.Corners.normal)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.Corners.normal)
                                            .stroke(state.selectedOptimizeTab == index ? Color.clear : DesignSystem.Colors.glassBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.pageMargin)
                    .padding(.top, DesignSystem.Spacing.comfortable)
                    .padding(.bottom, DesignSystem.Spacing.normal)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sectionGap) {
                            
                            switch state.selectedOptimizeTab {
                            case 0:
                                // space cleaner view
                                spaceCleanTab()
                            case 1:
                                // rogue processes view
                                processInspectorTab()
                            case 2:
                                // startup items view
                                launchAgentsTab()
                            case 3:
                                // maintenance tasks view
                                maintenanceTab()
                            default:
                                EmptyView()
                            }
                        }
                        .padding(DesignSystem.Spacing.pageMargin)
                    }
                    
                    // Footer Re-Scan Action Bar
                    Divider().background(DesignSystem.Colors.divider)
                    HStack {
                        Spacer()
                        Button(lang.tr("re_scan")) {
                            triggerGlobalScan()
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, DesignSystem.Spacing.pageMargin)
                        .padding(.vertical, DesignSystem.Spacing.normal)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(isPresented: $showDeleteConfirm) {
            Alert(
                title: Text(lang.tr("clean_cache_title")),
                message: Text(lang.tr("clean_cache_msg")),
                primaryButton: .destructive(Text(lang.tr("clean_trash"))) {
                    sweeper.cleanSelected()
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $processToKill) { proc in
            // Process Termination Confirmation Dialog
            VStack(spacing: DesignSystem.Spacing.comfortable) {
                Text(lang.tr("force_kill_title"))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.statusCritical)
                
                Text(String(format: lang.tr("force_kill_msg"), proc.name, proc.pid))
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: DesignSystem.Spacing.normal) {
                    Button(lang.tr("cancel")) {
                        processToKill = nil
                    }
                    .buttonStyle(.bordered)
                    
                    Button(lang.tr("kill_process")) {
                        rogue.killProcess(pid: proc.pid)
                        processToKill = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.statusCritical)
                }
            }
            .padding(DesignSystem.Spacing.pageMargin)
            .frame(width: 320, height: 160)
            .glassCard()
        }
        .sheet(item: $itemToUninstall) { item in
            // Startup Agent Uninstall Confirmation Dialog
            VStack(spacing: DesignSystem.Spacing.comfortable) {
                Text(lang.tr("uninstall_service_title"))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.statusCritical)
                
                Text(String(format: lang.tr("uninstall_service_msg"), item.label))
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: DesignSystem.Spacing.normal) {
                    Button(lang.tr("cancel")) {
                        itemToUninstall = nil
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        rogue.uninstall(item: item)
                        itemToUninstall = nil
                    }) {
                        Text(lang.tr("uninstall"))
                            .font(DesignSystem.Typography.headline)
                            .frame(minWidth: 80, minHeight: 28)
                            .padding(.horizontal, DesignSystem.Spacing.normal)
                    }
                    .background(DesignSystem.Colors.statusCritical)
                    .foregroundColor(DesignSystem.Colors.textInverse)
                    .cornerRadius(DesignSystem.Corners.smallButton)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .padding(DesignSystem.Spacing.pageMargin)
            .frame(width: 320, height: 160)
            .glassCard()
        }
    }
    
    // MARK: - Sub-tab: Space Clean (Purge Cache files)
    @ViewBuilder
    private func spaceCleanTab() -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
            HStack {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                    Text(lang.tr("developer_caches"))
                        .font(DesignSystem.Typography.title)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(lang.tr("cache_desc"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                Spacer()
                
                if !sweeper.items.isEmpty {
                    Button(lang.tr("clean_selected")) {
                        showDeleteConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accentBrand)
                    .foregroundColor(DesignSystem.Colors.textInverse)
                }
            }
            
            if sweeper.items.isEmpty {
                VStack(spacing: DesignSystem.Spacing.normal) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.Colors.statusHealthy)
                    Text(lang.tr("space_clean_done"))
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: DesignSystem.Spacing.normal) {
                    ForEach($sweeper.items) { $item in
                        HStack {
                            Toggle("", isOn: $item.isSelected)
                                .toggleStyle(.checkbox)
                            
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                                Text(item.name)
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(item.path)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(item.sizeString)
                                .font(DesignSystem.Typography.dataBody)
                                .foregroundColor(DesignSystem.Colors.accentBrand)
                                .padding(.horizontal, DesignSystem.Spacing.normal)
                                .padding(.vertical, DesignSystem.Spacing.tight)
                                .background(DesignSystem.Colors.accentBrand.opacity(0.12))
                                .cornerRadius(DesignSystem.Corners.normal)
                        }
                        .padding(DesignSystem.Spacing.comfortable)
                        .glassCard()
                    }
                }
            }
        }
    }
    
    // MARK: - Sub-tab: Process Inspector (CPU/RAM process scanner)
    @ViewBuilder
    private func processInspectorTab() -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                Text(lang.tr("process_ai"))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(lang.tr("process_desc"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            // Safety Banner
            HStack(spacing: DesignSystem.Spacing.normal) {
                Image(systemName: "sparkles")
                    .foregroundColor(DesignSystem.Colors.accentAI)
                Text(lang.tr("ai_banner"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .padding(DesignSystem.Spacing.comfortable)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.Colors.accentAI.opacity(0.12))
            .cornerRadius(DesignSystem.Corners.normal)
            
            VStack(spacing: DesignSystem.Spacing.normal) {
                ForEach(rogue.runningProcesses) { proc in
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.normal) {
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                                Text(proc.name)
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(String(format: lang.tr("pid_label"), proc.pid))
                                    .font(DesignSystem.Typography.dataCaption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                            }
                            Spacer()
                            
                            HStack(spacing: DesignSystem.Spacing.comfortable) {
                                Text(String(format: "%.1f%% CPU", proc.cpu))
                                    .font(DesignSystem.Typography.dataCaption)
                                    .foregroundColor(proc.cpu > 50 ? DesignSystem.Colors.statusCritical : DesignSystem.Colors.textSecondary)
                                
                                Text(String(format: "%.0f MB RAM", proc.memMB))
                                    .font(DesignSystem.Typography.dataCaption)
                                    .foregroundColor(proc.memMB > 1000 ? DesignSystem.Colors.statusCritical : DesignSystem.Colors.textSecondary)
                                
                                Button(lang.tr("ask_ai")) {
                                    rogue.askAIAboutProcess(item: proc)
                                }
                                .buttonStyle(.bordered)
                                
                                Button(action: {
                                    processToKill = proc
                                    showKillConfirm = true
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(DesignSystem.Colors.statusCritical)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Expanded AI Explanation
                        if let explanation = proc.aiExplanation {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                                Divider().background(DesignSystem.Colors.divider)
                                Text(lang.tr("ai_eval"))
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.accentAI)
                                    .padding(.top, DesignSystem.Spacing.tight)
                                Text(explanation)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(DesignSystem.Spacing.comfortable)
                    .glassCard()
                }
            }
        }
    }
    
    // MARK: - Sub-tab: Launch Agents (Autostart services)
    @ViewBuilder
    private func launchAgentsTab() -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                Text(lang.tr("rogue_title"))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(lang.tr("rogue_desc"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            if let result = rogue.uninstallResult {
                Text(result)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(result.contains("Error") || result.contains("Failed") ? DesignSystem.Colors.statusCritical : DesignSystem.Colors.statusHealthy)
                    .padding(DesignSystem.Spacing.normal)
                    .background((result.contains("Error") || result.contains("Failed") ? DesignSystem.Colors.statusCritical : DesignSystem.Colors.statusHealthy).opacity(0.12))
                    .cornerRadius(DesignSystem.Corners.normal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if rogue.items.isEmpty {
                VStack(spacing: DesignSystem.Spacing.normal) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.Colors.statusHealthy)
                    Text(lang.tr("no_rogue"))
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: DesignSystem.Spacing.normal) {
                    ForEach(rogue.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                                Text(item.program.isEmpty ? item.label : item.program)
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                Text(item.label)
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            
                            Button(lang.tr("uninstall")) {
                                itemToUninstall = item
                                showUninstallConfirm = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DesignSystem.Colors.statusCritical)
                            .foregroundColor(DesignSystem.Colors.textInverse)
                        }
                        .padding(DesignSystem.Spacing.comfortable)
                        .glassCard()
                    }
                }
            }
        }
    }
    
    // MARK: - Sub-tab: Maintenance (Spotlight, DNS, RAM)
    @ViewBuilder
    private func maintenanceTab() -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                Text(lang.tr("maintenance_title"))
                    .font(DesignSystem.Typography.title)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(lang.tr("maintenance_desc"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            if let msg = maintenanceMsg {
                Text(msg)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.accentBrand)
                    .padding(DesignSystem.Spacing.normal)
                    .background(DesignSystem.Colors.accentBrand.opacity(0.12))
                    .cornerRadius(DesignSystem.Corners.normal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            VStack(spacing: DesignSystem.Spacing.normal) {
                // Task 1: Rebuild Spotlight
                maintenanceRow(
                    title: lang.tr("rebuild_spotlight"),
                    desc: lang.tr("spotlight_desc"),
                    icon: "magnifyingglass.circle",
                    isRunning: $runningSpotlight
                ) {
                    executeSpotlight()
                }
                
                // Task 2: Flush DNS Cache
                maintenanceRow(
                    title: lang.tr("flush_dns"),
                    desc: lang.tr("dns_desc"),
                    icon: "network",
                    isRunning: $runningDNS
                ) {
                    executeDNS()
                }
                
                // Task 3: Inactive Memory Purge
                maintenanceRow(
                    title: lang.tr("purge_ram"),
                    desc: lang.tr("ram_desc"),
                    icon: "memorychip",
                    isRunning: $runningRAM
                ) {
                    executePurgeRAM()
                }
            }
        }
    }
    
    @ViewBuilder
    private func maintenanceRow(title: String, desc: String, icon: String, isRunning: Binding<Bool>, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.comfortable) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(DesignSystem.Colors.accentBrand)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                Text(title)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                Text(desc)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: action) {
                Group {
                    if isRunning.wrappedValue {
                        ProgressView().scaleEffect(0.8)
                            .frame(width: 80, height: 28)
                    } else {
                        Text(lang.tr("run"))
                            .font(DesignSystem.Typography.headline)
                            .frame(width: 80, height: 28)
                    }
                }
                .background(isRunning.wrappedValue ? DesignSystem.Colors.glassBg : DesignSystem.Colors.accentBrand)
                .foregroundColor(isRunning.wrappedValue ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textInverse)
                .cornerRadius(DesignSystem.Corners.smallButton)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRunning.wrappedValue)
        }
        .padding(DesignSystem.Spacing.comfortable)
        .glassCard()
    }
    
    // MARK: - Operation Helpers
    private func triggerGlobalScan() {
        withAnimation {
            state.isScanning = true
            state.hasScanned = false
        }
        
        // Scan sweeper cache size
        sweeper.scan()
        
        // Scan rogue services & processes
        rogue.scan()
        rogue.scanProcesses()
        
        // Simulate a 1.5 second diagnostics progress feel
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                state.isScanning = false
                state.hasScanned = true
            }
        }
    }
    
    private func executeSpotlight() {
        runningSpotlight = true
        maintenanceMsg = nil
        DaemonManager.shared.runMaintenance(type: "spotlight") { success, error in
            DispatchQueue.main.async {
                runningSpotlight = false
                maintenanceMsg = success ? "Spotlight Index rebuild triggered successfully." : "Error: \(error ?? "Unknown")"
            }
        }
    }
    
    private func executeDNS() {
        runningDNS = true
        maintenanceMsg = nil
        DaemonManager.shared.runMaintenance(type: "dns") { success, error in
            DispatchQueue.main.async {
                runningDNS = false
                maintenanceMsg = success ? "DNS cache flushed." : "Error: \(error ?? "Unknown")"
            }
        }
    }
    
    private func executePurgeRAM() {
        runningRAM = true
        maintenanceMsg = nil
        DaemonManager.shared.purgeMemory { success, error in
            DispatchQueue.main.async {
                runningRAM = false
                maintenanceMsg = success ? "Memory purged successfully." : "Error: \(error ?? "Unknown")"
            }
        }
    }
}
