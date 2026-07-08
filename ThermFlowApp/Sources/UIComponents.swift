import SwiftUI

/// Reusable premium UI components for CoolCumber V3
/// Designed for high information density, macOS HIG, and smooth physics-based dynamics.

/// 1. SparklineChart - Minimal real-time area chart without gridlines or labels
struct SparklineChart: View {
    var data: [Double]
    var color: Color = DesignSystem.Colors.accentBrand
    
    let yMin: Double = 40.0
    let yMax: Double = 95.0
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Y-Axis Labels
                VStack(alignment: .trailing, spacing: 0) {
                    Text("95°C").font(DesignSystem.Typography.dataCaption).foregroundColor(DesignSystem.Colors.statusCritical)
                    Spacer()
                    Text("75°C").font(DesignSystem.Typography.dataCaption).foregroundColor(DesignSystem.Colors.statusWarning)
                    Spacer()
                    Text("55°C").font(DesignSystem.Typography.dataCaption).foregroundColor(DesignSystem.Colors.statusHealthy)
                    Spacer()
                    Text("40°C").font(DesignSystem.Typography.dataCaption).foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .frame(width: 32)
                .padding(.vertical, 4)
                
                // Chart Area
                GeometryReader { geometry in
                    if data.isEmpty {
                        Text("No Data")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textTertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        let currentMax = max(data.max() ?? yMax, yMax)
                        let currentMin = min(data.min() ?? yMin, yMin)
                        let range = max(currentMax - currentMin, 1.0)
                        
                        ZStack {
                            // Horizontal Grid Lines
                            ForEach([55.0, 75.0, 95.0], id: \.self) { gridVal in
                                let yPct = 1.0 - CGFloat((gridVal - currentMin) / range)
                                if yPct >= 0 && yPct <= 1 {
                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: yPct * geometry.size.height))
                                        path.addLine(to: CGPoint(x: geometry.size.width, y: yPct * geometry.size.height))
                                    }
                                    .stroke(
                                        gridVal == 95.0 ? DesignSystem.Colors.statusCritical.opacity(0.2) :
                                        (gridVal == 75.0 ? DesignSystem.Colors.statusWarning.opacity(0.2) : DesignSystem.Colors.statusHealthy.opacity(0.2)),
                                        style: StrokeStyle(lineWidth: 1, lineCap: .butt, dash: [4, 4])
                                    )
                                }
                            }
                            
                            // Fill area gradient
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                                for index in data.indices {
                                    let x = CGFloat(index) / CGFloat(data.count - 1) * geometry.size.width
                                    let val = min(max(data[index], currentMin), currentMax)
                                    let y = geometry.size.height - CGFloat((val - currentMin) / range) * geometry.size.height
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                                path.closeSubpath()
                            }
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.18), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            
                            // Stroke line
                            Path { path in
                                for index in data.indices {
                                    let x = CGFloat(index) / CGFloat(data.count - 1) * geometry.size.width
                                    let val = min(max(data[index], currentMin), currentMax)
                                    let y = geometry.size.height - CGFloat((val - currentMin) / range) * geometry.size.height
                                    
                                    if index == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.statusHealthy, DesignSystem.Colors.statusWarning, DesignSystem.Colors.statusCritical],
                                    startPoint: .bottom,
                                    endPoint: .top
                                ),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }
                }
            }
            .frame(height: 110)
            
            // X-Axis Time Labels
            HStack {
                Spacer().frame(width: 40)
                Text("-60s")
                Spacer()
                Text("-30s")
                Spacer()
                Text("Now")
            }
            .font(DesignSystem.Typography.dataCaption)
            .foregroundColor(DesignSystem.Colors.textTertiary)
        }
    }
}

/// 2. ThermalGauge - Premium ring progress view for temperature or RPM
struct ThermalGauge: View {
    var value: Double
    var maxValue: Double
    var title: String
    var unit: String
    var statusColor: Color
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.tight) {
            ZStack {
                // Background Track
                Circle()
                    .stroke(DesignSystem.Colors.glassBorder, lineWidth: 5)
                
                // Active Dial Fill
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(max(value / maxValue, 0.0), 1.0)))
                    .stroke(
                        statusColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(Angle(degrees: -90))
                    .animation(DesignSystem.Animations.snappy, value: value)
                
                // Dynamic Text Center
                VStack(spacing: 0) {
                    Text(String(format: "%.0f", value))
                        .font(DesignSystem.Typography.dataTitle)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(unit)
                        .font(DesignSystem.Typography.micro)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .frame(width: 68, height: 68)
            
            Text(title)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
        }
    }
}

/// 3. StatusDot - Pulsing state indicator (green/yellow/red)
struct StatusDot: View {
    var color: Color
    var shouldPulse: Bool = false
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6
    
    var body: some View {
        ZStack {
            if shouldPulse {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .frame(width: 8, height: 8)
                    .onAppear {
                        withAnimation(
                            Animation.easeOut(duration: 1.8)
                                .repeatForever(autoreverses: false)
                        ) {
                            pulseScale = 2.8
                            pulseOpacity = 0.0
                        }
                    }
            }
            
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
    }
}
