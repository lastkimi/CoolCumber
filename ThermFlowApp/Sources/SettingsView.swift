import SwiftUI

/// SettingsView V3 - Cleaned preference configuration screen.
/// Focuses purely on AI engine models and credentials.
struct SettingsView: View {
    @ObservedObject private var lang = LanguageManager.shared
    @State private var selectedProvider = "deepseek"
    @State private var apiKey = ""
    @State private var saveStatus: String?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sectionGap) {
                // Header
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                    Text(lang.tr("pref_title"))
                        .font(DesignSystem.Typography.display)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    Text(lang.tr("pref_desc"))
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // AI Credentials Card
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
                    Text(lang.tr("ai_credentials"))
                        .font(DesignSystem.Typography.title)
                        .foregroundColor(DesignSystem.Colors.accentBrand)
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                        Text(lang.tr("ai_provider"))
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        HStack(spacing: DesignSystem.Spacing.normal) {
                            Button(action: {
                                selectedProvider = "deepseek"
                                loadApiKey(for: "deepseek")
                            }) {
                                Text("DeepSeek (Recommended)")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(selectedProvider == "deepseek" ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedProvider == "deepseek" ? DesignSystem.Colors.accentBrand : DesignSystem.Colors.glassBgHover)
                                    .cornerRadius(DesignSystem.Corners.normal)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.Corners.normal)
                                            .stroke(selectedProvider == "deepseek" ? Color.clear : DesignSystem.Colors.glassBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                selectedProvider = "qwen"
                                loadApiKey(for: "qwen")
                            }) {
                                Text("Qwen / DashScope")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(selectedProvider == "qwen" ? DesignSystem.Colors.textInverse : DesignSystem.Colors.textPrimary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(selectedProvider == "qwen" ? DesignSystem.Colors.accentBrand : DesignSystem.Colors.glassBgHover)
                                    .cornerRadius(DesignSystem.Corners.normal)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.Corners.normal)
                                            .stroke(selectedProvider == "qwen" ? Color.clear : DesignSystem.Colors.glassBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.tight) {
                        Text(lang.tr("api_key"))
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        ZStack(alignment: .leading) {
                            if apiKey.isEmpty {
                                Text("Enter API Key...")
                                    .foregroundColor(Color.white.opacity(0.35))
                                    .padding(.horizontal, DesignSystem.Spacing.normal)
                                    .font(DesignSystem.Typography.dataBody)
                            }
                            SecureField("", text: $apiKey)
                                .textFieldStyle(.plain)
                                .padding(DesignSystem.Spacing.normal)
                                .font(DesignSystem.Typography.dataBody)
                                .foregroundColor(.white)
                        }
                        .background(Color(white: 0.16))
                        .cornerRadius(DesignSystem.Corners.normal)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.Corners.normal)
                                .stroke(DesignSystem.Colors.glassBorder, lineWidth: 1)
                        )
                    }
                    
                    HStack {
                        Spacer()
                        Button(lang.tr("save_key")) {
                            UserDefaults.standard.set(selectedProvider, forKey: "ai_provider")
                            if KeychainHelper.shared.save(key: apiKey, account: selectedProvider) {
                                saveStatus = lang.currentLanguage == "zh" ? "密码凭证成功保存至系统 Keychain。" : "Credentials saved to Keychain."
                            } else {
                                saveStatus = lang.currentLanguage == "zh" ? "保存秘钥时发生错误。" : "Error saving credentials."
                            }
                            
                            // Clear status message after 3 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                saveStatus = nil
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accentBrand)
                        .foregroundColor(DesignSystem.Colors.textInverse)
                    }
                    
                    if let status = saveStatus {
                        Text(status)
                            .font(DesignSystem.Typography.headline)
                            .padding(DesignSystem.Spacing.normal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(status.contains("Error") || status.contains("错误") ? DesignSystem.Colors.statusCritical.opacity(0.12) : DesignSystem.Colors.statusHealthy.opacity(0.12))
                            .foregroundColor(status.contains("Error") ? DesignSystem.Colors.statusCritical : DesignSystem.Colors.statusHealthy)
                            .cornerRadius(DesignSystem.Corners.normal)
                    }
                }
                .padding(DesignSystem.Spacing.comfortable)
                .glassCard()
            }
            .padding(DesignSystem.Spacing.pageMargin)
        }
        .onAppear {
            selectedProvider = UserDefaults.standard.string(forKey: "ai_provider") ?? "deepseek"
            loadApiKey(for: selectedProvider)
        }
    }
    
    private func loadApiKey(for provider: String) {
        apiKey = KeychainHelper.shared.read(account: provider) ?? ""
        saveStatus = nil
    }
}
