import Foundation

enum DistributionEdition: String, Sendable {
    case direct
    case appStore

    static var current: DistributionEdition {
        #if APPSTORE
        return .appStore
        #else
        return .direct
        #endif
    }

    func displayName(isChinese: Bool) -> String {
        switch self {
        case .direct:
            return isChinese ? "官网直装版" : "Direct Edition"
        case .appStore:
            return isChinese ? "App Store 监测版" : "App Store Monitor"
        }
    }
}

enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    case longHistory
    case advancedAlerts
    case historyExport

    var id: String { rawValue }

    func title(isChinese: Bool) -> String {
        switch self {
        case .longHistory:
            return isChinese ? "延长本地历史" : "Extended on-device history"
        case .advancedAlerts:
            return isChinese ? "可信健康提醒" : "Trusted health alerts"
        case .historyExport:
            return isChinese ? "历史导出" : "History export"
        }
    }

    func detail(isChinese: Bool) -> String {
        switch self {
        case .longHistory:
            return isChinese
                ? "在这台 Mac 上最长保留 30 天紧凑历史，而 Free 保留 24 小时。"
                : "Keeps up to 30 days of compact history on this Mac instead of the Free 24-hour window."
        case .advancedAlerts:
            return isChinese
                ? "只基于应用能够验证的新鲜读数提供可配置本地提醒。"
                : "Adds configurable local alerts based only on fresh readings the app can verify."
        case .historyExport:
            return isChinese
                ? "将本机现有历史导出为防表格公式注入的 CSV 文件。"
                : "Exports the available on-device history as a spreadsheet-safe CSV file."
        }
    }

    static func offered(in _: DistributionEdition) -> [ProFeature] {
        allCases
    }
}

enum ProSource: String, Codable, Sendable {
    case appStore
    case directLicense
}

enum EntitlementState: Equatable, Sendable {
    case loading
    case free
    case betaUnlocked
    case pro(source: ProSource)
    case unavailable(reason: String)

    var unlocksPro: Bool {
        switch self {
        case .betaUnlocked, .pro:
            return true
        case .loading, .free, .unavailable:
            return false
        }
    }

    func statusTitle(isChinese: Bool) -> String {
        switch self {
        case .loading:
            return isChinese ? "正在检查权益" : "Checking access"
        case .free:
            return "Free"
        case .betaUnlocked:
            return isChinese ? "免费 Beta" : "Beta Preview"
        case .pro:
            return "Pro"
        case .unavailable:
            return isChinese ? "Pro 暂不可用" : "Pro unavailable"
        }
    }
}

enum PurchaseActivity: Equatable, Sendable {
    case idle
    case loadingProducts
    case purchasing
    case restoring
    case checkoutOpened
    case pending
    case succeeded(message: String)
    case notice(message: String)
    case cancelled
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .loadingProducts, .purchasing, .restoring:
            return true
        case .idle, .checkoutOpened, .pending, .succeeded, .notice, .cancelled, .failed:
            return false
        }
    }

    var message: String? {
        switch self {
        case .idle, .loadingProducts, .purchasing, .restoring:
            return nil
        case .checkoutOpened:
            return "Secure checkout opened in your browser. The app remains Free until you import a valid signed license."
        case .pending:
            return "The purchase is pending App Store approval. Pro will unlock only after Apple verifies the transaction."
        case .succeeded(let message), .notice(let message), .failed(let message):
            return message
        case .cancelled:
            return "The purchase was cancelled. No charge or entitlement change was recorded."
        }
    }

    var isFailure: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}

enum DirectCommerceReadiness: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var reason: String? {
        if case .unavailable(let reason) = self {
            return reason
        }
        return nil
    }
}

enum CommerceCatalog {
    static let lifetimeProProductID = "com.slmcamp.CoolCumber.pro.lifetime"
    static let directLicenseAccount = "coolcumber-pro-license-v1"
}
