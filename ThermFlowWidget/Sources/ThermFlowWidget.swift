import Foundation
import SwiftUI
import ThermFlowCore
import WidgetKit

fileprivate enum WidgetSnapshotState: String {
    case current
    case stale
    case unavailable
}

private struct SharedSnapshotReader {
    static let appGroupIdentifier = "BSKR6CQ765.com.slmcamp.CoolCumber"
    static let relativeDirectory = "Library/Application Support/CoolCumber/Telemetry"
    static let fileName = "system-snapshot-v1.json"
    static let maximumSnapshotAge: TimeInterval = 90
    static let maximumEncodedSnapshotSize = 1_048_576
    static let maximumFanCount = 8

    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func entry(at date: Date) -> SimpleEntry {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            return SimpleEntry(date: date, snapshot: nil, state: .unavailable)
        }

        let fileURL = containerURL
            .appendingPathComponent(Self.relativeDirectory, isDirectory: true)
            .appendingPathComponent(Self.fileName)
        guard let data = readBoundedData(from: fileURL) else {
            return SimpleEntry(date: date, snapshot: nil, state: .unavailable)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SystemSnapshot.self, from: data),
              snapshot.schemaVersion == SystemSnapshot.currentSchemaVersion,
              snapshot.fans.count <= Self.maximumFanCount else {
            return SimpleEntry(date: date, snapshot: nil, state: .unavailable)
        }

        let age = date.timeIntervalSince(snapshot.capturedAt)
        let snapshotIsFresh = age.isFinite
            && age >= 0
            && age <= Self.maximumSnapshotAge
        let state: WidgetSnapshotState
        if !snapshotIsFresh {
            state = .stale
        } else if containsUsableWidgetMetric(snapshot, at: date) {
            state = .current
        } else {
            state = .unavailable
        }
        return SimpleEntry(
            date: date,
            snapshot: snapshot,
            state: state
        )
    }

    private func readBoundedData(from fileURL: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        guard let data = try? handle.read(
            upToCount: Self.maximumEncodedSnapshotSize + 1
        ),
              !data.isEmpty,
              data.count <= Self.maximumEncodedSnapshotSize else {
            return nil
        }
        return data
    }

    /// A fresh file is not enough to claim that telemetry is current. At
    /// least one value the Widget can actually present must also be usable.
    private func containsUsableWidgetMetric(
        _ snapshot: SystemSnapshot,
        at date: Date
    ) -> Bool {
        if snapshot.thermal.cpuTemperature.usableValue(
            at: date,
            maximumAge: Self.maximumSnapshotAge
        ) != nil {
            return true
        }
        if snapshot.thermal.pressure.usableValue(
            at: date,
            maximumAge: Self.maximumSnapshotAge
        ) != nil {
            return true
        }
        if snapshot.memory.usage.usableValue(
            at: date,
            maximumAge: Self.maximumSnapshotAge
        ) != nil {
            return true
        }
        return snapshot.fans.contains {
            $0.currentSpeed.usableValue(
                at: date,
                maximumAge: Self.maximumSnapshotAge
            ) != nil
        }
    }
}

struct Provider: TimelineProvider {
    private let reader = SharedSnapshotReader()

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), snapshot: nil, state: .unavailable)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let now = Date()
        completion(context.isPreview ? placeholder(in: context) : reader.entry(at: now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<SimpleEntry>) -> Void
    ) {
        let now = Date()
        let entry = reader.entry(at: now)
        completion(
            Timeline(
                entries: [entry],
                policy: .after(now.addingTimeInterval(60))
            )
        )
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    fileprivate let snapshot: SystemSnapshot?
    fileprivate let state: WidgetSnapshotState
}

struct CoolCumberWidgetEntryView: View {
    let entry: SimpleEntry

    @Environment(\.widgetFamily) private var widgetFamily

    private let maximumMetricAge: TimeInterval = 90

    private var isCurrent: Bool { entry.state == .current }
    private var isChinese: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    private func t(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }

