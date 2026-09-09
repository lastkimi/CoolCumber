import AppKit
import Combine
import Foundation
import StoreKit
import ThermFlowCore

@MainActor
final class PurchaseController: ObservableObject {
    static let shared = PurchaseController()

    @Published private(set) var entitlement: EntitlementState
    @Published private(set) var activity: PurchaseActivity = .idle
    @Published private(set) var product: Product?

    private var updatesTask: Task<Void, Never>?
    private var betaExpirationTask: Task<Void, Never>?
    private let directVerifier: DirectLicenseVerifier
    private let directStore: DirectLicenseStore
    private let directCheckoutURL: URL?
    private let betaStartsAt: Date?
    private let betaExpiresAt: Date?

    var displayPrice: String? { product?.displayPrice }
    var isProUnlocked: Bool { entitlement.unlocksPro }
    var isBusy: Bool { activity.isBusy }

    var directReadiness: DirectCommerceReadiness {
        #if BETA
        return .unavailable(reason: "Purchasing and license import are disabled in Beta Preview builds.")
        #elseif APPSTORE
        return .unavailable(reason: "Direct licensing is not available in the App Store edition.")
        #else
        guard directCheckoutURL != nil else {
            return .unavailable(
                reason: "This release does not sell Direct licenses; Pro launches on the Mac App Store first."
            )
        }
        guard directVerifier.isConfigured else {
            return .unavailable(reason: "This build does not contain a valid P256 license verification key.")
        }
        return .available
        #endif
    }

    var canPurchase: Bool {
        guard !isBusy, !isProUnlocked else { return false }
        #if BETA
        return false
        #elseif APPSTORE
        return product != nil
        #else
        return directReadiness.isAvailable
        #endif
    }

    var canRestore: Bool {
        guard !isBusy else { return false }
        #if BETA
        return false
        #elseif APPSTORE
        return true
        #else
        return directReadiness.isAvailable
        #endif
    }

    private init(bundle: Bundle = .main) {
        directVerifier = DirectLicenseVerifier(bundle: bundle)
        directStore = DirectLicenseStore()
        directCheckoutURL = Self.validCheckoutURL(in: bundle)
        betaStartsAt = Self.configuredBetaDate(
            forKey: "CoolCumberBetaStartsAt",
            in: bundle
        )
        betaExpiresAt = Self.configuredBetaDate(
            forKey: "CoolCumberBetaExpiresAt",
            in: bundle
        )
        entitlement = .loading

        #if BETA && !APPSTORE
        refreshDirectBetaEntitlement()
        #elseif BETA
        entitlement = .betaUnlocked
        #endif

        #if APPSTORE && !BETA
        updatesTask = Task { [weak self] in
            await self?.observeTransactions()
        }
        #endif

        Task { [weak self] in
            await self?.refresh()
        }
    }

    deinit {
        updatesTask?.cancel()
        betaExpirationTask?.cancel()
    }

    func allows(_ feature: ProFeature) -> Bool {
        isProUnlocked && ProFeature.offered(in: .current).contains(feature)
    }

    func refresh() async {
        #if BETA && !APPSTORE
        refreshDirectBetaEntitlement()
        #elseif BETA
        entitlement = .betaUnlocked
        activity = .idle
        #elseif APPSTORE
        await refreshAppStoreEntitlement()
        #else
        refreshDirectEntitlement()
        #endif
    }

    func purchase() async {
        guard !isProUnlocked else {
            activity = .notice(message: "Pro is already active for this build.")
            return
        }

        #if BETA
        activity = .notice(message: "Beta Preview access is temporary and is not a purchase.")
        #elseif APPSTORE
        await purchaseFromAppStore()
        #else
        openDirectCheckout()
        #endif
    }

    func restorePurchases() async {
        #if BETA
        activity = .notice(message: "Beta Preview does not create or restore purchases.")
        #elseif APPSTORE
        activity = .restoring
        do {
            try await AppStore.sync()
            entitlement = await currentAppStoreEntitlement()
            switch entitlement {
            case .pro:
                activity = .succeeded(message: "Your verified App Store Pro purchase was restored.")
            case .unavailable(let reason):
                activity = .failed(message: reason)
            case .loading, .free, .betaUnlocked:
                activity = .notice(message: "No verified Pro purchase was found for this Apple Account.")
            }
        } catch {
            activity = .failed(message: error.localizedDescription)
        }
        #else
        refreshDirectEntitlement(reportMissing: true)
        #endif
    }

