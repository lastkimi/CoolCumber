import AppKit
import SwiftUI

struct PaywallView: View {
    @StateObject private var commerce = PurchaseController.shared
    @ObservedObject private var language = LanguageManager.shared
    @State private var directLicenseToken = ""
    @Environment(\.dismiss) private var dismiss

    private let edition = DistributionEdition.current
    private var isChinese: Bool { language.currentLanguage == "zh" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    accessCard
                    purchaseSection
                    benefitsSection
                    activitySection
                    trustFooter
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(24)
            }
        }
        .frame(minWidth: 540, idealWidth: 680, minHeight: 620, idealHeight: 720)
        .task {
            await commerce.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("CoolCumber")
                    .font(.title2.weight(.semibold))
                Text(edition.displayName(isChinese: isChinese))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            Text(commerce.entitlement.statusTitle(isChinese: isChinese))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.14))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())
                .accessibilityLabel(
                    t("Current access: ", "当前权益：")
                    + commerce.entitlement.statusTitle(isChinese: isChinese)
                )

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("Close", "关闭"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var accessCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: statusSymbol)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(commerce.entitlement.statusTitle(isChinese: isChinese))
                        .font(.headline)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } label: {
            Label(t("Your access", "你的权益"), systemImage: "person.crop.circle.badge.checkmark")
        }
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("What is included", "包含内容"))
                .font(.title3.weight(.semibold))

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    entitlementFeatureRow(
                        title: t("Clear system health overview", "清晰的系统健康概览"),
                        detail: t(
                            "Free includes supported live readings and explicit unavailable states.",
                            "Free 包含受支持的实时读数与明确的不可用状态。"
                        ),
                        symbol: "waveform.path.ecg",
                        tint: .blue
                    )
                    Divider()
                    entitlementFeatureRow(
                        title: t("No simulated hardware data", "不模拟硬件数据"),
                        detail: t(
                            "Missing sensors and unsupported controls stay visibly unavailable.",
                            "缺失的传感器和不支持的控制能力会明确显示为不可用。"
                        ),
                        symbol: "checkmark.shield",
                        tint: .green
                    )
                    Divider()
                    entitlementFeatureRow(
                        title: t("Free access does not expire", "Free 权益永不过期"),
                        detail: t(
                            "Declining Pro never removes the core monitoring experience.",
                            "不购买 Pro 也不会失去核心监测体验。"
                        ),
                        symbol: "infinity",
                        tint: .secondary
                    )
                }
                .padding(.vertical, 4)
            } label: {
                Text("Free")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ProFeature.offered(in: edition)) { feature in
                        entitlementFeatureRow(
                            title: feature.title(isChinese: isChinese),
                            detail: feature.detail(isChinese: isChinese),
                            symbol: "checkmark.circle.fill",
                            tint: .green
                        )

                        if feature.id != ProFeature.offered(in: edition).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            } label: {
                HStack(spacing: 8) {
                    Text("Pro")
                        .font(.headline)
                    if case .betaUnlocked = commerce.entitlement {
                        Text(t("temporarily enabled for Beta Preview", "Beta 期间临时启用"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Text(t(
                "Feature availability still depends on the edition, the Mac model, and verified system capabilities. Pro never makes an unsupported control appear available.",
                "功能可用性仍取决于发行版本、Mac 机型和已验证的系统能力；Pro 不会让不支持的控制功能伪装成可用。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var purchaseSection: some View {
        #if BETA
        betaPurchaseSection
        #elseif APPSTORE
        appStorePurchaseSection
        #else
        directPurchaseSection
        #endif
    }

    private var betaPurchaseSection: some View {
        GroupBox {
            Label {
                Text(t(
                    "Beta Preview temporarily enables eligible Pro features for testing. It is not a purchase, does not create a receipt, and does not promise permanent access.",
                    "Beta Preview 会临时开放符合条件的 Pro 功能用于测试；这不是购买，不会生成收据，也不代表永久权益。"
                ))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "testtube.2")
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        } label: {
            Text(t("Beta Preview", "免费 Beta"))
                .font(.headline)
        }
    }

    #if APPSTORE
    private var appStorePurchaseSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text(t(
                    "Pro is a one-time, non-consumable App Store purchase. The price below comes directly from StoreKit for your current storefront.",
                    "Pro 是一次性非消耗型 App Store 购买；下方价格直接来自当前商店地区的 StoreKit。"
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !commerce.isProUnlocked {
                    Button {
                        Task { await commerce.purchase() }
                    } label: {
                        HStack(spacing: 8) {
                            if commerce.activity == .purchasing {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(appStorePurchaseButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!commerce.canPurchase)
                    .accessibilityHint(t(
                        "Starts the Apple purchase sheet. Pro unlocks only after StoreKit verifies the transaction.",
                        "打开 Apple 购买表单；只有 StoreKit 验证交易后才会解锁 Pro。"
                    ))
                }

                Button {
                    Task { await commerce.restorePurchases() }
                } label: {
                    if commerce.activity == .restoring {
                        Label(t("Restoring purchases", "正在恢复购买"), systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label(t("Restore purchases", "恢复购买"), systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!commerce.canRestore)

                Text(t(
                    "A pending, cancelled, missing, or unverified transaction never unlocks Pro.",
                    "等待中、已取消、缺失或未验证的交易绝不会解锁 Pro。"
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            Text(commerce.isProUnlocked
                 ? t("App Store purchase", "App Store 购买")
                 : t("Unlock Pro", "解锁 Pro"))
                .font(.headline)
        }
    }

    private var appStorePurchaseButtonTitle: String {
        if let price = commerce.displayPrice {
            return t("Unlock Pro — \(price)", "解锁 Pro — \(price)")
        }
        if commerce.activity == .loadingProducts {
            return t("Loading localized price", "正在读取本地价格")
        }
        return t("Pro price unavailable", "Pro 价格暂不可用")
    }
    #endif

    #if !APPSTORE
    private var directPurchaseSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                switch commerce.directReadiness {
                case .available:
                    directConfiguredControls
                case .unavailable(let reason):
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t("Purchasing is unavailable", "购买暂不可用"))
                                .font(.headline)
                            Text(localizedDirectReadinessReason(reason))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.orange)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            Text(commerce.isProUnlocked
                 ? t("Direct license", "官网版授权")
                 : t("Unlock Pro", "解锁 Pro"))
                .font(.headline)
        }
    }

    private var directConfiguredControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !commerce.isProUnlocked {
                Button {
                    Task { await commerce.purchase() }
                } label: {
                    Label(t("Open secure checkout", "打开安全结账页"), systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!commerce.canPurchase)
                .accessibilityHint(t(
                    "Opens the configured HTTPS checkout in your browser. This action alone does not unlock Pro.",
                    "在浏览器中打开已配置的 HTTPS 结账页；仅执行此操作不会解锁 Pro。"
                ))
            }

            Text(t(
                "Checkout completion does not unlock this app by itself. Return with the signed license token issued for your purchase and import it below.",
                "完成结账本身不会解锁应用；请返回并在下方导入随购买签发的已签名授权令牌。"
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField(t("Signed license token", "已签名授权令牌"), text: $directLicenseToken)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .accessibilityHint(t(
                    "Paste the signed license token received after checkout.",
                    "粘贴结账后收到的签名授权令牌。"
                ))

            HStack(spacing: 12) {
                Button(t("Import signed license", "导入已签名授权")) {
                    importDirectLicense()
                }
                .disabled(
                    commerce.isBusy
                        || directLicenseToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button(t("Re-check saved license", "重新验证已保存授权")) {
                    Task { await commerce.restorePurchases() }
                }
                .disabled(!commerce.canRestore)
            }

            Text(t(
                "The token must carry a valid P256 signature. Invalid, expired, or malformed tokens never unlock Pro.",
                "令牌必须包含有效的 P256 签名；无效、过期或格式错误的令牌绝不会解锁 Pro。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func importDirectLicense() {
        do {
            try commerce.activateDirectLicense(directLicenseToken)
            directLicenseToken = ""
        } catch {
            // PurchaseController publishes the exact verification or storage failure.
        }
    }
    #endif

    @ViewBuilder
    private var activitySection: some View {
        if commerce.activity.isBusy {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(busyActivityTitle)
                    .font(.subheadline)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        } else if let message = localizedActivityMessage {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: commerce.activity.isFailure ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(commerce.activity.isFailure ? Color.red : Color.accentColor)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (commerce.activity.isFailure ? Color.red : Color.accentColor).opacity(0.08)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
        }
    }

    private var trustFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(t("Purchases are verified before access changes", "权益变更前会先验证购买"), systemImage: "checkmark.seal")
                .font(.subheadline.weight(.medium))
            Text(t(
                "CoolCumber never treats an opened checkout page, a button tap, or an unverified transaction as a successful purchase.",
                "CoolCumber 不会把打开结账页、点击按钮或未验证交易当作购买成功。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func entitlementFeatureRow(
        title: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        switch commerce.entitlement {
        case .loading:
            return "hourglass"
        case .free:
            return "leaf"
        case .betaUnlocked:
            return "testtube.2"
        case .pro:
            return "checkmark.seal.fill"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch commerce.entitlement {
        case .loading:
            return .secondary
        case .free:
            return .blue
        case .betaUnlocked:
            return .orange
        case .pro:
            return .green
        case .unavailable:
            return .red
        }
    }

    private var statusDetail: String {
        switch commerce.entitlement {
        case .loading:
            return t("CoolCumber is checking locally available entitlement evidence.", "CoolCumber 正在检查本机可用的权益凭据。")
        case .free:
            return t("Core monitoring remains available without payment.", "无需付费即可继续使用核心监测。")
        case .betaUnlocked:
            return t(
                "Eligible Pro features are temporarily enabled for evaluation. This is not a purchase or a permanent license.",
                "符合条件的 Pro 功能已临时开放用于评估；这不是购买或永久授权。"
            )
        case .pro(let source):
            switch source {
            case .appStore:
                return t("A verified App Store non-consumable purchase is active.", "已启用通过验证的 App Store 非消耗型购买。")
            case .directLicense:
                return t("A valid signed Direct license is stored in this Mac's Keychain.", "有效的官网版签名授权已存入此 Mac 的钥匙串。")
            }
        case .unavailable(let reason):
            return reason
        }
    }

    private var busyActivityTitle: String {
        switch commerce.activity {
        case .loadingProducts:
            return t("Checking product and entitlement information…", "正在检查产品与权益信息…")
        case .purchasing:
            return t("Waiting for the App Store purchase result…", "正在等待 App Store 购买结果…")
        case .restoring:
            return t("Restoring verified purchases…", "正在恢复已验证购买…")
        case .idle, .checkoutOpened, .pending, .succeeded, .notice, .cancelled, .failed:
            return t("Working…", "正在处理…")
        }
    }

    private var localizedActivityMessage: String? {
        switch commerce.activity {
        case .idle, .loadingProducts, .purchasing, .restoring:
            return nil
        case .checkoutOpened:
            return t(
                "Secure checkout opened in your browser. The app remains Free until you import a valid signed license.",
                "安全结账页已在浏览器中打开；在导入有效签名授权前，应用仍保持 Free。"
            )
        case .pending:
            return t(
                "The purchase is pending App Store approval. Pro will unlock only after Apple verifies the transaction.",
                "购买正在等待 App Store 批准；只有 Apple 验证交易后才会解锁 Pro。"
            )
        case .cancelled:
            return t(
                "The purchase was cancelled. No charge or entitlement change was recorded.",
                "购买已取消；没有产生扣款或权益变更。"
            )
        case .succeeded(let message), .notice(let message), .failed(let message):
            return localizedKnownMessage(message)
        }
    }

    private func localizedKnownMessage(_ message: String) -> String {
        guard isChinese else { return message }

        let exact: [String: String] = [
            "Pro is already active for this build.": "此版本已启用 Pro。",
            "Beta Preview access is temporary and is not a purchase.": "Beta Preview 权益是临时的，并不代表购买。",
            "Beta Preview does not create or restore purchases.": "Beta Preview 不会创建或恢复购买。",
            "Your verified App Store Pro purchase was restored.": "已恢复通过验证的 App Store Pro 购买。",
            "No verified Pro purchase was found for this Apple Account.": "此 Apple 账户下未找到通过验证的 Pro 购买。",
            "The signed Direct license was verified and stored securely.": "官网版签名授权已验证并安全保存。",
            "No saved Direct license was found on this Mac.": "此 Mac 上没有已保存的官网版授权。",
            "The saved signed license was verified.": "已验证保存的签名授权。",
            "The secure checkout page could not be opened.": "无法打开安全结账页。",
            "This Direct Beta build does not contain a valid preview access window.": "此官网 Beta 版本未包含有效的预览访问期限。",
            "Pro is active, but the App Store price is temporarily unavailable.": "Pro 已启用，但 App Store 价格暂时不可用。",
            "Pro is already active for this Apple Account.": "此 Apple 账户已启用 Pro。",
            "The verified transaction did not match the Pro lifetime product.": "已验证交易与 Pro 终身产品不匹配。",
            "Pro was unlocked by a verified App Store purchase.": "已通过验证的 App Store 购买解锁 Pro。",
            "The App Store returned an unknown purchase state.": "App Store 返回了未知的购买状态。",
            "The Pro lifetime product is not available from the App Store right now.": "Pro 终身产品当前无法从 App Store 获取。",
            "The App Store product is not configured as a non-consumable lifetime purchase.": "App Store 产品未配置为非消耗型终身购买。"
        ]
        if let translated = exact[message] {
            return translated
        }
        if message.hasPrefix("This Beta Preview is not active yet") {
            return "此 Beta Preview 尚未生效。"
        }
        if message.hasPrefix("This Beta Preview expired on") {
            return "此 Beta Preview 已过期。"
        }
        return message
    }

    private func localizedDirectReadinessReason(_ reason: String) -> String {
        guard isChinese else { return reason }
        switch reason {
        case "This release does not sell Direct licenses; Pro launches on the Mac App Store first.":
            return "首轮正式收费仅在 Mac App Store 上线；官网版授权尚未销售。"
        case "This build does not contain a valid HTTPS checkout address.":
            return "首轮正式收费仅在 Mac App Store 上线；官网版结账尚未开放。"
        case "This build does not contain a valid P256 license verification key.":
            return "官网版签名授权服务尚未启用；此版本不会接受无法验证的授权。"
        case "Purchasing and license import are disabled in Beta Preview builds.":
            return "Beta Preview 版本不会进行购买或导入授权。"
        case "Direct licensing is not available in the App Store edition.":
            return "App Store 版本不支持官网授权。"
        default:
            return reason
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
}
