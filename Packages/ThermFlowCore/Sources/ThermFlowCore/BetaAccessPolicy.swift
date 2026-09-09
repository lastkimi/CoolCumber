import Foundation

public enum BetaAccessStatus: Equatable, Sendable {
    case active(expiresAt: Date)
    case notStarted(startsAt: Date)
    case expired(expiresAt: Date)
    case invalidConfiguration
}

/// A fail-closed, bounded preview window. A build must carry both dates and the
/// complete window may not exceed 45 days.
public struct BetaAccessPolicy: Equatable, Sendable {
    public static let maximumDuration: TimeInterval = 45 * 24 * 60 * 60

    public let maximumDuration: TimeInterval

    public init(maximumDuration: TimeInterval = Self.maximumDuration) {
        self.maximumDuration = maximumDuration
    }

    public func status(
        startsAt: Date?,
        expiresAt: Date?,
        at evaluationDate: Date
    ) -> BetaAccessStatus {
        guard let startsAt,
              let expiresAt,
              maximumDuration.isFinite,
              maximumDuration > 0 else {
            return .invalidConfiguration
        }

        let windowDuration = expiresAt.timeIntervalSince(startsAt)
        guard windowDuration.isFinite,
              windowDuration > 0,
              windowDuration <= maximumDuration else {
            return .invalidConfiguration
        }
        guard evaluationDate >= startsAt else {
            return .notStarted(startsAt: startsAt)
        }
        guard evaluationDate < expiresAt else {
            return .expired(expiresAt: expiresAt)
        }
        return .active(expiresAt: expiresAt)
    }
}