    private var temperatureText: String {
        guard isCurrent,
              let value = entry.snapshot?.thermal.cpuTemperature.usableValue(
                at: entry.date,
                maximumAge: maximumMetricAge
              ) else {
            return "--°C"
        }
        return String(format: "%.1f°C", value.value)
    }

    private var fanText: String {
        guard isCurrent,
              let sample = entry.snapshot?.fans.first?.currentSpeed,
              let value = sample.usableValue(
                at: entry.date,
                maximumAge: maximumMetricAge
              ) else {
            return t("Unavailable", "不可用")
        }
        return "\(value.value) RPM"
    }

    private var memoryText: String {
        guard isCurrent,
              let value = entry.snapshot?.memory.usage.usableValue(
                at: entry.date,
                maximumAge: maximumMetricAge
              ) else {
            return t("Unavailable", "不可用")
        }
        return String(format: "%.0f%%", value.value)
    }

    private var thermalPressureText: String? {
        guard isCurrent,
              let value = entry.snapshot?.thermal.pressure.usableValue(
                at: entry.date,
                maximumAge: maximumMetricAge
              ) else {
            return nil
        }
        switch value {
        case .nominal: return t("Thermal pressure: Nominal", "系统热压力：正常")
        case .fair: return t("Thermal pressure: Fair", "系统热压力：偏高")
        case .serious: return t("Thermal pressure: Serious", "系统热压力：严重")
        case .critical: return t("Thermal pressure: Critical", "系统热压力：危急")
        }
    }

    private var stateTitle: String {
        switch entry.state {
        case .current: return t("Current", "当前")
        case .stale: return t("Stale", "已过期")
        case .unavailable: return t("Unavailable", "不可用")
        }
    }

    private var stateColor: Color {
        switch entry.state {
        case .current: return .green
        case .stale: return .orange
        case .unavailable: return .secondary
        }
    }

    @ViewBuilder
    var body: some View {
        if #available(macOSApplicationExtension 14.0, *) {
            content
                .containerBackground(.fill.tertiary, for: .widget)
        } else {
            content
                .background(Color.secondary.opacity(0.08))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "fanblades.fill")
                    .foregroundColor(.green)
                Text("CoolCumber")
                    .font(.headline)
                    .bold()
                Spacer()
                Text(stateTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(stateColor)
                Text(temperatureText)
                    .font(.headline.monospacedDigit())
            }

            Divider()

            if widgetFamily == .systemSmall {
                metric(label: t("Memory", "内存"), value: memoryText)
            } else {
                HStack {
                    metric(label: t("Fan", "风扇"), value: fanText)
                    Spacer()
                    metric(
                        label: t("Memory", "内存"),
                        value: memoryText,
                        alignment: .trailing
                    )
                }
            }

            Spacer(minLength: 2)

            footer
        }
        .padding()
    }

    private func metric(
        label: String,
        value: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch entry.state {
        case .current:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(
                    thermalPressureText
                        ?? t("Trusted telemetry is current", "可信遥测数据为当前状态")
                )
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        case .stale:
            HStack(spacing: 4) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundColor(.orange)
                Text(t("Data is stale", "数据已过期"))
                if let capturedAt = entry.snapshot?.capturedAt {
                    Text(capturedAt, style: .relative)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        case .unavailable:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                Text(t(
                    "No current supported reading",
                    "暂无当前可用读数"
                ))
                    .lineLimit(2)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }
}

@main
struct CoolCumberWidget: Widget {
    let kind = "CoolCumberWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CoolCumberWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(
            Locale.current.language.languageCode?.identifier == "zh"
                ? "CoolCumber 监测"
                : "CoolCumber Monitor"
        )
        .description(
            Locale.current.language.languageCode?.identifier == "zh"
                ? "查看可信的 Mac 遥测数据及其新鲜度。"
                : "View trusted Mac telemetry and its freshness."
        )
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
