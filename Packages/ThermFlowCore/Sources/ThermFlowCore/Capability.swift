import Foundation

public enum DistributionChannel: String, Codable, CaseIterable, Sendable {
    case direct
    case appStore
}

public enum CapabilityID: String, Codable, CaseIterable, Sendable {
    case thermalPressure
    case cpuUsage
    case memoryUsage
    case diskSpace
    case networkRate
    case cpuTemperature
    case gpuTemperature
    case fanRead
    case fanControl
    case batteryHealth
    case batteryChargeLimit
    case processRead
    case processControl
    case launchServiceManagement
    case systemMaintenance
    case widgetSync
    case remoteAI
}

public enum CapabilityAvailability: String, Codable, CaseIterable, Sendable {
    case available
    case unsupported
    case notPresent
    case authorizationRequired
    case temporarilyUnavailable
    case unknown
}

public struct CapabilityState: Codable, Equatable, Sendable {
    public let availability: CapabilityAvailability
    public let reasonCode: String?
    public let evaluatedAt: Date

    public init(
        availability: CapabilityAvailability,
        reasonCode: String? = nil,
        evaluatedAt: Date
    ) {
        self.availability = availability
        self.reasonCode = reasonCode
        self.evaluatedAt = evaluatedAt
    }

    public static func available(at date: Date) -> CapabilityState {
        CapabilityState(availability: .available, evaluatedAt: date)
    }

    public static func unknown(at date: Date) -> CapabilityState {
        CapabilityState(availability: .unknown, evaluatedAt: date)
    }

    public static func unsupported(
        reasonCode: String,
        at date: Date
    ) -> CapabilityState {
        CapabilityState(
            availability: .unsupported,
            reasonCode: reasonCode,
            evaluatedAt: date
        )
    }

    public func isUsable(
        at evaluationDate: Date,
        maximumAge: TimeInterval
    ) -> Bool {
        guard availability == .available,
              maximumAge.isFinite,
              maximumAge >= 0 else {
            return false
        }
        let age = evaluationDate.timeIntervalSince(evaluatedAt)
        return age.isFinite && age >= 0 && age <= maximumAge
    }
}

public struct CapabilitySet: Equatable, Sendable {
    public static let defaultMaximumAge: TimeInterval = 30

    public let channel: DistributionChannel
    private var states: [CapabilityID: CapabilityState]

    public init(
        channel: DistributionChannel,
        states: [CapabilityID: CapabilityState] = [:]
    ) {
        self.channel = channel
        self.states = states
    }

    public func state(for capability: CapabilityID) -> CapabilityState {
        states[capability] ?? .unknown(at: .distantPast)
    }

    public func allows(
        _ capability: CapabilityID,
        at evaluationDate: Date = Date(),
        maximumAge: TimeInterval = Self.defaultMaximumAge
    ) -> Bool {
        state(for: capability).isUsable(
            at: evaluationDate,
            maximumAge: maximumAge
        )
    }

    public mutating func set(
        _ state: CapabilityState,
        for capability: CapabilityID
    ) {
        states[capability] = state
    }

    public func setting(
        _ state: CapabilityState,
        for capability: CapabilityID
    ) -> CapabilitySet {
        var copy = self
        copy.set(state, for: capability)
        return copy
    }

    public static func baseline(
        for channel: DistributionChannel,
        evaluatedAt: Date
    ) -> CapabilitySet {
        var states = Dictionary(
            uniqueKeysWithValues: CapabilityID.allCases.map {
                ($0, CapabilityState.unknown(at: evaluatedAt))
            }
        )

        if channel == .appStore {
            let privilegedCapabilities: [CapabilityID] = [
                .cpuTemperature,
                .gpuTemperature,
                .fanRead,
                .fanControl,
                .batteryChargeLimit,
                .processRead,
                .processControl,
                .launchServiceManagement,
                .systemMaintenance
            ]
            for capability in privilegedCapabilities {
                states[capability] = .unsupported(
                    reasonCode: "appSandbox",
                    at: evaluatedAt
                )
            }
        }

        return CapabilitySet(channel: channel, states: states)
    }
}

extension CapabilitySet: Codable {
    private enum CodingKeys: String, CodingKey {
        case channel
        case states
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        channel = try container.decode(DistributionChannel.self, forKey: .channel)
        let rawStates = try container.decode([String: CapabilityState].self, forKey: .states)
        var decodedStates: [CapabilityID: CapabilityState] = [:]
        for (rawID, state) in rawStates {
            guard let id = CapabilityID(rawValue: rawID) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .states,
                    in: container,
                    debugDescription: "Unknown capability identifier: \(rawID)"
                )
            }
            decodedStates[id] = state
        }
        states = decodedStates
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channel, forKey: .channel)
        let rawStates = Dictionary(
            uniqueKeysWithValues: states.map { ($0.key.rawValue, $0.value) }
        )
        try container.encode(rawStates, forKey: .states)
    }
}