    func activateDirectLicense(_ token: String) throws {
        #if BETA
        let error = DirectLicenseError.commerceUnavailable(
            reason: "License import is disabled in Beta Preview builds."
        )
        activity = .failed(message: error.localizedDescription)
        throw error
        #elseif APPSTORE
        let error = DirectLicenseError.commerceUnavailable(
            reason: "Direct licenses cannot be imported into the App Store edition."
        )
        activity = .failed(message: error.localizedDescription)
        throw error
        #else
        guard directReadiness.isAvailable else {
            let error = DirectLicenseError.commerceUnavailable(
                reason: directReadiness.reason ?? "Direct commerce is not configured for this build."
            )
            activity = .failed(message: error.localizedDescription)
            throw error
        }

        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try directVerifier.verify(token: normalizedToken)
            try directStore.save(normalizedToken)
            entitlement = .pro(source: .directLicense)
            activity = .succeeded(message: "The signed Direct license was verified and stored securely.")
        } catch {
            activity = .failed(message: error.localizedDescription)
            throw error
        }
        #endif
    }

    private func refreshDirectEntitlement(reportMissing: Bool = false) {
        do {
            guard let token = try directStore.read() else {
                entitlement = .free
                activity = reportMissing
                    ? .notice(message: "No saved Direct license was found on this Mac.")
                    : .idle
                return
            }

            _ = try directVerifier.verify(token: token)
            entitlement = .pro(source: .directLicense)
            activity = reportMissing
                ? .succeeded(message: "The saved signed license was verified.")
                : .idle
        } catch {
            entitlement = .unavailable(reason: error.localizedDescription)
            activity = .failed(message: error.localizedDescription)
        }
    }

    private func openDirectCheckout() {
        guard directReadiness.isAvailable, let directCheckoutURL else {
            activity = .failed(
                message: directReadiness.reason ?? "Direct commerce is not configured for this build."
            )
            return
        }

        activity = NSWorkspace.shared.open(directCheckoutURL)
            ? .checkoutOpened
            : .failed(message: "The secure checkout page could not be opened.")
    }

    private static func validCheckoutURL(in bundle: Bundle) -> URL? {
        guard let configuredValue = bundle.object(forInfoDictionaryKey: "CoolCumberCheckoutURL") as? String else {
            return nil
        }

        let rawValue = configuredValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty,
              let components = URLComponents(string: rawValue),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              !["localhost", "127.0.0.1", "::1"].contains(host),
              let url = components.url else {
            return nil
        }
        return url
    }

    private static func configuredBetaDate(
        forKey key: String,
        in bundle: Bundle
    ) -> Date? {
        if let date = bundle.object(forInfoDictionaryKey: key) as? Date {
            return date
        }
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    #if BETA && !APPSTORE
    /// Direct previews fail closed unless the bundle contains a valid, bounded
    /// `CoolCumberBetaStartsAt` / `CoolCumberBetaExpiresAt` ISO-8601 window.
    private func refreshDirectBetaEntitlement(at evaluationDate: Date = Date()) {
        betaExpirationTask?.cancel()
        betaExpirationTask = nil

        switch BetaAccessPolicy().status(
            startsAt: betaStartsAt,
            expiresAt: betaExpiresAt,
            at: evaluationDate
        ) {
        case .active(let expiresAt):
            entitlement = .betaUnlocked
            activity = .idle
            scheduleDirectBetaExpiration(at: expiresAt, relativeTo: evaluationDate)

        case .notStarted(let startsAt):
            entitlement = .free
            activity = .notice(
                message: "This Beta Preview is not active yet (starts \(startsAt.formatted(.iso8601)))."
            )

        case .expired(let expiresAt):
            entitlement = .free
            activity = .notice(
                message: "This Beta Preview expired on \(expiresAt.formatted(.iso8601))."
            )

        case .invalidConfiguration:
            entitlement = .free
            activity = .notice(
                message: "This Direct Beta build does not contain a valid preview access window."
            )
        }
    }

    private func scheduleDirectBetaExpiration(
        at expirationDate: Date,
        relativeTo evaluationDate: Date
    ) {
        let delay = expirationDate.timeIntervalSince(evaluationDate)
        guard delay.isFinite, delay > 0 else {
            refreshDirectBetaEntitlement(at: evaluationDate)
            return
        }
        let nanoseconds = UInt64(min(delay * 1_000_000_000, Double(UInt64.max)))
        betaExpirationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.refreshDirectBetaEntitlement()
        }
    }
    #endif

    #if APPSTORE
    private func refreshAppStoreEntitlement() async {
        activity = .loadingProducts
        entitlement = await currentAppStoreEntitlement()

        do {
            product = try await loadAppStoreProduct()
            if case .unavailable(let reason) = entitlement {
                activity = .failed(message: reason)
            } else {
                activity = .idle
            }
        } catch {
            product = nil
            if entitlement.unlocksPro {
                activity = .notice(
                    message: "Pro is active, but the App Store price is temporarily unavailable."
                )
            } else {
                activity = .failed(message: error.localizedDescription)
            }
        }
    }

    private func loadAppStoreProduct() async throws -> Product {
        let products = try await Product.products(for: [CommerceCatalog.lifetimeProProductID])
        guard let product = products.first(where: { $0.id == CommerceCatalog.lifetimeProProductID }) else {
            throw AppStoreCommerceError.productUnavailable
        }
        guard product.type == .nonConsumable else {
            throw AppStoreCommerceError.invalidProductType
        }
        return product
    }

    private func currentAppStoreEntitlement() async -> EntitlementState {
        var verificationFailure: String?

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard transaction.productID == CommerceCatalog.lifetimeProProductID,
                      transaction.revocationDate == nil else {
                    continue
                }
                return .pro(source: .appStore)

            case .unverified(let transaction, let error):
                guard transaction.productID == CommerceCatalog.lifetimeProProductID else {
                    continue
                }
                verificationFailure = "The App Store Pro entitlement could not be verified: \(error.localizedDescription)"
            }
        }

        if let verificationFailure {
            return .unavailable(reason: verificationFailure)
        }
        return .free
    }

    private func purchaseFromAppStore() async {
        if product == nil {
            await refreshAppStoreEntitlement()
        }

        guard !isProUnlocked else {
            activity = .notice(message: "Pro is already active for this Apple Account.")
            return
        }
        guard let product else {
            if !activity.isFailure {
                activity = .failed(message: AppStoreCommerceError.productUnavailable.localizedDescription)
            }
            return
        }
        guard product.id == CommerceCatalog.lifetimeProProductID,
              product.type == .nonConsumable else {
            activity = .failed(message: AppStoreCommerceError.invalidProductType.localizedDescription)
            return
        }

        activity = .purchasing
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                guard transaction.productID == CommerceCatalog.lifetimeProProductID,
                      transaction.revocationDate == nil else {
                    activity = .failed(message: "The verified transaction did not match the Pro lifetime product.")
                    return
                }
                await transaction.finish()
                entitlement = .pro(source: .appStore)
                activity = .succeeded(message: "Pro was unlocked by a verified App Store purchase.")

            case .success(.unverified(_, let error)):
                let message = "The App Store could not verify this purchase: \(error.localizedDescription)"
                entitlement = .unavailable(reason: message)
                activity = .failed(message: message)

            case .pending:
                activity = .pending

            case .userCancelled:
                activity = .cancelled

            @unknown default:
                activity = .failed(message: "The App Store returned an unknown purchase state.")
            }
        } catch {
            activity = .failed(message: error.localizedDescription)
        }
    }

    private func observeTransactions() async {
        for await result in Transaction.updates {
            guard !Task.isCancelled else { return }

            switch result {
            case .verified(let transaction):
                guard transaction.productID == CommerceCatalog.lifetimeProProductID else {
                    continue
                }
                await transaction.finish()
                entitlement = await currentAppStoreEntitlement()

            case .unverified(let transaction, let error):
                guard transaction.productID == CommerceCatalog.lifetimeProProductID else {
                    continue
                }
                let message = "An App Store transaction could not be verified: \(error.localizedDescription)"
                entitlement = .unavailable(reason: message)
                activity = .failed(message: message)
            }
        }
    }
    #endif
}

#if APPSTORE
private enum AppStoreCommerceError: LocalizedError {
    case productUnavailable
    case invalidProductType

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "The Pro lifetime product is not available from the App Store right now."
        case .invalidProductType:
            return "The App Store product is not configured as a non-consumable lifetime purchase."
        }
    }
}
#endif
