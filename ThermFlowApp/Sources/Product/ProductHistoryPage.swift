import AppKit
import Charts
import SwiftUI
import ThermFlowCore
import UniformTypeIdentifiers

struct ProductHistoryPage: View {
    @ObservedObject private var data = ProductDataCoordinator.shared
    @ObservedObject private var commerce = PurchaseController.shared
    @State private var selectedRange: ProductHistoryRange = .day
    @State private var threshold = HealthAlertConfiguration.defaultTemperatureThresholdCelsius
    @State private var showsDeleteConfirmation = false
    @State private var exportMessage: String?

    let isChinese: Bool
    let showPro: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                accessCard
                trendCard
                alertCard
                dataControls
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .onAppear {
            data.start()
            threshold = data.alertConfiguration.temperatureThresholdCelsius
        }
        .onChange(of: data.alertConfiguration) { configuration in
            threshold = configuration.temperatureThresholdCelsius
        }
        .alert(
            isChinese ? "删除本地历史？" : "Delete local history?",
            isPresented: $showsDeleteConfirmation
        ) {
            Button(isChinese ? "取消" : "Cancel", role: .cancel) {}
            Button(isChinese ? "删除" : "Delete", role: .destructive) {
                data.removeAllHistory()
            }
        } message: {
            Text(isChinese
                 ? "这会删除 CoolCumber 的本地遥测历史；不会更改系统设置。"
                 : "This removes CoolCumber's local telemetry history and does not change system settings.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(isChinese ? "历史与提醒" : "History & Alerts")
                    .font(.system(size: 22, weight: .semibold))
                Text(isChinese
                     ? "以五分钟粒度保存紧凑本地快照；缺失和过期读数不会变成 0。"
                     : "Compact five-minute snapshots stay on this Mac; missing and stale readings never become zeroes.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessCard: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: commerce.isProUnlocked ? "checkmark.seal.fill" : "clock")
                .font(.title2)
                .foregroundColor(commerce.isProUnlocked ? .green : .blue)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(accessTitle)
                    .font(.headline)
                Text(accessDetail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if !commerce.isProUnlocked {
                Button(isChinese ? "查看 Pro" : "View Pro", action: showPro)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var trendCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(format: isChinese ? "%d 条可信快照" : "%d trusted snapshots", filteredRecords.count))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Picker(isChinese ? "时间范围" : "Range", selection: $selectedRange) {
                        ForEach(ProductHistoryRange.available(isPro: commerce.isProUnlocked)) { range in
                            Text(range.title(isChinese: isChinese)).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: commerce.isProUnlocked ? 260 : 100)
                }

                if chartPoints.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text(isChinese ? "正在等待可信历史" : "Waiting for trusted history")
                            .font(.headline)
                        Text(isChinese
                             ? "开始监测后，首个包含真实可用指标的快照会显示在这里。"
                             : "After monitoring starts, the first snapshot containing a real available metric will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    Chart(chartPoints) { point in
                        LineMark(
                            x: .value(isChinese ? "时间" : "Time", point.date),
                            y: .value(point.series, point.value)
                        )
                        .foregroundStyle(by: .value(isChinese ? "指标" : "Metric", point.series))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    .chartYScale(domain: 0...110)
                    .chartLegend(position: .bottom, alignment: .leading)
                    .frame(minHeight: 280)
                    .accessibilityLabel(isChinese ? "可信历史趋势图" : "Trusted history trend chart")
                }

                if data.historyStatus != .ready {
                    Label(historyStatusText, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding(.vertical, 6)
        } label: {
            Label(isChinese ? "本地趋势" : "On-device trends", systemImage: "chart.line.uptrend.xyaxis")
        }
    }

    private var alertCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(
                    isChinese ? "严重热压力时发送本地通知" : "Notify me about serious thermal pressure",
                    isOn: Binding(
                        get: { data.alertsAreDesired },
                        set: { enabled in
                            if enabled && !data.canConfigureAlerts {
                                showPro()
                            } else {
                                data.setAlertsEnabled(enabled)
                            }
                        }
                    )
                )

                if data.alertsAreDesired && !data.alertsAreEffectivelyEnabled {
                    Label(
                        isChinese
                            ? "提醒偏好已保留；恢复 Pro 后会重新生效。"
                            : "Your alert preference is saved and will resume when Pro is restored.",
                        systemImage: "pause.circle"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Text(isChinese
                     ? "App Store 与官网版都只依据 macOS 报告的新鲜严重/危急热压力。官网版若存在可信实测 CPU 温度，还会使用下面的阈值。"
                     : "Both editions use only fresh serious or critical thermal pressure reported by macOS. Direct also uses the threshold below when a trusted measured CPU temperature exists.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if data.isDirectEdition {
                    Divider()

                    HStack {
                        Text(isChinese ? "CPU 温度阈值" : "CPU temperature threshold")
                        Spacer()
                        Text("\(Int(threshold.rounded()))°C")
                            .font(.system(.body, design: .monospaced))
                    }

                    Slider(
                        value: $threshold,
                        in: HealthAlertConfiguration.minimumTemperatureThresholdCelsius...HealthAlertConfiguration.maximumTemperatureThresholdCelsius,
                        step: 1
                    ) { editing in
                        if !editing {
                            data.setTemperatureThreshold(threshold)
                        }
                    }
                    .disabled(!data.canConfigureAlerts)
                }

                if data.alertAuthorization == .denied {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Label(
                            isChinese ? "通知权限已在系统设置中关闭" : "Notifications are disabled in System Settings",
                            systemImage: "bell.slash"
                        )
                        .font(.caption)
                        .foregroundColor(.orange)

                        Spacer()

                        Button(isChinese ? "打开系统设置" : "Open System Settings") {
                            if let url = URL(
                                string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                            ) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link)
                    }
                }

                if let message = data.alertMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack {
                Label(isChinese ? "可信健康提醒" : "Trusted health alerts", systemImage: "bell.badge")
                Spacer()
                Text(data.canConfigureAlerts ? "Pro" : (isChinese ? "需要 Pro" : "Pro required"))
                    .font(.caption.weight(.medium))
                    .foregroundColor(data.canConfigureAlerts ? .green : .secondary)
            }
        }
    }

    private var dataControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        if data.canExport {
                            exportCSV()
                        } else {
                            showPro()
                        }
                    } label: {
                        Label(isChinese ? "导出 CSV…" : "Export CSV…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(filteredRecords.isEmpty)

                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label(isChinese ? "删除本地历史…" : "Delete local history…", systemImage: "trash")
                    }
                    .disabled(data.records.isEmpty)

                    Spacer()
                }

                Text(isChinese
                     ? "导出只包含本机现有记录；不可用或过期的指标保持为空，并保留状态与来源列。"
                     : "Exports contain only records on this Mac. Unavailable or stale values stay blank with their status and source columns preserved.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        } label: {
            Label(isChinese ? "数据控制" : "Data controls", systemImage: "externaldrive")
        }
    }

    private var filteredRecords: [HistoryRecord] {
        let effectiveRange = ProductHistoryRange.available(isPro: commerce.isProUnlocked)
            .contains(selectedRange) ? selectedRange : .day
        let cutoff = Date().addingTimeInterval(-effectiveRange.duration)
        return data.records.filter { $0.capturedAt >= cutoff && $0.capturedAt <= Date() }
    }

    private var chartPoints: [ProductHistoryPoint] {
        var points: [ProductHistoryPoint] = []
        for record in filteredRecords {
            if let value = record.cpuTemperature.usableValue(at: record.capturedAt, maximumAge: 90) {
                points.append(ProductHistoryPoint(date: record.capturedAt, value: value.value, series: isChinese ? "CPU 温度 °C" : "CPU temperature °C"))
            }
            if let value = record.cpuUsage.usableValue(at: record.capturedAt, maximumAge: 90) {
                points.append(ProductHistoryPoint(date: record.capturedAt, value: value.value, series: isChinese ? "CPU 使用 %" : "CPU usage %"))
            }
            if let value = record.memoryUsage.usableValue(at: record.capturedAt, maximumAge: 90) {
                points.append(ProductHistoryPoint(date: record.capturedAt, value: value.value, series: isChinese ? "内存使用 %" : "Memory use %"))
            }
        }
        return SeriesDownsamplingPolicy.evenlySpaced(
            points,
            maximumCount: 1_800,
            seriesID: \ProductHistoryPoint.series
        )
    }

    private var accessTitle: String {
        if case .betaUnlocked = commerce.entitlement {
            return isChinese ? "免费 Beta：30 天历史已临时启用" : "Free Beta: 30-day history temporarily enabled"
        }
        return commerce.isProUnlocked
            ? (isChinese ? "Pro：最长 30 天本地历史" : "Pro: up to 30 days of local history")
            : (isChinese ? "Free：最长 24 小时本地历史" : "Free: up to 24 hours of local history")
    }

    private var accessDetail: String {
        commerce.isProUnlocked
            ? (isChinese
                ? "包括可信健康提醒与 CSV 导出；所有数据仍留在本机。"
                : "Includes trusted health alerts and CSV export; all data still stays on this Mac.")
            : (isChinese
                ? "实时监测永久免费。升级只延长保留时间并开放提醒和导出。"
                : "Live monitoring stays free. Pro only extends retention and enables alerts and export.")
    }

    private var historyStatusText: String {
        switch data.historyStatus {
        case .ready:
            return ""
        case .appGroupUnavailable:
            return isChinese ? "当前签名无法访问本地历史容器。" : "This signature cannot access the local history container."
        case .corruptArchive:
            return isChinese ? "本地历史文件已损坏；旧记录未被信任。" : "The local archive is corrupt; old records were not trusted."
        case .readFailed:
            return isChinese ? "无法读取本地历史。" : "Local history could not be read."
        case .writeFailed:
            return isChinese ? "无法保存最新历史。" : "The latest history could not be saved."
        case .limitsExceeded:
            return isChinese ? "本地历史超过安全上限。" : "Local history exceeded its safety limits."
        }
    }

    private func exportCSV() {
        guard let csvData = data.csvDataForExport() else {
            showPro()
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "CoolCumber-History-\(Self.exportDate.string(from: Date())).csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csvData.write(to: url, options: .atomic)
                exportMessage = isChinese ? "CSV 已导出。" : "CSV exported."
            } catch {
                exportMessage = isChinese ? "CSV 导出失败。" : "CSV export failed."
            }
        }
    }

    private static let exportDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum ProductHistoryRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        }
    }

    func title(isChinese: Bool) -> String {
        switch self {
        case .day: return isChinese ? "24 小时" : "24h"
        case .week: return isChinese ? "7 天" : "7d"
        case .month: return isChinese ? "30 天" : "30d"
        }
    }

    static func available(isPro: Bool) -> [ProductHistoryRange] {
        isPro ? allCases : [.day]
    }
}

private struct ProductHistoryPoint: Identifiable {
    let date: Date
    let value: Double
    let series: String

    var id: String {
        "\(date.timeIntervalSinceReferenceDate.bitPattern)-\(series)"
    }
}
