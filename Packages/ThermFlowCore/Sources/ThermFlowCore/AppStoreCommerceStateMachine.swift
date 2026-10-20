import Foundation

/// StoreKit is converted into this small, deterministic evidence model before
/// it can change paid access. This keeps verification, revocation and restore
/// behavior exhaustively testable without manufacturing signed StoreKit JWS
/// payloads in unit tests.
public enum AppStoreTransactionEvidence: Equatable, Sendable {
    case verified(productID: String, isRevoked: Bool)
    case unverified(productID: String, reason: String)

    public var productID: String {
        switch self {
        case .verified(let productID, _), .unverified(let productID, _):
            return productID
        }
    }
}

public enum AppStoreEntitlementResolution: Equatable, Sendable {
    case free
    case pro
    case unavailable(reason: String)
}

public enum AppStorePurchaseOutcome: Equatable, Sendable {
    case verified(productID: String, isRevoked: Bool)
    case unverified(productID: String, reason: String)
    case pending
    case userCancelled
    case unknown
}

public enum AppStorePurchaseTransition: Equatable, Sendable {
    case unlockVerified
    case rejectRevoked
    case rejectUnexpectedProduct
    case rejectUnverified(reason: String)
    case pending
    case cancelled
    case failedUnknown

    /// Only a cryptographically verified transaction owned by this product is
    /// finished here. A revoked transaction is also finished but never unlocks
    /// access, preventing repeated delivery without trusting revoked evidence.
    public var shouldFinishVerifiedTransaction: Bool {
        switch self {
        case .unlockVerified, .rejectRevoked:
            return true
        case .rejectUnexpectedProduct, .rejectUnverified, .pending, .cancelled, .failedUnknown:
            return false
        }
    }
}

public enum AppStoreRestoreTransition: Equatable, Sendable {
    case restored
    case noVerifiedPurchase
    case verificationFailed(reason: String)
}

public enum AppStoreTransactionUpdateTransition: Equatable, Sendable {
    case refreshEntitlements(finishVerifiedTransaction: Bool, wasRevoked: Bool)
    case rejectUnverified(reason: String)
    case ignore
}

public struct AppStoreCommerceStateMachine: Equatable, Sendable {
    public let lifetimeProductID: String

    public init(lifetimeProductID: String) {
        self.lifetimeProductID = lifetimeProductID
    }

    public func resolveEntitlement(
        from evidence: [AppStoreTransactionEvidence]
    ) -> AppStoreEntitlementResolution {
        var matchingVerificationFailure: String?

        for item in evidence where item.productID == lifetimeProductID {
            switch item {
            case .verified(_, let isRevoked):
                if !isRevoked {
                    return .pro
                }
            case .unverified(_, let reason):
                matchingVerificationFailure = matchingVerificationFailure ?? reason
            }
        }

        if let matchingVerificationFailure {
            return .unavailable(reason: matchingVerificationFailure)
        }
        return .free
    }

    public func purchaseTransition(
        for outcome: AppStorePurchaseOutcome
    ) -> AppStorePurchaseTransition {
        switch outcome {
        case .verified(let productID, let isRevoked):
            guard productID == lifetimeProductID else {
                return .rejectUnexpectedProduct
            }
            return isRevoked ? .rejectRevoked : .unlockVerified
        case .unverified(let productID, let reason):
            guard productID == lifetimeProductID else {
                return .rejectUnexpectedProduct
            }
            return .rejectUnverified(reason: reason)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        case .unknown:
            return .failedUnknown
        }
    }

    public func restoreTransition(
        for resolution: AppStoreEntitlementResolution
    ) -> AppStoreRestoreTransition {
        switch resolution {
        case .pro:
            return .restored
        case .free:
            return .noVerifiedPurchase
        case .unavailable(let reason):
            return .verificationFailed(reason: reason)
        }
    }

    public func transactionUpdateTransition(
        for evidence: AppStoreTransactionEvidence
    ) -> AppStoreTransactionUpdateTransition {
        guard evidence.productID == lifetimeProductID else { return .ignore }
        switch evidence {
        case .verified(_, let isRevoked):
            return .refreshEntitlements(
                finishVerifiedTransaction: true,
                wasRevoked: isRevoked
            )
        case .unverified(_, let reason):
            return .rejectUnverified(reason: reason)
        }
    }
}
