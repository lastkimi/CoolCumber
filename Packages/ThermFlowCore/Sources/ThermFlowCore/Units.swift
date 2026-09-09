import Foundation

public struct TemperatureCelsius: Hashable, Sendable {
    public let value: Double

    public init?(_ value: Double) {
        guard value.isFinite, value >= -273.15 else { return nil }
        self.value = value
    }
}

extension TemperatureCelsius: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(Double.self)
        guard let value = TemperatureCelsius(decoded) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Temperature must be finite and at or above absolute zero."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct FanRPM: Hashable, Sendable {
    public let value: Int

    public init?(_ value: Int) {
        guard value >= 0 else { return nil }
        self.value = value
    }
}

extension FanRPM: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(Int.self)
        guard let value = FanRPM(decoded) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Fan speed cannot be negative."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct ByteCount: Hashable, Codable, Sendable {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }

    public static let zero = ByteCount(0)

    public var kibibytes: Double { Double(value) / 1_024 }
    public var mebibytes: Double { Double(value) / 1_048_576 }
    public var gibibytes: Double { Double(value) / 1_073_741_824 }
}

public struct ByteRate: Hashable, Sendable {
    public let bytesPerSecond: Double

    public init?(_ bytesPerSecond: Double) {
        guard bytesPerSecond.isFinite, bytesPerSecond >= 0 else { return nil }
        self.bytesPerSecond = bytesPerSecond
    }

    public var megabytesPerSecond: Double { bytesPerSecond / 1_000_000 }
    public var mebibytesPerSecond: Double { bytesPerSecond / 1_048_576 }
}

extension ByteRate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(Double.self)
        guard let value = ByteRate(decoded) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Byte rate must be finite and non-negative."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bytesPerSecond)
    }
}

public struct Percent: Hashable, Sendable {
    public let value: Double

    public init?(_ value: Double) {
        guard value.isFinite, (0...100).contains(value) else { return nil }
        self.value = value
    }

    public init?(ratio: Double) {
        guard ratio.isFinite else { return nil }
        self.init(ratio * 100)
    }

    public var ratio: Double { value / 100 }
}

extension Percent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(Double.self)
        guard let value = Percent(decoded) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Percent must be finite and between 0 and 100."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct DurationSeconds: Hashable, Sendable {
    public let value: Double

    public init?(_ value: Double) {
        guard value.isFinite, value >= 0 else { return nil }
        self.value = value
    }
}

extension DurationSeconds: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode(Double.self)
        guard let value = DurationSeconds(decoded) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Duration must be finite and non-negative."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
