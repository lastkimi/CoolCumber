import Foundation

public enum WorkloadCheckPersistenceStatus: String, Equatable, Sendable {
    case ready, storageUnavailable, invalidArchivePreserved, readFailed, writeFailed, limitsExceeded
}

public struct WorkloadCheckPersistenceResult: Equatable, Sendable {
    public let check: WorkloadCheck?
    public let status: WorkloadCheckPersistenceStatus
}

/// The latest explicit check is stored separately from telemetry-history-v1.
/// Invalid/unknown versions are preserved, never silently overwritten.
public struct WorkloadCheckFileRepository {
    public static let maximumBytes = 524_288
    private let fileURL: URL?
    private let fileManager: FileManager

    public init(fileURL: URL?, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load(at date: Date) -> WorkloadCheckPersistenceResult {
        guard let fileURL else { return WorkloadCheckPersistenceResult(check: nil, status: .storageUnavailable) }
        guard fileManager.fileExists(atPath: fileURL.path) else { return WorkloadCheckPersistenceResult(check: nil, status: .ready) }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                return WorkloadCheckPersistenceResult(check: nil, status: .invalidArchivePreserved)
            }
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: Self.maximumBytes + 1), !data.isEmpty else {
                return WorkloadCheckPersistenceResult(check: nil, status: .invalidArchivePreserved)
            }
            guard data.count <= Self.maximumBytes else { return WorkloadCheckPersistenceResult(check: nil, status: .limitsExceeded) }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == WorkloadCheck.schemaVersion else {
                return WorkloadCheckPersistenceResult(check: nil, status: .invalidArchivePreserved)
            }
            try envelope.check.validate(at: date)
            return WorkloadCheckPersistenceResult(check: envelope.check, status: .ready)
        } catch is DecodingError {
            return WorkloadCheckPersistenceResult(check: nil, status: .invalidArchivePreserved)
        } catch is WorkloadCheckError {
            return WorkloadCheckPersistenceResult(check: nil, status: .invalidArchivePreserved)
        } catch { return WorkloadCheckPersistenceResult(check: nil, status: .readFailed) }
    }

    public func persist(_ check: WorkloadCheck, at date: Date) -> WorkloadCheckPersistenceResult {
        guard let fileURL else { return WorkloadCheckPersistenceResult(check: check, status: .storageUnavailable) }
        let previous = load(at: date)
        guard previous.status == .ready else { return WorkloadCheckPersistenceResult(check: check, status: previous.status) }
        do {
            try check.validate(at: date)
            let data = try JSONEncoder().encode(Envelope(version: WorkloadCheck.schemaVersion, check: check))
            guard data.count <= Self.maximumBytes else { return WorkloadCheckPersistenceResult(check: check, status: .limitsExceeded) }
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return WorkloadCheckPersistenceResult(check: check, status: .ready)
        } catch { return WorkloadCheckPersistenceResult(check: check, status: .writeFailed) }
    }

    public func remove() -> WorkloadCheckPersistenceStatus {
        guard let fileURL else { return .storageUnavailable }
        do {
            if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
            return .ready
        } catch { return .writeFailed }
    }

    private struct Envelope: Codable {
        let version: UInt8
        let check: WorkloadCheck
    }
}

public struct WorkloadCheckCSVEncoder {
    public init() {}

    public func data(from check: WorkloadCheck) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let header = "check_id,note,captured_at,phase,cpu_percent,cpu_state,memory_percent,memory_state,thermal_pressure,thermal_state,channel"
        let rows = check.points.map { point in
            [check.id.uuidString, check.note, formatter.string(from: point.capturedAt), point.phase.rawValue,
             number(point.cpuValue), state(point.cpu.availability, usable: point.cpuValue != nil),
             number(point.memoryValue), state(point.memory.availability, usable: point.memoryValue != nil),
             point.thermalValue?.rawValue ?? "", state(point.thermal.availability, usable: point.thermalValue != nil), check.channel.rawValue]
                .map(safeCell).joined(separator: ",")
        }
        return Data(([header] + rows).joined(separator: "\r\n").appending("\r\n").utf8)
    }

    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? ""
    }

    private func state(_ availability: MetricAvailability, usable: Bool) -> String {
        availability == .available && !usable ? "stale_or_untrusted" : availability.rawValue
    }

    private func safeCell(_ input: String) -> String {
        let dangerous = input.trimmingCharacters(in: .whitespacesAndNewlines).first.map { "=+-@".contains($0) } ?? false
        let value = dangerous ? "'" + input : input
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
