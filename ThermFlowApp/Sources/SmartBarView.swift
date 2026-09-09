import SwiftUI

/// Optional notch surface backed by the same trusted presentation model as the
/// menu bar and main window. It never exposes mutating or maintenance actions.
struct SmartBarView: View {
    @ObservedObject private var model = ProductUIModel.shared
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var isChinese: Bool { language.currentLanguage == "zh" }

    var body: some View {
        VStack(spacing: 0) {
            compactRow

            if isHovering {
                Divider()
                    .padding(.horizontal, 14)

                HStack(spacing: 18) {
                    compactMetric(
                        title: isChinese ? "风扇" : "Fan",
                        state: model.fanSpeed,
                        unit: "RPM"
                    )
                    compactMetric(
                        title: "CPU",
                        state: model.cpuUsage,
                        unit: "%"
                    )
                    compactMetric(
                        title: isChinese ? "内存" : "Memory",
                        state: model.memoryPressure,
                        unit: "%"
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Button {
                    MenuBarManager.shared.openDashboard()
                } label: {
                    Label(
                        isChinese ? "打开 CoolCumber" : "Open CoolCumber",
                        systemImage: "rectangle.on.rectangle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .frame(width: isHovering ? 340 : 230)
        .background(.ultraThickMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: isHovering ? 16 : 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: isHovering ? 16 : 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            if reduceMotion {
                isHovering = hovering
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    isHovering = hovering
                }
            }
            SmartBarManager.shared.updateExpandedState(hovering)
        }
        .onTapGesture {
            MenuBarManager.shared.openDashboard()
        }
        .accessibilityAction {
            MenuBarManager.shared.openDashboard()
        }
        .onAppear {
            model.startReadOnlyMonitoring()
        }
    }

    private var compactRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf.fill")
                .foregroundColor(model.overallHealth.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.healthTitle(isChinese: isChinese))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(temperatureSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: isHovering ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }

    private var temperatureSummary: String {
        switch model.temperature {
        case .available:
            return "\(model.temperature.displayedValue) °C"
        case .stale:
            return isChinese
                ? "旧读数 · \(model.temperature.displayedValue) °C"
                : "Stale · \(model.temperature.displayedValue) °C"
        case .loading:
            return isChinese ? "正在读取温度" : "Reading temperature"
        case .unavailable:
            return isChinese ? "温度不可用" : "Temperature unavailable"
        }
    }

    private func compactMetric(
        title: String,
        state: ProductMetricState,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(valueText(for: state, unit: unit))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func valueText(for state: ProductMetricState, unit: String) -> String {
        switch state {
        case .available:
            return "\(state.displayedValue) \(unit)"
        case .stale:
            return "~\(state.displayedValue) \(unit)"
        case .loading:
            return "…"
        case .unavailable:
            return isChinese ? "不可用" : "Unavailable"
        }
    }
}
