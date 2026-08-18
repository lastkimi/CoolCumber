import SwiftUI

/// SettingsView V3 - Cleaned preference configuration screen.
/// Focuses purely on AI engine models and credentials.
struct SettingsView: View {
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var updater = UpdateManager.shared
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
                
                // Software Update Card
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.comfortable) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.tr("software_update"))
                                .font(DesignSystem.Typography.title)
                                .foregroundColor(DesignSystem.Colors.accentBrand)
                            Text(lang.tr("update_desc"))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        Spacer()
                        
                        Button(action: {
                            updater.checkForUpdates(isManual: true)
                        }) {
                            HStack(spacing: DesignSystem.Spacing.tight) {
                                if updater.isChecking {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11))
                                }
                                Text(updater.isChecking ? lang.tr("checking_updates") : lang.tr("check_updates"))
                                    .font(DesignSystem.Typography.headline)
                            }
                            .foregroundColor(DesignSystem.Colors.textInverse)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(DesignSystem.Colors.accentBrand)
                            .cornerRadius(DesignSystem.Corners.smallButton)
                        }
                        .buttonStyle(.plain)
                        .disabled(updater.isChecking)
                    }
                    
                    Divider().background(DesignSystem.Colors.divider)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.tr("current_version") + ": v\(updater.currentVersion)")
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            if updater.hasUpdate {
                                Text(lang.tr("new_version_available") + ": v\(updater.latestVersion)")
                                    .font(DesignSystem.Typography.headline)
                                    .foregroundColor(DesignSystem.Colors.statusHealthy)
                            }
                        }
                        
                        Spacer()
                        
                        Toggle(lang.tr("auto_check"), isOn: $updater.autoCheckUpdates)
                            .toggleStyle(.switch)
                    }
                    
                    if let msg = updater.statusMessage {
                        Text(msg)
                            .font(DesignSystem.Typography.headline)
                            .padding(DesignSystem.Spacing.normal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(updater.hasUpdate ? DesignSystem.Colors.statusHealthy.opacity(0.12) : DesignSystem.Colors.accentBrand.opacity(0.08))
                            .foregroundColor(updater.hasUpdate ? DesignSystem.Colors.statusHealthy : DesignSystem.Colors.accentBrand)
                            .cornerRadius(DesignSystem.Corners.normal)
                    }
                    
                    if updater.hasUpdate {
                        HStack(spacing: DesignSystem.Spacing.comfortable) {
                            Button(action: {
                                updater.downloadAndOpenRelease()
                            }) {
                                HStack(spacing: DesignSystem.Spacing.tight) {
                                    if updater.isDownloading {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 14, height: 14)
                                        Text(lang.tr("downloading"))
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text(lang.tr("update_now"))
                                    }
                                }
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textInverse)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(DesignSystem.Colors.statusHealthy)
                                .cornerRadius(DesignSystem.Corners.smallButton)
                            }
                            .buttonStyle(.plain)
                            .disabled(updater.isDownloading)
                            
                            Link(destination: URL(string: updater.releaseURL)!) {
                                HStack(spacing: 4) {
                                    Image(systemName: "safari")
                                    Text(lang.tr("view_on_github"))
                                }
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(DesignSystem.Colors.glassBgHover)
                                .cornerRadius(DesignSystem.Corners.smallButton)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.comfortable)
                .glassCard()
                
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
