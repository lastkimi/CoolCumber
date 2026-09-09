import Foundation

/// Stable RFC 4180 CSV output for trusted history. Every metric value is blank
/// unless the recorded value is explicitly available and fresh at capture.
public struct HistoryCSVEncoder: Equatable, Sendable {
    public let maximumMetricAge: TimeInterval

    public init(maximumMetricAge: TimeInterval = 90) {
        self.maximumMetricAge = maximumMetricAge.isFinite && maximumMetricAge >= 0
            ? maximumMetricAge
            : 90
    }

    public func data(from records: [HistoryRecord]) -> Data {
        Data(string(from: records).utf8)
    }

    public func string(from records: [HistoryRecord]) -> String {
        var rows: [[Cell]] = [header.map(Cell.text)]
        let sortedRecords = records.sorted {
            if $0.capturedAt != $1.capturedAt {
                return $0.capturedAt < $1.capturedAt
            }
            return $0.sequence < $1.sequence
        }
        rows.append(contentsOf: sortedRecords.map(row))
        return rows
            .map { $0.map(Self.render).joined(separator: ",") }
            .joined(separator: "\r\n") + "\r\n"
    }

    /// Escapes untrusted text for CSV and neutralizes spreadsheet formula
    /// prefixes, including prefixes hidden behind whitespace/control/BOM.
    public static func escapeText(_ rawValue: String) -> String {
        let withoutNUL = rawValue.replacingOccurrences(of: "\0", with: "�")
        let significantScalars = withoutNUL.unicodeScalars.drop(while: {
            $0.value == 0xFEFF
                || $0.value < 0x20
                || CharacterSet.whitespacesAndNewlines.contains($0)
        })
        let dangerousFormulaPrefix = significantScalars.first.map {
            $0 == "=" || $0 == "+" || $0 == "-" || $0 == "@"
        } ?? false
        var value = dangerousFormulaPrefix ? "'" + withoutNUL : withoutNUL
        if value.contains(",")
            || value.contains("\"")
            || value.contains("\r")
            || value.contains("\n") {
            value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private enum Cell {
        case blank
        case number(String)
        case text(String)
    }

    private var header: [String] {
        var columns = ["captured_at", "sequence", "channel"]
        for metric in Self.metricNames {
            columns.append("\(metric)_value")
            columns.append("\(metric)_availability")
            columns.append("\(metric)_source")
            columns.append("\(metric)_observed_at")
        }
        columns.append("fans_rpm")
        return columns
    }

    private static let metricNames = [
        "thermal_pressure",
        "cpu_temperature_c",
        "gpu_temperature_c",
        "cpu_usage_percent",
        "memory_used_bytes",
        "memory_total_bytes",
        "memory_usage_percent",
        "memory_pressure",
        "storage_total_bytes",
        "storage_available_bytes",
        "storage_usage_percent",
        "upload_bytes_per_second",
        "download_bytes_per_second",
        "battery_cycle_count",
        "battery_maximum_capacity_percent",
        "battery_condition"
    ]

    private func row(_ record: HistoryRecord) -> [Cell] {
        var cells: [Cell] = [
            .text(Self.timestamp(record.capturedAt)),
            .number(String(record.sequence)),
            .text(record.channel.rawValue)
        ]
        cells += metricCells(record.thermalPressure, at: record.capturedAt) {
            .text($0.rawValue)
        }
        cells += metricCells(record.cpuTemperature, at: record.capturedAt) {
            .number(Self.decimal($0.value))
        }
        cells += metricCells(record.gpuTemperature, at: record.capturedAt) {
            .number(Self.decimal($0.value))
        }
        cells += metricCells(record.cpuUsage, at: record.capturedAt) {
            .number(Self.decimal($0.value))
        }
        cells += metricCells(record.memoryUsed, at: record.capturedAt) {
            .number(String($0.value))
        }
        cells += metricCells(record.memoryTotal, at: record.capturedAt) {
            .number(String($0.value))
        }
        cells += metricCells(record.memoryUsage, at: record.capturedAt) {
            .number(Self.decimal($0.value))
        }
        cells += metricCells(record.memoryPressure, at: record.capturedAt) {
            .text($0.rawValue)
        }
        cells += metricCells(record.storageTotal, at: record.capturedAt) {
            .number(String($0.value))
        }
        cells += metricCells(record.storageAvailable, at: record.capturedAt) {
            .number(String($0.value))
        }
        cells += metricCells(record.storageUsage, at: record.capturedAt) {
            .number(Self.decimal($0.value))
        }
        cells += metricCells(record.uploadRate, at: record.capturedAt) {
            .number(Self.decimal($0.bytesPerSecond))
        }
        cells += metricCells(record.downloadRate, at: record.capturedAt) {
            .number(Self.decimal($0.bytesPerSecond))
        }
        cells += metricCells(record.batteryCycleCount, at: record.capturedAt) {
            .number(String($0))
        }
        cells += metricCells(record.batteryMaximumCapacity, at: record.capturedAt) {
            .number(Self.decimal($0.value))
        }
        cells += metricCells(record.batteryCondition, at: record.capturedAt) {
            .text($0.rawValue)
        }

        let fanValues = record.fans
            .sorted { $0.id < $1.id }
            .compactMap { fan -> String? in
                guard let speed = fan.speed.usableValue(
                    at: record.capturedAt,
                    maximumAge: maximumMetricAge
                ) else {
                    return nil
                }
                return "\(fan.id):\(speed.value)"
            }
        cells.append(fanValues.isEmpty ? .blank : .text(fanValues.joined(separator: ";")))
        return cells
    }

    private func metricCells<Value>(
        _ metric: HistoryMetric<Value>,
        at capturedAt: Date,
        valueCell: (Value) -> Cell
    ) -> [Cell] where Value: Codable & Equatable & Sendable {
        let value = metric.usableValue(
            at: capturedAt,
            maximumAge: maximumMetricAge
        )
        return [
            value.map(valueCell) ?? .blank,
            .text(metric.availability.rawValue),
            .text(metric.provenance.source.rawValue),
            .text(Self.timestamp(metric.observedAt))
        ]
    }

    private static func render(_ cell: Cell) -> String {
        switch cell {
        case .blank:
            return ""
        case .number(let number):
            return number
        case .text(let text):
            return escapeText(text)
        }
    }

    private static func decimal(_ value: Double) -> String {
        var result = String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
