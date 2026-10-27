import AppKit
import Charts
import SwiftUI
import ThermFlowCore
import UniformTypeIdentifiers

struct WorkloadCheckPage: View {
    @ObservedObject private var controller = WorkloadCheckController.shared
    @ObservedObject private var commerce = PurchaseController.shared
    @State private var note = ""
    @State private var confirmReplacement = false
    @State private var confirmClear = false
    @State private var exportMessage: String?
    let isChinese: Bool
    let showPro: () -> Void

    private func t(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if controller.check == nil { HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(t("THERMAL CHECK", "热状态检查"), systemImage: "waveform.path.ecg.rectangle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.teal)
                        Text(t("Observe a change, not a guess.", "用真实观察，对比前后变化。"))
                            .font(.title2.weight(.semibold))
                        Text(t("A short, read-only comparison of CPU use, memory use and macOS thermal pressure.",
                               "短时、只读地对比 CPU 使用、内存使用与 macOS 系统热压力。"))
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Label(t("On this Mac", "仅保存在本机"), systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("coolcumber.check.top")
                }

                if let check = controller.check {
                    recordingHeader(check).accessibilityIdentifier("coolcumber.check.top")
                    observationChart(check)
                    HStack(alignment: .top, spacing: 16) {
                        phaseSummary(check.baselineSummary, title: t("Baseline", "基线"))
                        phaseSummary(check.comparisonSummary, title: t("Follow-up", "对比阶段"))
                    }
                    if check.phase == .completed { deltaSummary(check) }
                    if check.phase == .interrupted {
                        Label(t("Interrupted check — collected readings are kept, but this is not a completed comparison.",
                                "检查已中断：保留实际读数，但不会把它当作完整对比。"), systemImage: "pause.circle")
                            .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    emptyState
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(t("What this check can tell you", "这项检查能告诉你什么"), systemImage: "info.circle")
                        .font(.headline)
                    Text(t("It records observations, not causation or a benchmark score. Make any workload change yourself, then mark the next phase. Missing, stale or untrusted samples leave gaps. No fan, process or power controls run.",
                           "检查记录观察结果，不推断因果，也不生成跑分。请自行调整工作负载，再标记下一阶段。缺失、过期或不可信样本会留下空白；不会执行风扇、进程或电源控制。"))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(t("Each phase needs three fresh observations over at least 20 seconds. The full check is limited to five minutes. The latest check is kept for up to 24 hours; continuous history is managed separately.",
                           "每阶段至少需要三个新鲜样本并覆盖 20 秒；整次检查最长五分钟。最近检查最长保留 24 小时；连续历史单独管理。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.instrumentPanel()

                if controller.persistenceStatus != .ready {
                    Label(t("The check cannot currently be saved. Any older unreadable document is preserved; this view may be memory-only.",
                            "当前无法保存检查。较早的不可读文件仍保留；本次结果可能仅在内存中。"), systemImage: "externaldrive.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if let message = controller.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if let exportMessage { Text(exportMessage).font(.callout).foregroundStyle(.secondary) }
            }
            .padding(24).frame(maxWidth: 1120, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .confirmationDialog(t("Replace the latest check?", "替换最近的检查？"), isPresented: $confirmReplacement) {
            Button(t("Replace and start", "替换并开始"), role: .destructive) { controller.begin(note: note, replacingConfirmed: true) }
        } message: {
            Text(t("Only the latest explicit check is replaced. Continuous history and purchase access are unchanged.",
                   "仅替换最近一次手动检查；连续历史与购买权益不变。"))
        }
        .confirmationDialog(t("Clear the latest check?", "清除最近的检查？"), isPresented: $confirmClear) {
            Button(t("Clear check", "清除检查"), role: .destructive) { controller.clearConfirmed() }
        } message: {
            Text(t("This removes this app's saved check file, including any unreadable prior check. Continuous history and purchases are unchanged.",
                   "将移除本应用的检查保存文件，包括可能存在的不可读旧检查。连续历史与购买权益不变。"))
        }
        .onAppear { controller.start() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                step("1", t("Record a baseline", "记录基线"), t("Keep your current workload running.", "保持当前工作负载。"))
                step("2", t("Mark a change", "标记变化"), t("Make a change yourself, then mark the boundary.", "自行调整后，标记阶段边界。"))
                step("3", t("Review observations", "查看观察结果"), t("Compare real samples and their coverage.", "对比真实样本与采样覆盖情况。"))
            }
            TextField(t("Optional context, up to 80 characters", "可选背景说明，最多 80 字符"), text: $note)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("coolcumber.check.note")
            Label(t("There is no saved check yet. Starting does not change any system settings.", "尚无已保存检查；开始检查不会更改系统设置。"), systemImage: "waveform")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.instrumentPanel()
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(number).font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(.teal)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func recordingHeader(_ check: WorkloadCheck) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(phaseTitle(check.phase)).font(.title3.weight(.semibold)).accessibilityIdentifier("coolcumber.check.phase")
                Text(check.note.isEmpty ? t("Read-only workload observation", "只读工作负载观察") : check.note)
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(t("Started ", "开始时间 ") + check.startedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(String(format: "%02d:%02d", Int(controller.elapsed) / 60, Int(controller.elapsed) % 60))
                    .font(.title2.monospacedDigit())
                Text(t("\(check.usablePointCount) usable observations", "\(check.usablePointCount) 个可用观察点"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(controller.isSaving ? t("Saving locally…", "正在本机保存…")
                     : (controller.persistenceStatus == .ready ? t("Saved locally", "已保存在本机") : t("Not saved", "尚未保存")))
                    .font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("coolcumber.check.saved")
            }
        }.instrumentPanel()
    }

    @ViewBuilder
    private func observationChart(_ check: WorkloadCheck) -> some View {
        let entries = chartEntries(check)
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Observed CPU & memory use", "CPU 与内存使用观察")).font(.headline)
            if entries.count < 2 {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line").font(.title).foregroundStyle(.teal)
                    Text(t("Waiting for fresh readings — no sample is invented.", "等待新鲜读数；不会补造样本。"))
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(entries) { entry in
                    LineMark(x: .value(t("Time", "时间"), entry.date), y: .value("%", entry.value),
                             series: .value("segment", entry.segment))
                        .foregroundStyle(by: .value(t("Signal", "指标"), entry.metric))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: entry.isMemory ? [5, 3] : []))
                }
                .chartYScale(domain: 0...100)
                .chartForegroundStyleScale(domain: [t("CPU", "CPU"), t("Memory", "内存")], range: [Color.teal, Color.purple])
                .chartLegend(position: .bottom)
                .frame(height: 140)
                .accessibilityLabel(t("Actual CPU and memory observations. Dashed line is memory; unavailable values create gaps.",
                                     "真实 CPU 与内存观察；虚线表示内存，不可用读数留空。"))
            }
        }.instrumentPanel()
    }

    private func phaseSummary(_ summary: WorkloadPhaseSummary, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            summaryRow("CPU", value: percent(summary.meanCPU), count: summary.cpuSampleCount)
            summaryRow(t("Memory", "内存"), value: percent(summary.meanMemory), count: summary.memorySampleCount)
            summaryRow(t("Thermal peak", "最高热压力"), value: pressure(summary.highestThermalPressure), count: summary.thermalSampleCount)
        }.frame(maxWidth: .infinity, alignment: .leading).instrumentPanel()
    }

    private func summaryRow(_ title: String, value: String, count: Int) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.medium))
            Text(t("\(count) samples", "\(count) 个样本")).font(.caption2).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func deltaSummary(_ check: WorkloadCheck) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(t("Comparison recorded", "对比已记录"), systemImage: "checkmark.seal")
                .font(.headline).foregroundStyle(.teal)
            HStack(alignment: .top, spacing: 24) {
                Text(t("CPU difference: ", "CPU 差值：") + difference(check.baselineSummary.meanCPU, check.comparisonSummary.meanCPU))
                Text(t("Memory difference: ", "内存差值：") + difference(check.baselineSummary.meanMemory, check.comparisonSummary.meanMemory))
            }
            Text(t("Differences describe these observations only; they do not prove that your change caused them.",
                   "差值仅描述本次观察，不证明由你的操作导致。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.instrumentPanel().accessibilityElement(children: .contain).accessibilityIdentifier("coolcumber.check.summary")
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if let check = controller.check, check.isRecording {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("\(controller.currentPhaseSampleCount) fresh observations in this phase", "本阶段 \(controller.currentPhaseSampleCount) 个新鲜观察点"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(check.phase == .baseline ? t("Make your change before marking the next phase.", "调整负载后，再标记下一阶段。")
                                                 : t("Collect enough follow-up samples to finish.", "采集足够的对比样本后完成。"))
                        .font(.caption2).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(t("Stop", "停止")) { controller.stop() }.accessibilityIdentifier("coolcumber.check.stop")
                Button(check.phase == .baseline ? t("Mark comparison", "标记对比阶段") : t("Finish check", "完成检查")) { controller.advance() }
                    .buttonStyle(.borderedProminent).disabled(!check.canAdvance).accessibilityIdentifier("coolcumber.check.advance")
            } else {
                Button(controller.check == nil ? t("Start baseline", "开始记录基线") : t("New check", "新建检查")) {
                    if controller.check != nil { confirmReplacement = true }
                    else { controller.begin(note: note, replacingConfirmed: false) }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("coolcumber.check.start")
                if controller.check != nil {
                    Button(t("Clear check", "清除检查")) { confirmClear = true }.accessibilityIdentifier("coolcumber.check.clear")
                }
                Spacer()
                Button(commerce.allows(.historyExport) ? t("Export check CSV", "导出检查 CSV") : t("Export check CSV — Pro", "导出检查 CSV — Pro")) { exportCSV() }
                    .disabled(controller.check?.points.isEmpty ?? true).accessibilityIdentifier("coolcumber.check.export")
            }
        }.padding(16).background(.bar)
    }

    private func exportCSV() {
        guard let data = controller.csvDataIfAllowed() else { showPro(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "CoolCumber-check.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            exportMessage = t("Check exported to the file you selected.", "检查已导出到你选择的文件。")
        } catch { exportMessage = t("The export could not be saved; the local check is unchanged.", "无法保存导出文件；本地检查未更改。") }
    }

    private func phaseTitle(_ phase: WorkloadCheckPhase) -> String {
        switch phase {
        case .baseline: return t("Recording baseline", "正在记录基线")
        case .comparison: return t("Recording follow-up", "正在记录对比阶段")
        case .completed: return t("Check complete", "检查已完成")
        case .interrupted: return t("Check interrupted", "检查已中断")
        }
    }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? t("No usable samples", "无可用样本") }
    private func difference(_ before: Double?, _ after: Double?) -> String {
        guard let before, let after else { return t("Insufficient matched samples", "缺少对应样本") }
        return String(format: "%+.1f", after - before) + t(" percentage points", " 个百分点")
    }
    private func pressure(_ value: ThermalPressure?) -> String {
        switch value {
        case .nominal: return t("Nominal", "正常")
        case .fair: return t("Fair", "升高")
        case .serious: return t("Serious", "严重")
        case .critical: return t("Critical", "危急")
        case nil: return t("No usable samples", "无可用样本")
        }
    }

    private struct ChartEntry: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let metric: String
        let isMemory: Bool
        let segment: String
    }
    private func chartEntries(_ check: WorkloadCheck) -> [ChartEntry] {
        var entries: [ChartEntry] = []
        for isMemory in [false, true] {
            var segment = 0
            var lastDate: Date?
            var lastPhase: WorkloadCheckPhase?
            var seen = Set<Date>()
            for point in check.points {
                guard let value = isMemory ? point.memoryValue : point.cpuValue else { segment += 1; lastDate = nil; continue }
                let date = isMemory ? point.memory.observedAt : point.cpu.observedAt
                guard seen.insert(date).inserted else { continue }
                if point.phase != lastPhase || lastDate.map({ date.timeIntervalSince($0) > 25 }) == true { segment += 1 }
                let metric = isMemory ? t("Memory", "内存") : "CPU"
                entries.append(ChartEntry(id: "\(metric)-\(point.sequence)", date: date, value: value,
                    metric: metric, isMemory: isMemory, segment: "\(metric)-\(segment)"))
                lastDate = date
                lastPhase = point.phase
            }
        }
        return entries
    }
}

private extension View {
    func instrumentPanel() -> some View {
        self.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}
