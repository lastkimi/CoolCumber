import SwiftUI
import Combine

/// SmartBarView V3 - The premium Notch / Menu Bar floating widget.
/// Implements responsive glassmorphism, physical spring mechanics, and jitter-free SF Mono data alignment.
struct SmartBarView: View {
    @State private var isHovering = false
    @State private var isPurging = false
    @State private var purgeStatus: String? = nil
    
    @ObservedObject var daemon = DaemonManager.shared
    @ObservedObject var aiEngine = DiagnosticRuleEngine.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Compact Core Row (Notch Capsule)
            HStack(spacing: DesignSystem.Spacing.normal) {
                // Spinner Fan Icon
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isHovering ? DesignSystem.Colors.accentBrand : DesignSystem.Colors.textSecondary)
                    .rotationEffect(.degrees(isHovering ? 360 : 0))
                    .animation(isHovering ? DesignSystem.Animations.spin : .default, value: isHovering)
                    .frame(width: 18)
                
                // CPU Temperature
                HStack(spacing: 2) {
                    if let temp = daemon.temperatures["CPU"] {
                        Text(String(format: "%.0f", temp))
                            .font(DesignSystem.Typography.dataBody)
                        Text("°C")
                            .font(DesignSystem.Typography.dataMicro)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    } else {
                        Text("--")
                            .font(DesignSystem.Typography.dataBody)
                        Text("°C")
                            .font(DesignSystem.Typography.dataMicro)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(width: 38, alignment: .leading)
                
                // Divider line inside capsule
                Rectangle()
                    .fill(DesignSystem.Colors.divider)
                    .frame(width: 1, height: 14)
                
                // Fan speed in RPM
                HStack(spacing: 1) {
                    let rpmClean = daemon.fanSpeed.replacingOccurrences(of: " RPM", with: "")
                    Text(rpmClean == "0" ? "0" : rpmClean)
                        .font(DesignSystem.Typography.dataCaption)
                    Text("rpm")
                        .font(DesignSystem.Typography.dataMicro)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .foregroundColor(isHovering ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                .frame(width: 58, alignment: .leading)
                
                if isHovering {
                    Spacer()
                    // Thermal Warning Indicator Icon
                    let statusColor = getStatusColor()
                    Image(systemName: aiEngine.currentDiagnosis.status == .healthy ? "sparkles" : "exclamationmark.triangle.fill")
                        .foregroundColor(statusColor)
                        .font(.system(size: 13, weight: .semibold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 32)
            .padding(.horizontal, isHovering ? DesignSystem.Spacing.comfortable : DesignSystem.Spacing.cardPadding)
            
            // 2. Expanded Multi-Telemetry Panel
            if isHovering {
                Divider()
                    .background(DesignSystem.Colors.divider)
                    .padding(.horizontal, DesignSystem.Spacing.cardPadding)
                    .padding(.vertical, DesignSystem.Spacing.normal)
                
                VStack(spacing: DesignSystem.Spacing.comfortable) {
                    // System load grid
                    HStack {
                        // CPU load
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                            Text("CPU Usage")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text(String(format: "%.0f%%", daemon.currentCpuPercent))
                                .font(DesignSystem.Typography.dataHeadline)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        }
                        
                        Spacer()
                        
                        // Memory usage
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                            Text("Memory")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            Text(String(format: "%.0f%%", daemon.currentMemPercent))
                                .font(DesignSystem.Typography.dataHeadline)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        }
                        
                        Spacer()
                        
                        // Diagnosed pressure status
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                            Text("AI Diagnostics")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            
                            let isHealthy = aiEngine.currentDiagnosis.status == .healthy
                            Text(isHealthy ? "COOL" : "HOT")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(isHealthy ? DesignSystem.Colors.statusHealthy : DesignSystem.Colors.statusCritical)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.comfortable)
                    
                    // Quick Action Buttons
                    HStack(spacing: DesignSystem.Spacing.normal) {
                        // Action 1: Instant RAM Purge (Smart Clean)
                        Button(action: {
                            triggerPurge()
                        }) {
                            HStack(spacing: DesignSystem.Spacing.tight) {
                                if isPurging {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 11))
                                }
                                Text(isPurging ? "Cleaning..." : "Smart Clean")
                                    .font(DesignSystem.Typography.headline)
                            }
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.accentBrand)
                            .cornerRadius(DesignSystem.Corners.smallButton)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isPurging)
                        
                        // Action 2: Open Center
                        Button(action: {
                            MenuBarManager.shared.openDashboard()
                        }) {
                            HStack(spacing: DesignSystem.Spacing.tight) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 11))
                                Text("Dashboard")
                                    .font(DesignSystem.Typography.headline)
                            }
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.glassBgHover)
                            .cornerRadius(DesignSystem.Corners.smallButton)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.Corners.smallButton)
                                    .stroke(DesignSystem.Colors.glassBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, DesignSystem.Spacing.cardPadding)
                    .padding(.bottom, DesignSystem.Spacing.cardPadding)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, isHovering ? 6 : 2)
        .frame(width: isHovering ? 320 : 220)
        .background(
            RoundedRectangle(cornerRadius: isHovering ? DesignSystem.Corners.smartBarExpanded : DesignSystem.Corners.smartBarCompact, style: .continuous)
                .fill(isHovering ? DesignSystem.Colors.glassBgHover : DesignSystem.Colors.glassBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: isHovering ? DesignSystem.Corners.smartBarExpanded : DesignSystem.Corners.smartBarCompact, style: .continuous)
                .stroke(isHovering ? DesignSystem.Colors.glassBorderHover : DesignSystem.Colors.glassBorder, lineWidth: 1)
        )
        .windowShadow()
        .onHover { hovering in
            withAnimation(DesignSystem.Animations.snappy) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            if !isHovering {
                MenuBarManager.shared.openDashboard()
            }
        }
        .padding(.top, 4)
        .frame(width: 400, height: 300, alignment: .top)
    }
    
    private func getStatusColor() -> Color {
        switch aiEngine.currentDiagnosis.status {
        case .healthy:
            return DesignSystem.Colors.statusHealthy
        case .warning:
            return DesignSystem.Colors.statusWarning
        case .critical:
            return DesignSystem.Colors.statusCritical
        }
    }
    
    private func triggerPurge() {
        withAnimation {
            isPurging = true
            purgeStatus = nil
        }
        
        daemon.purgeMemory { success, message in
            DispatchQueue.main.async {
                withAnimation {
                    isPurging = false
                    purgeStatus = success ? "Success" : "Failed"
                }
                // Reset status indicator after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        purgeStatus = nil
                    }
                }
            }
        }
    }
}
